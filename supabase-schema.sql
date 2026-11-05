-- ====================================================================
-- QueueNow - Real-Time Digital Token & Queue Management Database Schema
-- Supabase / PostgreSQL Schema & Security Rules
-- Tagline: Skip the Waiting. Track Your Turn.
-- ====================================================================

-- 1. Enable Required Extensions
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- 2. Drop existing objects if resetting (for clean install)
-- drop table if exists tokens cascade;
-- drop table if exists businesses cascade;
-- drop table if exists daily_analytics cascade;

-- ====================================================================
-- 3. BUSINESSES TABLE
-- ====================================================================
create table if not exists businesses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete cascade not null,
  business_name text not null,
  slug text unique not null,
  category text not null default 'Clinic',
  address text,
  average_service_minutes integer not null default 15,
  description text,
  is_queue_open boolean not null default true,
  is_booking_enabled boolean not null default true,
  daily_capacity integer not null default 200,
  current_serving_token text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Index for rapid lookup by slug (customer join & public display)
create index if not exists idx_businesses_slug on businesses(slug);
create index if not exists idx_businesses_owner on businesses(owner_id);

-- ====================================================================
-- 4. TOKENS TABLE
-- ====================================================================
create table if not exists tokens (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id) on delete cascade not null,
  token_number text not null,               -- e.g. 'QN-A101'
  sequence_number integer not null,         -- sequential counter for ordering
  customer_name text default 'Guest',
  customer_phone text,
  notes text,
  status text not null default 'waiting' check (status in ('waiting', 'serving', 'completed', 'skipped', 'cancelled')),
  created_at timestamptz not null default now(),
  called_at timestamptz,
  completed_at timestamptz,
  skipped_at timestamptz,
  cancelled_at timestamptz
);

-- Fast lookup indexes
create index if not exists idx_tokens_business_status on tokens(business_id, status, created_at);
create index if not exists idx_tokens_token_number on tokens(token_number);

-- ====================================================================
-- 5. DAILY ANALYTICS TABLE (Summary aggregation)
-- ====================================================================
create table if not exists daily_analytics (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references businesses(id) on delete cascade not null,
  report_date date not null default current_date,
  total_tokens integer not null default 0,
  completed_count integer not null default 0,
  skipped_count integer not null default 0,
  cancelled_count integer not null default 0,
  avg_wait_seconds integer not null default 0,
  avg_service_seconds integer not null default 0,
  peak_hour integer,
  created_at timestamptz not null default now(),
  unique (business_id, report_date)
);

-- ====================================================================
-- 6. ROW LEVEL SECURITY (RLS) POLICIES
-- ====================================================================
alter table businesses enable row level security;
alter table tokens enable row level security;
alter table daily_analytics enable row level security;

-- Businesses policies:
-- Anyone (public or authenticated) can view a business by slug (for queue joining & TV display)
create policy "Allow public read of active businesses"
  on businesses for select
  using (true);

-- Authenticated business owners can manage their own business
create policy "Allow owner to insert their business"
  on businesses for insert
  to authenticated
  with check (auth.uid() = owner_id);

create policy "Allow owner to update their business"
  on businesses for update
  to authenticated
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

create policy "Allow owner to delete their business"
  on businesses for delete
  to authenticated
  using (auth.uid() = owner_id);

-- Tokens policies:
-- Anyone can view tokens for an active queue (needed for live customer tracking & waiting room display)
create policy "Allow public read of tokens"
  on tokens for select
  using (true);

-- Anyone can insert a waiting token if business has bookings enabled and queue open
create policy "Allow public to generate token"
  on tokens for insert
  with check (
    exists (
      select 1 from businesses
      where businesses.id = tokens.business_id
        and businesses.is_queue_open = true
        and businesses.is_booking_enabled = true
    )
  );

-- Owner can update any token of their business
create policy "Allow owner to update business tokens"
  on tokens for update
  to authenticated
  using (
    exists (
      select 1 from businesses
      where businesses.id = tokens.business_id
        and businesses.owner_id = auth.uid()
    )
  );

-- Anyone can cancel their own token (if they have the token ID)
create policy "Allow customer to cancel their token"
  on tokens for update
  using (status = 'waiting')
  with check (status in ('cancelled', 'waiting'));

-- Daily Analytics policies
create policy "Allow owner to read their analytics"
  on daily_analytics for select
  to authenticated
  using (
    exists (
      select 1 from businesses
      where businesses.id = daily_analytics.business_id
        and businesses.owner_id = auth.uid()
    )
  );

-- ====================================================================
-- 7. ATOMIC QUEUE TRANSITION RPC FUNCTIONS
-- ====================================================================

-- Function: Generate a new token with atomic sequence numbering
create or replace function generate_token(
  p_business_id uuid,
  p_customer_name text default 'Guest',
  p_customer_phone text default null,
  p_notes text default null
)
returns tokens
language plpgsql
security definer
as $$
declare
  v_business businesses%rowtype;
  v_next_seq integer;
  v_token_code text;
  v_prefix text;
  v_new_token tokens%rowtype;
begin
  -- Validate business status
  select * into v_business from businesses where id = p_business_id;
  if not found then
    raise exception 'Business not found';
  end if;

  if not v_business.is_queue_open then
    raise exception 'Queue is currently closed.';
  end if;

  if not v_business.is_booking_enabled then
    raise exception 'New customer bookings are temporarily disabled.';
  end if;

  -- Determine next sequence for today
  select coalesce(max(sequence_number), 100) + 1
  into v_next_seq
  from tokens
  where business_id = p_business_id
    and created_at::date = current_date;

  -- Generate prefix from business category or name
  v_prefix := upper(substr(coalesce(v_business.category, 'A'), 1, 1));
  v_token_code := 'QN-' || v_prefix || v_next_seq::text;

  -- Insert token
  insert into tokens (
    business_id,
    token_number,
    sequence_number,
    customer_name,
    customer_phone,
    notes,
    status
  ) values (
    p_business_id,
    v_token_code,
    v_next_seq,
    coalesce(p_customer_name, 'Guest'),
    p_customer_phone,
    p_notes,
    'waiting'
  )
  returning * into v_new_token;

  return v_new_token;
end;
$$;

-- Function: CALL NEXT token (Atomically completes existing serving token and calls oldest waiting)
create or replace function call_next_token(p_business_id uuid)
returns tokens
language plpgsql
security definer
as $$
declare
  v_next_token tokens%rowtype;
begin
  -- 1. Safely complete currently serving token if one exists
  update tokens
  set status = 'completed',
      completed_at = now()
  where business_id = p_business_id
    and status = 'serving';

  -- 2. Select oldest waiting token with row lock to prevent race conditions
  select *
  into v_next_token
  from tokens
  where business_id = p_business_id
    and status = 'waiting'
  order by sequence_number asc
  limit 1
  for update skip locked;

  if not found then
    -- Clear current serving in business
    update businesses
    set current_serving_token = null,
        updated_at = now()
    where id = p_business_id;
    return null;
  end if;

  -- 3. Mark token as serving
  update tokens
  set status = 'serving',
      called_at = now()
  where id = v_next_token.id
  returning * into v_next_token;

  -- 4. Update business current serving token
  update businesses
  set current_serving_token = v_next_token.token_number,
      updated_at = now()
  where id = p_business_id;

  return v_next_token;
end;
$$;

-- Function: COMPLETE CURRENT token
create or replace function complete_current_token(
  p_business_id uuid,
  p_token_id uuid default null
)
returns tokens
language plpgsql
security definer
as $$
declare
  v_token tokens%rowtype;
begin
  if p_token_id is not null then
    update tokens
    set status = 'completed',
        completed_at = now()
    where id = p_token_id
      and business_id = p_business_id
    returning * into v_token;
  else
    update tokens
    set status = 'completed',
        completed_at = now()
    where business_id = p_business_id
      and status = 'serving'
    limit 1
    returning * into v_token;
  end if;

  update businesses
  set current_serving_token = null,
      updated_at = now()
  where id = p_business_id;

  return v_token;
end;
$$;

-- Function: SKIP CURRENT token
create or replace function skip_current_token(
  p_business_id uuid,
  p_token_id uuid default null
)
returns tokens
language plpgsql
security definer
as $$
declare
  v_token tokens%rowtype;
begin
  if p_token_id is not null then
    update tokens
    set status = 'skipped',
        skipped_at = now()
    where id = p_token_id
      and business_id = p_business_id
    returning * into v_token;
  else
    update tokens
    set status = 'skipped',
        skipped_at = now()
    where business_id = p_business_id
      and status = 'serving'
    limit 1
    returning * into v_token;
  end if;

  update businesses
  set current_serving_token = null,
      updated_at = now()
  where id = p_business_id;

  return v_token;
end;
$$;

-- Function: RECALL token (Restores skipped or missed token to serving)
create or replace function recall_token(
  p_business_id uuid,
  p_token_id uuid
)
returns tokens
language plpgsql
security definer
as $$
declare
  v_token tokens%rowtype;
begin
  -- Safely complete any existing serving token
  update tokens
  set status = 'completed',
      completed_at = now()
  where business_id = p_business_id
    and status = 'serving'
    and id != p_token_id;

  -- Restore chosen token to serving
  update tokens
  set status = 'serving',
      called_at = now(),
      skipped_at = null
  where id = p_token_id
    and business_id = p_business_id
  returning * into v_token;

  update businesses
  set current_serving_token = v_token.token_number,
      updated_at = now()
  where id = p_business_id;

  return v_token;
end;
$$;

-- ====================================================================
-- 8. SUPABASE REALTIME CONFIGURATION
-- ====================================================================
-- Enable Realtime replication for businesses and tokens
alter publication supabase_realtime add table businesses;
alter publication supabase_realtime add table tokens;

-- Set replica identity to full so update payloads contain full records
alter table businesses replica identity full;
alter table tokens replica identity full;

-- ====================================================================
-- 9. SEED DEMO BUSINESS (Optional demo helper)
-- ====================================================================
-- insert into businesses (owner_id, business_name, slug, category, address, average_service_minutes, description)
-- values ('00000000-0000-0000-0000-000000000000', 'Apex Health Clinic', 'apex-clinic', 'Clinic', '742 Evergreen Terrace', 12, 'Walk-in & Scheduled Medical Consultations');

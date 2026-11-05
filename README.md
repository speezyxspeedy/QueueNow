# QueueNow 🎫
> **Skip the Waiting. Track Your Turn.**

**QueueNow** is a modern, real-time digital token and queue management web application designed for clinics, salons, repair shops, consultancies, government service centres, and other customer-facing businesses.

Customers no longer waste time waiting in crowded lobbies. Instead, they scan a QR code, receive a digital token on their smartphone, monitor their exact position in line with smart wait-time estimation, and receive instant sound, speech, and browser notifications when their turn arrives.

---

## 🌟 Key Experiences

### 1. 🏢 Business Owner Management Portal
- **Real-Time Queue Console**: Instantly see who is currently serving and how long they have been at the counter.
- **One-Click Queue Controls**:
  - `CALL NEXT TOKEN`: Atomically completes the current customer, pulls the oldest waiting token, announces the token via synthesized audio chime and speech callout, and notifies the customer.
  - `COMPLETE CURRENT`: Safely marks the active ticket completed and records service duration.
  - `SKIP CURRENT`: Moves the current token to skipped status without losing customer record.
  - `RECALL TOKEN`: Restores any missed or skipped token back into the serving position.
  - `PAUSE / RESUME QUEUE`: Halts token calls and alerts customers in line.
  - `MANUAL WALK-IN`: Allows receptionists to quickly issue tickets to walk-ins without smartphones.
- **Dynamic Customer Table**: Filter by status (`Waiting`, `Serving`, `Completed`, `Skipped`, `Cancelled`), search by name or token number, and review wait times.
- **Business Profile Manager**: Create and customize profiles across multiple categories (Clinic, Salon, Repair shop, Government service centre, Consultancy, Other) with customizable average service durations and unique URL slugs.
- **Keyboard Shortcuts**: Press `Space` or `Enter` to call the next token immediately.

### 2. 📱 Mobile-First Customer Experience
- **Zero Friction**: Customers join the queue by scanning a QR code or opening a direct link (`?join=business-slug`). **No app installation or account registration required.**
- **Live Ticket Tracker**:
  - Real-time token number (e.g., `QN-C104`).
  - Position in line (e.g., `#2 in line`, `1 customer ahead`).
  - **Smart Estimated Waiting Time**: Dynamically calculated using historical service averages, queue length, and elapsed service times.
  - Live status transitions: `WAITING`, `YOUR TURN!`, `COMPLETED`, `SKIPPED`, `CANCELLED`.
- **Instant Turn Alerts**:
  - Screen pulses emerald green when called.
  - 3-tone harmonic reception chime via Web Audio API.
  - Native browser notification via the Web Notifications API.
  - Device vibration support for mobile devices.
- **Share & Cancel**: Customers can copy their tracking link or safely cancel their ticket if they need to leave.

### 3. 📺 Public Waiting Room TV Display (`?display=business-slug`)
- Designed for 1080p and 4K waiting room TVs and wall-mounted monitors.
- **High-Contrast Typography**: Readable from 20+ feet away.
- **Center Stage NOW SERVING**: Massive token display with counter designation.
- **Speech Synthesis Voice Announcements**: Uses the Web Speech API to clearly announce: *"Now serving token QN-C101, please proceed to counter."*
- **UP NEXT Ticker**: Highlights the next 3 waiting tokens in line.
- **Live Stats Bar**: Displays total waiting count, average wait time, and a scannable on-screen QR code for arriving customers.
- **Fullscreen Mode**: One-click toggle (`⛶`) to enter full-screen presentation mode.

### 4. 🖨️ QR Code Generation & Printable Counter Signs
- Real-time QR code generation for the business's public queue URL.
- **1-Click PNG Download**: High-resolution image export for digital signage and websites.
- **Print Waiting Room Counter Sign**: Built-in `@media print` styling that formats an 8.5x11 / A4 printable table-tent and door sign ready for the front counter.

### 5. 📊 Real-Time Analytics & CSV Export
- **Operational Metrics**: Total customers served, average service duration, average wait duration, and queue completion rate.
- **Hourly Customer Volume Distribution**: Visual bar chart showing traffic breakdown from 8:00 AM to 8:00 PM to identify peak rush hours.
- **Date Range Filters**: Filter metrics by `Today`, `Yesterday`, `Last 7 Days`, or `All Time`.
- **CSV Data Export**: One-click export of complete token logs with timestamps, wait durations, service durations, customer notes, and final statuses.

---

## 🛠️ Technology Stack

- **Frontend**: HTML5, Modern CSS3, Vanilla JavaScript (ES2022).
- **Styling**: Pure CSS3 with responsive layouts, dark navy SaaS theme, electric blue/purple accents, and print stylesheets (Zero dependencies on Tailwind or Bootstrap).
- **Backend / Database**: Supabase PostgreSQL with Row Level Security (RLS) and atomic RPC functions.
- **Realtime Mesh**: Dual-engine architecture:
  - **Supabase Realtime**: Live Postgres changes subscriptions.
  - **BroadcastChannel Mesh**: Cross-tab synchronized local storage engine for instant offline testing and live multi-screen preview.
- **Audio & Voice**: Web Audio API (synthesized chime) and Web Speech Synthesis API.
- **QR Codes**: Client-side QR generation with SVG fallback renderer.

---

## 📂 Project Structure

```text
├── index.html            # Complete semantic HTML5 structure for all 3 views
├── supabase-schema.sql   # Production PostgreSQL database schema, RLS, and RPCs
├── package.json          # Development scripts and project configuration
├── vite.config.ts        # Static web server & bundling configuration
├── tsconfig.json         # TypeScript configuration
└── src/
    ├── styles.css        # Pure CSS3 styling (Theme, TV display, cards, print)
    ├── app.js            # Core Vanilla JS engine (Queue logic, Audio, QR, Analytics)
    └── main.ts           # Bundler entry point linking styles and app engine
```

---

## 🗄️ Database Setup (Supabase)

The file `supabase-schema.sql` contains the complete production schema.

### Tables:
1. `businesses`: Holds business metadata, operating category, average service minutes, slug, daily capacity, and queue state.
2. `tokens`: Tracks each ticket, sequence number, customer details, timestamps (`created_at`, `called_at`, `completed_at`, `skipped_at`, `cancelled_at`), and status.
3. `daily_analytics`: Aggregates daily metrics and peak queue hours.

### Key RPC Functions:
- `call_next_token(p_business_id uuid)`: Safely completes any currently active token, acquires a row lock on the oldest waiting token, marks it as serving, and updates the business record.
- `generate_token(p_business_id uuid, ...)`: Computes sequence numbers and generates unique alphanumeric token codes (e.g., `QN-C101`).
- `complete_current_token(p_business_id uuid, p_token_id uuid)`
- `skip_current_token(p_business_id uuid, p_token_id uuid)`
- `recall_token(p_business_id uuid, p_token_id uuid)`

### Setup Instructions:
1. Create a project at [supabase.com](https://supabase.com).
2. Go to the **SQL Editor** in your Supabase dashboard.
3. Paste the contents of `supabase-schema.sql` and run the script.
4. In the QueueNow UI, click the connection indicator in the top navbar or open **Queue Settings**, enter your **Supabase URL** and **Anon Key**, and click **Save & Connect**.

---

## 🚀 Running Locally

```bash
# Install dependencies
npm install

# Start local development server
npm run dev
```

Visit `http://localhost:3000` in your browser.

### Multi-Tab Testing (Live Simulation):
1. **Tab 1**: Open `http://localhost:3000` (Business Owner Dashboard).
2. **Tab 2**: Open `http://localhost:3000/?join=apex-clinic` (Customer View).
3. **Tab 3**: Open `http://localhost:3000/?display=apex-clinic` (Public Waiting Room TV View).

Click **GET YOUR TOKEN** in Tab 2, then click **CALL NEXT TOKEN** in Tab 1 — Tab 2 and Tab 3 will update in real time with audio chimes and voice callouts!

---

## 🚢 Static Deployment

Because QueueNow is built with pure HTML5, CSS3, and Vanilla JavaScript, it can be hosted on any static web host:

- **Netlify**: Connect your Git repository or drag-and-drop the project directory.
- **Vercel**: Deploy as a static project.
- **GitHub Pages**: Push to a repository and enable GitHub Pages in settings.

Build output can be generated with:
```bash
npm run build
```

---

## 📄 License
Apache-2.0

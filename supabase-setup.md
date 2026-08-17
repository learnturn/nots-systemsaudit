# Making the audit data shared — Supabase setup

The app now supports two modes. It picks automatically:

- **Local mode** (what you have today) — no credentials configured, data lives in one browser.
- **Shared mode** — credentials configured, everything reads and writes to a Supabase Postgres database. Every tablet, laptop and phone sees the same data.

The header shows which mode you're in: **This device only**, **Synced**, **Saving…**, or **Not saved** with a red error bar if a write fails.

## 1. Create the database

1. Go to supabase.com, sign up, click **New project**.
2. Name it (e.g. `nots-quality-audit`), set a database password, pick the region closest to your sites (US East or US Central).
3. Wait for it to finish provisioning — about two minutes.

## 2. Build the tables

1. In the left sidebar click **SQL Editor** → **New query**.
2. Open `supabase-schema.sql` from this project, copy the whole file, paste it in, click **Run**.
3. You should see "Success. No rows returned." Click **Table Editor** and confirm you see `audits`, `findings`, `users`, `processes` and the rest.

This also seeds the four starting people and the two sample audit processes, so the app is usable the moment it connects. Edit or delete them in the Admin Portal.

## 3. Get your two credentials

**Project Settings** (gear icon) → **API**. Copy:

- **Project URL** — looks like `https://abcdefghijkl.supabase.co`
- **anon public** key — a long string starting `eyJ...`

Send both to me and I'll wire them into the app. Or paste them yourself: they go in the `window.NOTS_SUPABASE` block at the top of `QA Audit App.dc.html`. If you edit it yourself, tell me so I can rebuild `index.html` — the deployed file is a compiled copy and won't pick up the change on its own.

## 4. Deploy

Push to GitHub as you have been. GitHub Pages serves `index.html`; the app calls Supabase directly over HTTPS. Nothing else to host.

## What you should know before going live

**There is no login.** You chose the kiosk name list, which means the anon key ships inside the page and anyone who has your site URL can read and write this data — including employee names attached to performance findings. That's a real exposure, not a technicality. Three ways to reduce it, cheapest first:

1. Keep the GitHub repo **private** and don't publish the Pages URL. Obscurity only, but it's free.
2. Put the site behind a single shared password (Cloudflare Access on a free plan, or move hosting to Netlify and use password protection).
3. Add real Supabase logins — each person gets an email and password, and the database enforces what each role can do. This is the only option that actually holds up, and it's the one I'd pick before entering real employee data. Say the word and I'll build it.

**Countermeasure notes are append-only** at the database level: the anon key can insert and read them but has no permission to edit or delete. That's deliberate — the history is your audit evidence.

**Audit and finding IDs are allocated by the database**, not the browser, so two auditors submitting at the same second can't both get `A-0007`.

**Submitting an audit is atomic.** The audit, its checkpoint results, its findings and their retraining rows are written in one database call — you can't end up with an audit that's missing half its findings.

**No offline support.** You said you always have Wi-Fi. If a tablet loses signal mid-audit, the work in progress stays on screen, but submitting will fail with a red error bar and the auditor needs to reconnect and submit again. Tell me if you want the offline queue after all.

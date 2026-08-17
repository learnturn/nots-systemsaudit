# Prompt for Netlify — create the database + API for the NOTS Quality Audit app

Copy everything below the line into Netlify's AI assistant / agent.

---

Add a Netlify DB (Neon Postgres) database and serverless API to this site. The site is currently a single static `index.html` that stores all of its data in `localStorage` under the key `nots_qa_audit_v1`. I need that same data stored server-side in Postgres so every tablet, laptop and phone that opens the site sees the same audits and findings.

## Data model

Create these tables. Use `text` for the human-readable IDs (`A-0001`, `F-0001`) and keep a server-side sequence so two devices submitting at once never collide.

**users** — people who sign in (kiosk name list, no passwords)
`id` (pk), `name`, `employee_no`, `site`, `role` (one of: Auditor, Supervisor, Manager, Admin), `active` (bool, default true).

**processes** — audit templates built in the admin portal
`id` (pk), `name`, `area`, `audit_type`, `site` (a site name or the literal `All Sites`), `archived` (bool, default false), `created_at`.

**process_checkpoints** — the questions inside a process, order matters
`id` (pk), `process_id` (fk → processes, cascade delete), `position` (int), `text`, `standard`, `category`, `severity` (Critical / Major / Minor).

**audits** — one row per completed audit
`id` (pk, e.g. `A-0001`), `date` (date), `site`, `auditee_name`, `auditee_no`, `customer`, `shift`, `layer`, `audit_type`, `area`, `process_id`, `process_name` (denormalized snapshot — the process may be edited later), `auditor`, `checkpoints_audited` (int), `conforming` (int), `pct` (numeric), `result` (PASS / FAIL), `notes`, `created_at`.

**audit_results** — one row per checkpoint answered in that audit
`id` (pk), `audit_id` (fk → audits, cascade delete), `position` (int), `text`, `standard`, `result` (conform / break / na / empty), `note`, `finding_id` (nullable fk → findings).

**findings** — one row per non-conforming checkpoint
`id` (pk, e.g. `F-0001`), `audit_id` (fk → audits, cascade delete), `date` (date), `site`, `customer`, `shift`, `area`, `audit_type`, `auditor`, `process_name`, `auditee_name`, `employee` (employee number), `category`, `break_detail`, `standard`, `severity`, `impact`, `containment`, `repeat_status` (Unreviewed / Yes / No), `repeat_by_employee` (text[] of prior finding ids), `repeat_by_type` (text[] of prior finding ids), `reason`, `root_cause`, `cm_type`, `owner`, `target_date` (date, nullable), `actual_date` (date, nullable), `status`, `effectiveness`, `reported_to_customer`, `retrain_used` (bool), `created_at`, `updated_at`.

**finding_notes** — the countermeasure log; append-only, never updated or deleted
`id` (pk), `finding_id` (fk → findings, cascade delete), `created_at` (timestamptz, default now()), `author`, `text`.

**finding_retraining** — one row per finding
`finding_id` (pk, fk → findings, cascade delete), `removed` (Yes/No), `removed_date`, `topic`, `trainer`, `train_date`, `method`, `mon_start`, `mon_end`, `mon_observations` (int), `mon_by`, `mon_errors` (int), `check_date`, `check_by`, `check_result`, `outcome`, `narrative`.

**settings** — single row
`id` (pk, always 1), `conformance_target` (int, default 95), `repeat_window_days` (int, default 90).

Indexes on `audits(date)`, `audits(site)`, `findings(status)`, `findings(employee)`, `findings(category)`, `findings(date)`, `finding_notes(finding_id)`.

## API (Netlify Functions under /api)

- `GET /api/bootstrap` — returns everything the app needs on load in one payload: users, processes (with nested checkpoints ordered by position), audits (with nested audit_results), findings (with nested notes newest-first and retraining), settings.
- `POST /api/audits` — accepts one submitted audit with its checkpoint results and the findings to raise. In a single transaction: allocate the next `A-` id, insert the audit and its results, then for each break allocate the next `F-` id, run the repeat-finding check, and insert the finding plus an empty retraining row. Return the created audit and findings.
- The repeat check runs server-side against existing findings, using `settings.repeat_window_days`: signal one = same `employee` + same `category` within the window; signal two = same `audit_type` + `area` + `category` within the window. Store the matching ids in `repeat_by_employee` / `repeat_by_type` and leave `repeat_status` as `Unreviewed`.
- `PATCH /api/findings/:id` — partial update of any finding field (reason, root cause, countermeasure type, owner, dates, status, effectiveness, reported, repeat_status, retrain_used) and of the retraining row.
- `POST /api/findings/:id/notes` — append a countermeasure note with a server timestamp and author. Never expose update or delete for notes.
- `DELETE /api/audits/:id` — admin only. Deletes the audit and cascades to its results, findings, notes and retraining.
- `GET/POST/PATCH/DELETE /api/processes` and `/api/processes/:id` — full CRUD including nested checkpoints (replace-all on save is fine), plus duplicate.
- `GET/POST/PATCH/DELETE /api/users` and `/api/users/:id`.
- `PATCH /api/settings`.

Return JSON with camelCase keys so the front end can use them directly. Handle CORS for same-origin only.

## Also do this

- Seed the database on first deploy with the four users and two audit processes currently hardcoded in `index.html` (read them out of the file — look for `seedUsers` and `seedProcesses`).
- Do NOT rewrite my front-end UI. The only front-end change I want is swapping the `localStorage` read/write for calls to these endpoints: load from `/api/bootstrap` on mount, and write through on submit/patch/note-add/delete. Keep a local cache so the audit flow still works if the tablet drops Wi-Fi mid-audit and syncs the completed audit when it reconnects.
- Tell me the environment variables you set and what I need to configure in the Netlify dashboard.

---

## After Netlify finishes

Two things to be aware of:

1. There is no authentication — the kiosk name list is an honor system, and the API will be open to anyone who finds the URL. If findings data is sensitive (employee names tied to performance issues), add Netlify Identity or password protection before real use. Ask Netlify for that as a follow-up.

2. Once the database exists, the app's source of truth moves off `localStorage`. Bring the resulting endpoint list back to me and I will rewire `QA Audit App.dc.html` properly, so future edits stay in sync instead of Netlify's changes living only in the compiled `index.html`.

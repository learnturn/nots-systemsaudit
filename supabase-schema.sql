-- NOTS Quality Audit — Supabase schema
-- Paste this whole file into Supabase → SQL Editor → New query → Run.
-- Safe to re-run: it drops and rebuilds the schema.

drop function if exists submit_audit(jsonb);
drop function if exists next_audit_id();
drop function if exists next_finding_id();
drop table if exists finding_notes, finding_retraining, audit_results, findings, audits,
                     process_checkpoints, processes, users, settings cascade;
drop sequence if exists audit_seq, finding_seq;

create sequence audit_seq start 1;
create sequence finding_seq start 1;

create table users (
  id uuid primary key default gen_random_uuid(),
  name text not null default '',
  employee_no text not null default '',
  site text not null default '',
  role text not null default 'Auditor',
  position int not null default 0,
  created_at timestamptz not null default now()
);

create table processes (
  id uuid primary key default gen_random_uuid(),
  name text not null default '',
  area text not null default '',
  audit_type text not null default '',
  site text not null default 'All Sites',
  position int not null default 0,
  created_at timestamptz not null default now()
);

create table process_checkpoints (
  id uuid primary key default gen_random_uuid(),
  process_id uuid not null references processes(id) on delete cascade,
  position int not null default 0,
  text text not null default '',
  standard text not null default '',
  category text not null default '',
  severity text not null default 'Major'
);

create table audits (
  id text primary key,
  date date not null,
  site text not null default '',
  auditee_name text not null default '',
  auditee_no text not null default '',
  customer text not null default '',
  shift text not null default '',
  layer text not null default '',
  audit_type text not null default '',
  area text not null default '',
  process_id uuid references processes(id) on delete set null,
  process_name text not null default '',
  auditor text not null default '',
  checkpoints_audited int not null default 0,
  conforming int not null default 0,
  pct numeric not null default 0,
  result text not null default '',
  notes text not null default '',
  created_at timestamptz not null default now()
);

create table findings (
  id text primary key,
  audit_id text not null references audits(id) on delete cascade,
  date date not null,
  site text not null default '',
  customer text not null default '',
  shift text not null default '',
  area text not null default '',
  audit_type text not null default '',
  auditor text not null default '',
  process_name text not null default '',
  auditee_name text not null default '',
  employee text not null default '',
  category text not null default '',
  break_detail text not null default '',
  standard text not null default '',
  severity text not null default '',
  impact text not null default '',
  containment text not null default '',
  repeat_status text not null default 'Unreviewed',
  repeat_by_employee text[] not null default '{}',
  repeat_by_type text[] not null default '{}',
  reason text not null default '',
  root_cause text not null default 'Unreviewed',
  cm_type text not null default 'Unreviewed',
  owner text not null default '',
  target_date date,
  actual_date date,
  status text not null default 'Open',
  effectiveness text not null default 'Too Early to Verify',
  reported_to_customer text not null default 'Pending',
  retrain_used boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table audit_results (
  id uuid primary key default gen_random_uuid(),
  audit_id text not null references audits(id) on delete cascade,
  position int not null default 0,
  text text not null default '',
  standard text not null default '',
  result text not null default '',
  note text not null default '',
  finding_id text references findings(id) on delete set null
);

-- Append-only: the countermeasure history is evidence, so there is no update path.
create table finding_notes (
  id uuid primary key default gen_random_uuid(),
  finding_id text not null references findings(id) on delete cascade,
  created_at timestamptz not null default now(),
  author text not null default '',
  text text not null default ''
);

create table finding_retraining (
  finding_id text primary key references findings(id) on delete cascade,
  removed text not null default 'No',
  removed_date date,
  topic text not null default '',
  trainer text not null default '',
  train_date date,
  method text not null default '',
  mon_start date,
  mon_end date,
  mon_observations int,
  mon_by text not null default '',
  mon_errors int,
  check_date date,
  check_by text not null default '',
  check_result text not null default '',
  outcome text not null default '',
  narrative text not null default ''
);

create table settings (
  id int primary key default 1,
  conformance_target int not null default 95,
  repeat_window_days int not null default 90
);

insert into settings (id) values (1);

create index on audits (date desc);
create index on audits (site);
create index on findings (status);
create index on findings (employee);
create index on findings (category);
create index on findings (date desc);
create index on finding_notes (finding_id);
create index on audit_results (audit_id);
create index on process_checkpoints (process_id, position);

-- ---------------------------------------------------------------------------
-- ID allocation. Server-side so two tablets submitting at the same moment
-- can never both claim A-0007.
-- ---------------------------------------------------------------------------
create function next_audit_id() returns text language sql security definer as $$
  select 'A-' || lpad(nextval('audit_seq')::text, 4, '0');
$$;

create function next_finding_id() returns text language sql security definer as $$
  select 'F-' || lpad(nextval('finding_seq')::text, 4, '0');
$$;

-- ---------------------------------------------------------------------------
-- Submitting an audit is one atomic call: the audit, its checkpoint results,
-- its findings and their retraining rows all land together or not at all.
-- ---------------------------------------------------------------------------
create function submit_audit(payload jsonb) returns jsonb
language plpgsql security definer as $$
declare
  a jsonb := payload->'audit';
  aid text;
  fid text;
  fids text[] := '{}';
  f jsonb;
  r jsonb;
  rt jsonb;
begin
  aid := next_audit_id();

  insert into audits (id, date, site, auditee_name, auditee_no, customer, shift, layer,
                      audit_type, area, process_id, process_name, auditor,
                      checkpoints_audited, conforming, pct, result, notes)
  values (aid, (a->>'date')::date, a->>'site', a->>'auditeeName', a->>'auditeeNo',
          a->>'customer', a->>'shift', a->>'layer', a->>'auditType', a->>'area',
          nullif(a->>'processId','')::uuid, a->>'processName', a->>'auditor',
          (a->>'audited')::int, (a->>'conforming')::int, (a->>'pct')::numeric,
          a->>'result', coalesce(a->>'notes',''));

  for f in select * from jsonb_array_elements(coalesce(payload->'findings','[]'::jsonb)) loop
    fid := next_finding_id();
    fids := fids || fid;

    insert into findings (id, audit_id, date, site, customer, shift, area, audit_type,
                          auditor, process_name, auditee_name, employee, category,
                          break_detail, standard, severity, impact, containment,
                          repeat_by_employee, repeat_by_type)
    values (fid, aid, (f->>'date')::date, f->>'site', f->>'customer', f->>'shift',
            f->>'area', f->>'auditType', f->>'auditor', f->>'processName',
            f->>'auditeeName', f->>'employee', f->>'category', f->>'breakDetail',
            f->>'standard', f->>'severity', f->>'impact', f->>'containment',
            coalesce(array(select jsonb_array_elements_text(f->'repeatByEmployee')), '{}'),
            coalesce(array(select jsonb_array_elements_text(f->'repeatByType')), '{}'));

    rt := coalesce(f->'retrain', '{}'::jsonb);
    insert into finding_retraining (finding_id, removed, method, outcome, check_result)
    values (fid, coalesce(rt->>'removed','No'), coalesce(rt->>'method',''),
            coalesce(rt->>'outcome',''), coalesce(rt->>'checkResult',''));
  end loop;

  for r in select * from jsonb_array_elements(coalesce(payload->'results','[]'::jsonb)) loop
    insert into audit_results (audit_id, position, text, standard, result, note, finding_id)
    values (aid, (r->>'position')::int, r->>'text', coalesce(r->>'standard',''),
            r->>'result', coalesce(r->>'note',''),
            case when r->>'breakIndex' is null then null
                 else fids[(r->>'breakIndex')::int + 1] end);
  end loop;

  return jsonb_build_object('auditId', aid, 'findingIds', to_jsonb(fids));
end;
$$;

-- ---------------------------------------------------------------------------
-- Access. There is no login in this app (kiosk name list), so the public
-- anon key can read and write. See supabase-setup.md — this key ships in the
-- page and anyone with the URL can reach this data.
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['users','processes','process_checkpoints','audits',
                           'audit_results','findings','finding_notes',
                           'finding_retraining','settings']
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists anon_all on %I', t);
    execute format('create policy anon_all on %I for all to anon using (true) with check (true)', t);
  end loop;
end $$;

-- finding_notes stays append-only even for anon.
drop policy if exists anon_all on finding_notes;
create policy notes_read on finding_notes for select to anon using (true);
create policy notes_insert on finding_notes for insert to anon with check (true);

grant execute on function next_audit_id(), next_finding_id(), submit_audit(jsonb) to anon;

-- ---------------------------------------------------------------------------
-- Starting people and two sample processes so the app is usable immediately.
-- Edit or delete these in the app's Admin Portal.
-- ---------------------------------------------------------------------------
insert into users (name, employee_no, site, role, position) values
  ('J. Povolish',    'EE #2210', 'White, GA',                   'Auditor',    0),
  ('D. Reyes',       'EE #1188', 'White, GA',                   'Supervisor', 1),
  ('M. Sanders',     'EE #1042', 'White, GA',                   'Manager',    2),
  ('Home Office QA', 'EE #0001', 'Nashville, IL (Home Office)',  'Admin',      3);

with p as (
  insert into processes (name, area, audit_type, site, position)
  values ('Picking - Kanban Application', 'Picking', 'Standard Work Observation', 'All Sites', 0)
  returning id
)
insert into process_checkpoints (process_id, position, text, standard, category, severity)
select p.id, v.position, v.text, v.standard, v.category, v.severity from p, (values
  (0, 'Is the Kanban part number matched to the tote pick label before the card is applied?', 'Standard Work PIK-04, Step 6: match Kanban part number to tote pick label and scan-verify before applying the card.', 'Labeling / Kanban Error', 'Major'),
  (1, 'Is the scan-verify step performed on every tote, with no exceptions?', 'PIK-04, Step 6. Scan-verify is not optional at any volume.', 'System / Scan Error', 'Major'),
  (2, 'Are pick quantities correct against the pick list?', 'PIK-04, Step 4: count and confirm quantity against the pick list line.', 'Quality / Accuracy Error', 'Major'),
  (3, 'Are damaged or questionable parts pulled and routed to the hold area?', 'PIK-04, Step 9: any part in question goes to hold, never to staging.', 'Quality / Accuracy Error', 'Critical'),
  (4, 'Is the pick area free of loose Kanban cards not attached to a tote?', '5S standard: staging rail holds active cards only.', '5S / Housekeeping', 'Minor')
) as v(position, text, standard, category, severity);

with p as (
  insert into processes (name, area, audit_type, site, position)
  values ('Shipping - Trailer Load Verification', 'Shipping / Loading', 'Layered Process Audit', 'All Sites', 1)
  returning id
)
insert into process_checkpoints (process_id, position, text, standard, category, severity)
select p.id, v.position, v.text, v.standard, v.category, v.severity from p, (values
  (0, 'Does the BOL match the physical load count before the trailer is sealed?', 'SHP-02, Step 3: BOL count verified against physical count by the loader and confirmed by the checker.', 'Documentation Error', 'Critical'),
  (1, 'Is the seal number recorded on the BOL and legible?', 'SHP-02, Step 7: seal number written on the BOL and photographed.', 'Documentation Error', 'Major'),
  (2, 'Are trailer chocks and restraints in place during loading?', 'SAF-01: chock and restraint required before any PIT enters a trailer.', 'Safety Non-Conformance', 'Critical'),
  (3, 'Is the load blocked and braced to prevent shift in transit?', 'SHP-02, Step 5: void space blocked, load braced per customer spec.', 'Quality / Accuracy Error', 'Major')
) as v(position, text, standard, category, severity);

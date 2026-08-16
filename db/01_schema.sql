-- =============================================================================
-- LADS MEMBER PORTAL, DATABASE SCHEMA
-- Run once in Supabase SQL Editor. Safe to re-run.
--
-- Design principles:
--   1. Member data is private by default. Every table has RLS enabled and no
--      policy grants blanket read access.
--   2. Roles live in one place (profiles.role) and are checked by one function
--      so permissions can be audited in a single spot.
--   3. Membership is per academic year, so history survives board changes.
--      This is the continuity requirement: a member joining in 2026 still has
--      a visible record in 2031.
--   4. Nothing is ever hard-deleted. Records are archived, not destroyed.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- ENUMS
-- ---------------------------------------------------------------------------
do $$ begin
  create type user_role as enum ('member','committee_head','treasurer','executive');
exception when duplicate_object then null; end $$;

do $$ begin
  create type payment_status as enum ('unpaid','pending_verification','paid','waived');
exception when duplicate_object then null; end $$;

do $$ begin
  create type application_kind as enum ('IDRP','IVP','exchange','other');
exception when duplicate_object then null; end $$;

do $$ begin
  create type application_status as enum
    ('submitted','under_review','accepted','rejected','withdrawn');
exception when duplicate_object then null; end $$;

do $$ begin
  create type proposal_status as enum
    ('submitted','under_review','approved','declined','implemented');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- COMMITTEES  (reference data, publicly readable)
-- ---------------------------------------------------------------------------
create table if not exists public.committees (
  id          text primary key,           -- 'scientific', 'fundraising', ...
  name        text not null,
  description text,
  sort_order  int  not null default 0
);

insert into public.committees (id,name,sort_order) values
  ('scientific','Scientific Committee',1),
  ('fundraising','Fundraising Committee',2),
  ('exchange','Exchange Committee',3),
  ('training','Training Committee',4),
  ('public_health','Public Health Committee',5),
  ('voluntary','Voluntary Committee',6),
  ('activities','Activities Committee',7),
  ('editorial','Editorial Committee',8),
  ('social_media','Social Media Committee',9)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- PROFILES  (one row per logged-in person, keyed to Supabase Auth)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id             uuid primary key references auth.users(id) on delete cascade,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  full_name      text not null default '',
  email          text not null,
  phone          text,
  university     text check (university in ('BAU','LU','USJ')),
  academic_year  text,
  student_id     text,

  role           user_role not null default 'member',
  -- set only for committee_head: which committee they lead
  committee_id   text references public.committees(id),

  archived       boolean not null default false
);

create index if not exists profiles_role_idx on public.profiles(role);
create index if not exists profiles_committee_idx on public.profiles(committee_id);

-- ---------------------------------------------------------------------------
-- ROLE HELPERS
-- security definer so the function itself can read profiles without recursing
-- through the RLS policies that call it.
-- ---------------------------------------------------------------------------
create or replace function public.my_role()
returns user_role
language sql stable security definer set search_path = public
as $$ select role from public.profiles where id = auth.uid() $$;

create or replace function public.my_committee()
returns text
language sql stable security definer set search_path = public
as $$ select committee_id from public.profiles where id = auth.uid() $$;

create or replace function public.is_staff()
returns boolean
language sql stable security definer set search_path = public
as $$ select coalesce(
     (select role in ('committee_head','treasurer','executive')
        from public.profiles where id = auth.uid()), false) $$;

create or replace function public.is_exec()
returns boolean
language sql stable security definer set search_path = public
as $$ select coalesce(
     (select role = 'executive' from public.profiles where id = auth.uid()), false) $$;

create or replace function public.handles_money()
returns boolean
language sql stable security definer set search_path = public
as $$ select coalesce(
     (select role in ('treasurer','executive')
        from public.profiles where id = auth.uid()), false) $$;

-- Auto-create a profile the first time someone logs in.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email,
          coalesce(new.raw_user_meta_data->>'full_name',
                   new.raw_user_meta_data->>'name', ''))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- MEMBERSHIPS  (one row per member per academic year, the continuity record)
-- ---------------------------------------------------------------------------
create table if not exists public.memberships (
  id             uuid primary key default gen_random_uuid(),
  profile_id     uuid not null references public.profiles(id) on delete cascade,
  academic_year  text not null,                      -- '2026/2027'
  status         payment_status not null default 'unpaid',
  amount_usd     numeric(10,2) not null default 10.00,
  paid_on        date,
  due_on         date,
  method         text check (method in ('whish','Bank transfer','OMT','Cash')),
  proof_path     text,
  verified_by    uuid references public.profiles(id),
  verified_at    timestamptz,
  notes          text,
  created_at     timestamptz not null default now(),
  unique (profile_id, academic_year)
);

create index if not exists memberships_profile_idx on public.memberships(profile_id);
create index if not exists memberships_year_idx    on public.memberships(academic_year);

-- ---------------------------------------------------------------------------
-- EVENTS
-- ---------------------------------------------------------------------------
create table if not exists public.events (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  summary       text,
  description   text,
  committee_id  text references public.committees(id),
  starts_at     timestamptz not null,
  ends_at       timestamptz,
  location      text,
  capacity      int,
  members_only  boolean not null default true,
  registration_opens  timestamptz,
  registration_closes timestamptz,
  published     boolean not null default false,
  created_by    uuid references public.profiles(id),
  created_at    timestamptz not null default now()
);

create index if not exists events_start_idx on public.events(starts_at);

create table if not exists public.event_registrations (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events(id) on delete cascade,
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  registered_at timestamptz not null default now(),
  attended    boolean,
  cancelled   boolean not null default false,
  note        text,
  unique (event_id, profile_id)
);

create index if not exists event_regs_event_idx   on public.event_registrations(event_id);
create index if not exists event_regs_profile_idx on public.event_registrations(profile_id);

-- ---------------------------------------------------------------------------
-- APPLICATIONS  (IDRP, IVP, exchange)
-- ---------------------------------------------------------------------------
create table if not exists public.applications (
  id            uuid primary key default gen_random_uuid(),
  profile_id    uuid not null references public.profiles(id) on delete cascade,
  kind          application_kind not null,
  cycle         text not null,                 -- '2026/2027' or 'Summer 2027'
  committee_id  text references public.committees(id),
  motivation    text,
  answers       jsonb not null default '{}'::jsonb,
  status        application_status not null default 'submitted',
  reviewer_id   uuid references public.profiles(id),
  reviewer_note text,
  decided_at    timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists applications_profile_idx   on public.applications(profile_id);
create index if not exists applications_committee_idx on public.applications(committee_id);
create index if not exists applications_status_idx    on public.applications(status);

-- ---------------------------------------------------------------------------
-- PROJECT PROPOSALS
-- ---------------------------------------------------------------------------
create table if not exists public.proposals (
  id            uuid primary key default gen_random_uuid(),
  profile_id    uuid not null references public.profiles(id) on delete cascade,
  title         text not null,
  summary       text not null,
  committee_id  text references public.committees(id),
  needs         text,                          -- budget, people, materials
  status        proposal_status not null default 'submitted',
  reviewer_id   uuid references public.profiles(id),
  reviewer_note text,
  decided_at    timestamptz,
  created_at    timestamptz not null default now()
);

create index if not exists proposals_committee_idx on public.proposals(committee_id);
create index if not exists proposals_profile_idx   on public.proposals(profile_id);

-- ---------------------------------------------------------------------------
-- updated_at maintenance
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

drop trigger if exists applications_touch on public.applications;
create trigger applications_touch before update on public.applications
  for each row execute function public.touch_updated_at();

-- =============================================================================
-- ROW LEVEL SECURITY
-- Default deny. Every grant below is deliberate.
-- =============================================================================
alter table public.profiles            enable row level security;
alter table public.memberships         enable row level security;
alter table public.events              enable row level security;
alter table public.event_registrations enable row level security;
alter table public.applications        enable row level security;
alter table public.proposals           enable row level security;
alter table public.committees          enable row level security;

-- committees: reference data, any signed-in user may read
drop policy if exists committees_read on public.committees;
create policy committees_read on public.committees
  for select to authenticated using (true);

-- ---------------------------- PROFILES -------------------------------------
-- A member sees only themselves. Staff see all members.
drop policy if exists profiles_self_read on public.profiles;
create policy profiles_self_read on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_staff());

-- A member may edit their own contact details, but NOT their role.
drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and role = public.my_role());

-- Only the executive may change roles or edit other people.
drop policy if exists profiles_exec_update on public.profiles;
create policy profiles_exec_update on public.profiles
  for update to authenticated
  using (public.is_exec()) with check (public.is_exec());

-- --------------------------- MEMBERSHIPS -----------------------------------
-- Members read their own dues history. Treasurer and executive read all.
drop policy if exists memberships_read on public.memberships;
create policy memberships_read on public.memberships
  for select to authenticated
  using (profile_id = auth.uid() or public.handles_money());

-- Only treasurer/executive can create or change payment records.
drop policy if exists memberships_write on public.memberships;
create policy memberships_write on public.memberships
  for insert to authenticated with check (public.handles_money());

drop policy if exists memberships_update on public.memberships;
create policy memberships_update on public.memberships
  for update to authenticated
  using (public.handles_money()) with check (public.handles_money());

-- ------------------------------ EVENTS -------------------------------------
-- Published events visible to signed-in users; drafts only to staff.
drop policy if exists events_read on public.events;
create policy events_read on public.events
  for select to authenticated
  using (published or public.is_staff());

drop policy if exists events_write on public.events;
create policy events_write on public.events
  for insert to authenticated with check (public.is_staff());

drop policy if exists events_update on public.events;
create policy events_update on public.events
  for update to authenticated
  using (public.is_staff()) with check (public.is_staff());

-- ------------------------ EVENT REGISTRATIONS ------------------------------
-- Members see and manage only their own registrations. Staff see all.
drop policy if exists eventregs_read on public.event_registrations;
create policy eventregs_read on public.event_registrations
  for select to authenticated
  using (profile_id = auth.uid() or public.is_staff());

drop policy if exists eventregs_insert on public.event_registrations;
create policy eventregs_insert on public.event_registrations
  for insert to authenticated with check (profile_id = auth.uid());

drop policy if exists eventregs_update on public.event_registrations;
create policy eventregs_update on public.event_registrations
  for update to authenticated
  using (profile_id = auth.uid() or public.is_staff());

-- --------------------------- APPLICATIONS ----------------------------------
-- Applicant sees their own. Committee head sees applications to their own
-- committee only. Executive sees all. Treasurer has no special access here.
drop policy if exists applications_read on public.applications;
create policy applications_read on public.applications
  for select to authenticated
  using (
    profile_id = auth.uid()
    or public.is_exec()
    or (public.my_role() = 'committee_head' and committee_id = public.my_committee())
  );

drop policy if exists applications_insert on public.applications;
create policy applications_insert on public.applications
  for insert to authenticated with check (profile_id = auth.uid());

-- Applicant may withdraw; reviewers may decide.
drop policy if exists applications_update on public.applications;
create policy applications_update on public.applications
  for update to authenticated
  using (
    profile_id = auth.uid()
    or public.is_exec()
    or (public.my_role() = 'committee_head' and committee_id = public.my_committee())
  );

-- ---------------------------- PROPOSALS ------------------------------------
drop policy if exists proposals_read on public.proposals;
create policy proposals_read on public.proposals
  for select to authenticated
  using (
    profile_id = auth.uid()
    or public.is_exec()
    or (public.my_role() = 'committee_head' and committee_id = public.my_committee())
  );

drop policy if exists proposals_insert on public.proposals;
create policy proposals_insert on public.proposals
  for insert to authenticated with check (profile_id = auth.uid());

drop policy if exists proposals_update on public.proposals;
create policy proposals_update on public.proposals
  for update to authenticated
  using (
    public.is_exec()
    or (public.my_role() = 'committee_head' and committee_id = public.my_committee())
  );

-- =============================================================================
-- STORAGE: payment proofs stay private, readable only by treasurer/executive
-- =============================================================================
insert into storage.buckets (id,name,public)
values ('payment-proofs','payment-proofs',false)
on conflict (id) do nothing;

drop policy if exists proofs_upload on storage.objects;
create policy proofs_upload on storage.objects
  for insert to authenticated
  with check (bucket_id = 'payment-proofs');

drop policy if exists proofs_read on storage.objects;
create policy proofs_read on storage.objects
  for select to authenticated
  using (bucket_id = 'payment-proofs' and public.handles_money());

-- =============================================================================
-- BOOTSTRAP: make yourself executive after your first login.
-- Run this ONCE, replacing the email, then delete these lines.
--
--   update public.profiles set role = 'executive'
--   where email = 'vicepresident@ladslb.org';
-- =============================================================================

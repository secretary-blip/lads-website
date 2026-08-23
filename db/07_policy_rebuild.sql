-- =============================================================================
-- LADS PORTAL, STAGE 7: EVERY POLICY, REBUILT
-- Run in the Supabase SQL Editor after 06. Safe to re-run, any number of times.
--
-- WHY THIS FILE REPLACES THE PIECEMEAL FIXES
--
-- Three security policies had to be corrected during setup, and they all failed
-- the same way: each was written for the situation that existed when it was
-- written, and stopped being right when the situation changed.
--
--   "anyone can register"  was `to anon` only. Correct when nobody had an
--                          account. Wrong the moment members could sign in
--                          first, which is now the order we recommend.
--
--   guard_role_changes     required is_exec(), which is false in the SQL Editor
--                          because there is no signed-in user. It locked out the
--                          one place you would go to fix a bad role.
--
--   committees_read        was `to authenticated`. The Join form is filled in by
--                          people with no account, so the committee list came
--                          back empty for exactly the audience it was for.
--
-- Rather than patch a fourth, this file states the whole permission model in one
-- place, checked against every real flow. From here on, this is the file to read
-- and the file to change.
--
-- WHO CAN DO WHAT
--
--                        | own data | all members | dues    | applications      | events
--   anon (no account)    | register and upload a payment proof, read committees
--   member               | read/edit | no          | own     | own               | published
--   committee_head       | read/edit | read        | own     | own committee     | all + create
--   treasurer            | read/edit | read        | all r/w | own               | all + create
--   executive            | read/edit | read/edit   | all r   | all               | all + create
--
-- Every rule below is enforced by Postgres, not by the website. A bug in a page
-- cannot widen any of it.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. ROW-LEVEL SECURITY ON, EVERYWHERE, NO EXCEPTIONS
--
-- A table with RLS switched off is readable by anyone holding the publishable
-- key, which is printed in the page source of every page on the site. This is
-- the single most important statement in the file.
-- ---------------------------------------------------------------------------
alter table public.committees           enable row level security;
alter table public.profiles             enable row level security;
alter table public.memberships          enable row level security;
alter table public.events               enable row level security;
alter table public.event_registrations  enable row level security;
alter table public.applications         enable row level security;
alter table public.proposals            enable row level security;
alter table public.registrations        enable row level security;


-- ---------------------------------------------------------------------------
-- 2. CLEAR OUT EVERY OLD POLICY BY NAME
--
-- Policies accumulate. Two policies on the same table are OR'd together, so an
-- old permissive one silently defeats a new strict one, and nothing warns you.
-- ---------------------------------------------------------------------------
do $$
declare p record;
begin
  for p in
    select policyname, tablename
      from pg_policies
     where schemaname = 'public'
       and tablename in ('committees','profiles','memberships','events',
                         'event_registrations','applications','proposals',
                         'registrations')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;


-- ---------------------------------------------------------------------------
-- 3. COMMITTEES
-- Reference data. Names and descriptions are already published on the public
-- Committees page, so there is nothing here that is not already visible.
-- Anon needs it for the deputy head section of the Join form.
-- ---------------------------------------------------------------------------
create policy committees_read on public.committees
  for select to anon, authenticated using (true);

-- So descriptions can be corrected from a future admin page rather than by
-- someone editing SQL. Riad's requirement: nobody should need the backend.
create policy committees_exec_update on public.committees
  for update to authenticated
  using (public.is_exec()) with check (public.is_exec());


-- ---------------------------------------------------------------------------
-- 4. PROFILES
-- ---------------------------------------------------------------------------

-- A member sees themselves. Staff see everyone, because committee heads have to
-- be able to contact the people who volunteered for their committee.
create policy profiles_read on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_staff());

-- Edit your own contact details. The role column is protected by
-- guard_role_changes as well, so this holds even if this policy is rewritten.
create policy profiles_self_update on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy profiles_exec_update on public.profiles
  for update to authenticated
  using (public.is_exec()) with check (public.is_exec());

-- No INSERT policy on purpose. Profiles are created only by handle_new_user,
-- which runs as SECURITY DEFINER when an account is confirmed. Nobody can
-- fabricate a profile row through the API.

-- No DELETE policy on purpose. Members are archived, never deleted, so
-- historical membership counts stay accurate for grant applications.


-- ---------------------------------------------------------------------------
-- 5. MEMBERSHIPS, the money
-- ---------------------------------------------------------------------------
create policy memberships_read on public.memberships
  for select to authenticated
  using (profile_id = auth.uid() or public.handles_money());

create policy memberships_write on public.memberships
  for insert to authenticated
  with check (public.handles_money());

create policy memberships_update on public.memberships
  for update to authenticated
  using (public.handles_money()) with check (public.handles_money());

-- Deliberately NOT readable by committee heads. Nine people do not need to know
-- who has and has not paid.


-- ---------------------------------------------------------------------------
-- 6. REGISTRATIONS, the public Join form
-- ---------------------------------------------------------------------------

-- Both roles. Someone who created an account first is `authenticated`, and that
-- is the order the Join page now recommends.
create policy registrations_insert on public.registrations
  for insert to anon, authenticated
  with check (true);

-- Only the people who handle money can read them. They contain phone numbers,
-- payment methods and screenshots.
create policy registrations_staff_read on public.registrations
  for select to authenticated
  using (public.handles_money());

create policy registrations_staff_update on public.registrations
  for update to authenticated
  using (public.handles_money()) with check (public.handles_money());

-- No DELETE. Registrations are a financial record.


-- ---------------------------------------------------------------------------
-- 7. EVENTS
-- ---------------------------------------------------------------------------
create policy events_read on public.events
  for select to authenticated
  using (published or public.is_staff());

create policy events_write on public.events
  for insert to authenticated with check (public.is_staff());

create policy events_update on public.events
  for update to authenticated
  using (public.is_staff()) with check (public.is_staff());

-- No DELETE. Unpublish instead, so attendance history is never orphaned.


-- ---------------------------------------------------------------------------
-- 8. EVENT REGISTRATIONS
-- ---------------------------------------------------------------------------
create policy eventregs_read on public.event_registrations
  for select to authenticated
  using (profile_id = auth.uid() or public.is_staff());

create policy eventregs_insert on public.event_registrations
  for insert to authenticated
  with check (profile_id = auth.uid() or public.is_staff());

create policy eventregs_update on public.event_registrations
  for update to authenticated
  using (profile_id = auth.uid() or public.is_staff())
  with check (profile_id = auth.uid() or public.is_staff());

-- Attendance and capacity are enforced by triggers in 04_security.sql, because
-- a row-level policy controls which rows you may touch, not which columns.


-- ---------------------------------------------------------------------------
-- 9. APPLICATIONS
-- ---------------------------------------------------------------------------
create policy applications_read on public.applications
  for select to authenticated
  using (
    profile_id = auth.uid()
    or public.is_exec()
    or (public.my_role() = 'committee_head' and committee_id = public.my_committee())
  );

create policy applications_insert on public.applications
  for insert to authenticated with check (profile_id = auth.uid());

create policy applications_update on public.applications
  for update to authenticated
  using (
    profile_id = auth.uid()
    or public.is_exec()
    or (public.my_role() = 'committee_head' and committee_id = public.my_committee())
  )
  with check (
    profile_id = auth.uid()
    or public.is_exec()
    or (public.my_role() = 'committee_head' and committee_id = public.my_committee())
  );

-- The applicant may only withdraw. guard_applications enforces that, since this
-- policy cannot express "you may change this column but not that one".


-- ---------------------------------------------------------------------------
-- 10. PROPOSALS
-- ---------------------------------------------------------------------------
create policy proposals_read on public.proposals
  for select to authenticated
  using (
    profile_id = auth.uid()
    or public.is_exec()
    or (public.my_role() = 'committee_head' and committee_id = public.my_committee())
  );

create policy proposals_insert on public.proposals
  for insert to authenticated with check (profile_id = auth.uid());

create policy proposals_update on public.proposals
  for update to authenticated
  using (
    public.is_exec()
    or (public.my_role() = 'committee_head' and committee_id = public.my_committee())
  )
  with check (
    public.is_exec()
    or (public.my_role() = 'committee_head' and committee_id = public.my_committee())
  );


-- ---------------------------------------------------------------------------
-- 11. STORAGE, payment screenshots
-- ---------------------------------------------------------------------------
do $$
begin
  drop policy if exists "anyone can upload proof" on storage.objects;
  drop policy if exists proofs_upload on storage.objects;
  drop policy if exists proofs_read on storage.objects;
  drop policy if exists "staff can read payment proofs" on storage.objects;

  -- Anyone may upload, because the person paying has no account yet.
  create policy proofs_upload on storage.objects
    for insert to anon, authenticated
    with check (bucket_id = 'payment-proofs');

  -- Only the people who handle money may look.
  create policy proofs_read on storage.objects
    for select to authenticated
    using (bucket_id = 'payment-proofs' and public.handles_money());

  -- No update or delete policy. A payment screenshot is evidence; once
  -- uploaded it cannot be replaced or removed through the API.
exception
  when insufficient_privilege then
    raise notice 'Storage policies need to be set from the dashboard on this project. See docs.';
end $$;

update storage.buckets
   set public = false,
       file_size_limit = 5242880,
       allowed_mime_types = array['image/png','image/jpeg','image/webp','image/heic','application/pdf']
 where id = 'payment-proofs';


-- =============================================================================
-- Now run 08_healthcheck.sql, then:  select * from public.health_check();
-- =============================================================================

-- =============================================================================
-- LADS PORTAL, STAGE 13: ROW-LEVEL SECURITY FOR THE NEW ARCHITECTURE
-- Run after 12. Safe to re-run.
--
-- One file states the entire permission model. Every existing policy is dropped
-- by name first: two policies on one table are OR'd together, so an old
-- permissive rule silently defeats a new strict one and nothing warns you.
--
--                      | own record        | everyone else
--   member             | read, edit        | nothing
--   committee_head     | read, edit        | applications and proposals for
--                      |                   | their own committee. No payments.
--   admin              | read, edit        | everything except role changes
--                      |                   | reserved to super_admin by policy
--   super_admin        | read, edit        | everything
--
-- Columns are not controlled here. A policy decides which ROWS you may touch,
-- never which COLUMNS, which is why guard_membership and guard_role_changes in
-- file 12 exist. Without them, "you may update your own membership" would also
-- mean "you may mark your own membership paid".
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. SECURITY ON, EVERYWHERE
-- A table with RLS off is readable by anyone holding the publishable key, and
-- that key is printed in the source of every page on the site.
-- ---------------------------------------------------------------------------
alter table public.committees          enable row level security;
alter table public.profiles            enable row level security;
alter table public.memberships         enable row level security;
alter table public.events              enable row level security;
alter table public.event_registrations enable row level security;
alter table public.applications        enable row level security;
alter table public.proposals           enable row level security;


-- ---------------------------------------------------------------------------
-- 2. CLEAR EVERY EXISTING POLICY
-- ---------------------------------------------------------------------------
do $$
declare p record;
begin
  for p in
    select policyname, tablename from pg_policies
     where schemaname = 'public'
       and tablename in ('committees','profiles','memberships','events',
                         'event_registrations','applications','proposals')
  loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;


-- ---------------------------------------------------------------------------
-- 3. COMMITTEES
-- ---------------------------------------------------------------------------
create policy committees_read on public.committees
  for select to anon, authenticated using (true);

create policy committees_admin_write on public.committees
  for insert to authenticated with check (public.is_admin());

create policy committees_admin_update on public.committees
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy committees_admin_delete on public.committees
  for delete to authenticated using (public.is_admin());


-- ---------------------------------------------------------------------------
-- 4. PROFILES
--
-- Committee heads can read profiles so they can contact the people who applied
-- to their committee. They cannot read memberships, so contact details do not
-- come with sight of anyone's payments.
-- ---------------------------------------------------------------------------
create policy profiles_read on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_admin() or public.is_committee_head());

create policy profiles_self_update on public.profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy profiles_admin_update on public.profiles
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- No INSERT policy. Profiles are created only by handle_new_user, which runs
-- as SECURITY DEFINER when an account is confirmed. Nobody can fabricate one.
-- No DELETE policy. People are archived, so historical counts stay accurate.


-- ---------------------------------------------------------------------------
-- 5. MEMBERSHIPS
--
-- A member creates and updates their own. What they may set is limited by
-- guard_membership, not by this policy.
-- ---------------------------------------------------------------------------
create policy memberships_read on public.memberships
  for select to authenticated
  using (profile_id = auth.uid() or public.is_admin());

create policy memberships_insert on public.memberships
  for insert to authenticated
  with check (profile_id = auth.uid() or public.is_admin());

create policy memberships_update on public.memberships
  for update to authenticated
  using (profile_id = auth.uid() or public.is_admin())
  with check (profile_id = auth.uid() or public.is_admin());

-- No DELETE. A payment record is not something anyone deletes through a website.


-- ---------------------------------------------------------------------------
-- 6. APPLICATIONS
--
-- No capacity check, no application limit, by instruction. Anyone signed in may
-- apply, as many times as the board is willing to read.
-- ---------------------------------------------------------------------------
create policy applications_read on public.applications
  for select to authenticated
  using (
    profile_id = auth.uid()
    or public.is_admin()
    or (public.is_committee_head() and committee_id = public.my_committee())
  );

create policy applications_insert on public.applications
  for insert to authenticated
  with check (profile_id = auth.uid());

create policy applications_update on public.applications
  for update to authenticated
  using (
    profile_id = auth.uid()
    or public.is_admin()
    or (public.is_committee_head() and committee_id = public.my_committee())
  )
  with check (
    profile_id = auth.uid()
    or public.is_admin()
    or (public.is_committee_head() and committee_id = public.my_committee())
  );


-- An applicant may edit a submission that has not been looked at, and may
-- withdraw. They may not decide it, and they may not decide their own.
create or replace function public.guard_applications()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare reviewer boolean;
begin
  reviewer := public.is_admin() or (
    public.is_committee_head()
    and coalesce(new.committee_id, old.committee_id) = public.my_committee()
  );

  if tg_op = 'INSERT' then
    if not reviewer then
      new.status        := 'submitted'::application_status;
      new.reviewer_id   := null;
      new.reviewer_note := null;
      new.decided_at    := null;
    end if;
    return new;
  end if;

  -- Nobody decides their own application, whatever role they hold.
  if new.status is distinct from old.status
     and new.profile_id = auth.uid()
     and new.status <> 'withdrawn'::application_status then
    raise exception 'You cannot decide your own application';
  end if;

  if not reviewer then
    if new.status is distinct from old.status
       and new.status <> 'withdrawn'::application_status then
      raise exception 'Only a reviewer may change the status of an application';
    end if;
    if new.reviewer_id   is distinct from old.reviewer_id
    or new.reviewer_note is distinct from old.reviewer_note
    or new.decided_at    is distinct from old.decided_at
    or new.profile_id    is distinct from old.profile_id then
      raise exception 'Only a reviewer may change that';
    end if;
    if old.status <> 'submitted'::application_status then
      raise exception 'This application is already under review and can no longer be edited';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists guard_applications_trg on public.applications;
create trigger guard_applications_trg
  before insert or update on public.applications
  for each row execute function public.guard_applications();


-- ---------------------------------------------------------------------------
-- 7. EVENTS
-- ---------------------------------------------------------------------------
create policy events_read on public.events
  for select to authenticated
  using (published or public.is_admin() or public.is_committee_head());

create policy events_write on public.events
  for insert to authenticated
  with check (public.is_admin() or public.is_committee_head());

create policy events_update on public.events
  for update to authenticated
  using (public.is_admin() or public.is_committee_head())
  with check (public.is_admin() or public.is_committee_head());


-- ---------------------------------------------------------------------------
-- 8. EVENT REGISTRATIONS
-- ---------------------------------------------------------------------------
create policy eventregs_read on public.event_registrations
  for select to authenticated
  using (profile_id = auth.uid() or public.is_admin() or public.is_committee_head());

create policy eventregs_insert on public.event_registrations
  for insert to authenticated
  with check (profile_id = auth.uid() or public.is_admin());

create policy eventregs_update on public.event_registrations
  for update to authenticated
  using (profile_id = auth.uid() or public.is_admin() or public.is_committee_head())
  with check (profile_id = auth.uid() or public.is_admin() or public.is_committee_head());


-- ---------------------------------------------------------------------------
-- 9. PROPOSALS
-- ---------------------------------------------------------------------------
create policy proposals_read on public.proposals
  for select to authenticated
  using (
    profile_id = auth.uid()
    or public.is_admin()
    or (public.is_committee_head() and committee_id = public.my_committee())
  );

create policy proposals_insert on public.proposals
  for insert to authenticated
  with check (profile_id = auth.uid());

create policy proposals_update on public.proposals
  for update to authenticated
  using (
    public.is_admin()
    or (public.is_committee_head() and committee_id = public.my_committee())
  )
  with check (
    public.is_admin()
    or (public.is_committee_head() and committee_id = public.my_committee())
  );


-- ---------------------------------------------------------------------------
-- 10. PAYMENT PROOFS
--
-- Private bucket. A member may read and write only inside a folder named after
-- their own user id, so the path is the permission:
--
--     payment-proofs/<auth.uid()>/whatever.png
--
-- Anything not in that shape is admin-only, which is what happens to the files
-- uploaded by the old anonymous form. Those keep working for review and are
-- simply not readable by members.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('payment-proofs','payment-proofs', false)
on conflict (id) do nothing;

update storage.buckets
   set public = false,
       file_size_limit = 5242880,
       allowed_mime_types = array['image/png','image/jpeg','image/webp','image/heic','application/pdf']
 where id = 'payment-proofs';

do $$
begin
  drop policy if exists "anyone can upload proof"      on storage.objects;
  drop policy if exists proofs_upload                  on storage.objects;
  drop policy if exists proofs_read                    on storage.objects;
  drop policy if exists "staff can read payment proofs" on storage.objects;
  drop policy if exists proofs_own_read                on storage.objects;
  drop policy if exists proofs_own_write               on storage.objects;
  drop policy if exists proofs_admin_read              on storage.objects;

  create policy proofs_own_write on storage.objects
    for insert to authenticated
    with check (
      bucket_id = 'payment-proofs'
      and (storage.foldername(name))[1] = auth.uid()::text
    );

  create policy proofs_own_read on storage.objects
    for select to authenticated
    using (
      bucket_id = 'payment-proofs'
      and (storage.foldername(name))[1] = auth.uid()::text
    );

  create policy proofs_admin_read on storage.objects
    for select to authenticated
    using (bucket_id = 'payment-proofs' and public.is_admin());

exception
  when insufficient_privilege then
    raise notice 'Storage policies must be set from the dashboard on this project. See docs/EMAIL_SETUP.md style instructions in the migration notes.';
end $$;


-- =============================================================================
-- Then run 14_verify.sql and read the report.
-- =============================================================================

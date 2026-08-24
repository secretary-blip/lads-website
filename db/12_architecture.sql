-- =============================================================================
-- LADS PORTAL, STAGE 12: THE NEW ARCHITECTURE
-- Run AFTER 11_new_enum_values.sql, as a separate snippet. Safe to re-run.
--
-- WHAT THIS DOES, AND WHAT IT DELIBERATELY DOES NOT DO
--
-- Three concepts are now kept strictly apart:
--
--   ACCOUNT      auth.users + profiles. Signing up creates a profile and
--                nothing else. No membership, no application. A person can log
--                in having paid nothing.
--
--   MEMBERSHIP   one row per profile per academic year, carrying the payment.
--                unpaid -> pending -> paid, or rejected.
--
--   COMMITTEE    an application that an admin accepts. Acceptance is what sets
--                profiles.committee_id. There is no capacity check anywhere in
--                this file, by instruction, and none should be added.
--
-- NOTHING IS DROPPED. The old `registrations` table is copied out and then
-- RENAMED to `registrations_archive`. If any part of this migration is wrong,
-- the original rows are still sitting there to compare against. Drop it
-- yourself, later, once you have checked the results.
--
-- Old enum values (treasurer, executive, pending_verification, waived) stay
-- defined. Removing an enum value means rebuilding the type and every column
-- using it, which is precisely the destructive operation to avoid here.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. PROFILES gains the survey, and loses nothing
--
-- interests and interest_details move here from registrations. They describe a
-- person, not a payment, so this is where they belonged. Keeping them on the
-- profile also means the member can edit them later, which they could not do
-- when the answers were locked inside a one-off form submission.
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists interests        text[],
  add column if not exists interest_details jsonb not null default '{}'::jsonb;


-- ---------------------------------------------------------------------------
-- 2. ROLE HELPERS
--
-- Every permission decision goes through these, so the whole model can be
-- audited by reading four small functions. SECURITY DEFINER so they can read
-- profiles without recursing through the policies that call them.
-- ---------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce((select role in ('admin','super_admin')
                         from public.profiles where id = auth.uid()), false) $$;

create or replace function public.is_super_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce((select role = 'super_admin'
                         from public.profiles where id = auth.uid()), false) $$;

-- Kept so committee heads can review applications to their own committee
-- without gaining sight of anybody's payment records.
create or replace function public.is_committee_head()
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce((select role = 'committee_head'
                         from public.profiles where id = auth.uid()), false) $$;

create or replace function public.my_committee()
returns text language sql stable security definer set search_path = public
as $$ select committee_id from public.profiles where id = auth.uid() $$;


-- ---------------------------------------------------------------------------
-- 3. MOVE EXISTING PEOPLE ONTO THE NEW ROLES
--
-- The guard trigger on profiles refuses role changes unless an executive is
-- making them, and in the SQL Editor there is no signed-in user. Disable it for
-- this one statement rather than weakening it permanently.
-- ---------------------------------------------------------------------------
do $$
begin
  begin
    execute 'alter table public.profiles disable trigger user';
  exception when others then
    -- Not the table owner on this project. The guard already allows changes
    -- when auth.uid() is null, which is the case in the SQL Editor, so the
    -- updates below should still succeed.
    raise notice 'Could not disable triggers; relying on the guard allowing admin-context changes.';
  end;

  update public.profiles set role = 'super_admin' where role::text = 'executive';
  update public.profiles set role = 'admin'       where role::text = 'treasurer';
  -- committee_head and member are unchanged.

  begin
    execute 'alter table public.profiles enable trigger user';
  exception when others then null;
  end;
end $$;


-- ---------------------------------------------------------------------------
-- 4. MEMBERSHIP STATUS, RENAMED
-- pending_verification becomes pending. waived becomes paid, because a waived
-- member is a member in good standing and the new model has no separate word
-- for it; the reason is preserved in notes.
-- ---------------------------------------------------------------------------
update public.memberships
   set status = 'pending'::payment_status
 where status::text = 'pending_verification';

update public.memberships
   set status = 'paid'::payment_status,
       notes  = coalesce(notes || E'\n', '') || 'Dues waived by the board.'
 where status::text = 'waived';


-- ---------------------------------------------------------------------------
-- 5. MIGRATE THE REGISTRATIONS TABLE
--
-- Each old column goes to exactly one place. Nothing is copied to two tables,
-- because two copies of the same fact is how they end up disagreeing.
--
--   identity        full_name, email, phone, university, academic_year,
--                   student_id, interests, interest_details   -> profiles
--   money           payment_method, payment_proof_path, payment_verified,
--                   rejected, verified_by, verified_at, notes -> memberships
--   committee       workforce, workforce_committee,
--                   workforce_motivation, committee_interest  -> applications
--
-- Rows with no matching account are left in the archive. There is no profile to
-- attach them to, and inventing one would create accounts nobody can sign into.
-- ---------------------------------------------------------------------------
do $$
declare
  r          record;
  p_id       uuid;
  yr         text;
  new_status payment_status;
  moved_m    int := 0;
  moved_a    int := 0;
  orphans    int := 0;
begin
  if not exists (select 1 from pg_tables
                  where schemaname='public' and tablename='registrations') then
    raise notice 'No registrations table. Nothing to migrate.';
    return;
  end if;

  for r in execute 'select * from public.registrations order by created_at' loop

    select id into p_id from public.profiles
     where lower(email) = lower(r.email) limit 1;

    if p_id is null then
      orphans := orphans + 1;
      continue;
    end if;

    -- ---- identity, filling gaps only, never overwriting what someone typed
    update public.profiles
       set full_name        = case when coalesce(full_name,'') = ''
                                   then r.full_name else full_name end,
           phone            = coalesce(phone, r.phone),
           university       = coalesce(university, r.university),
           academic_year    = coalesce(academic_year, r.academic_year),
           student_id       = coalesce(student_id, r.student_id),
           interests        = coalesce(interests, r.interests),
           interest_details = case when interest_details = '{}'::jsonb
                                   then coalesce(r.interest_details,'{}'::jsonb)
                                   else interest_details end
     where id = p_id;

    -- ---- money
    yr := public.dues_year_of(r.created_at::date);
    new_status := case
      when r.payment_verified then 'paid'::payment_status
      when r.rejected         then 'rejected'::payment_status
      else 'pending'::payment_status
    end;

    insert into public.memberships
      (profile_id, academic_year, status, amount_usd, paid_on, method,
       proof_path, verified_by, verified_at, notes)
    values
      (p_id, yr, new_status, 10.00,
       case when r.payment_verified then coalesce(r.verified_at::date, r.created_at::date) end,
       r.payment_method, r.payment_proof_path, r.verified_by, r.verified_at,
       nullif(r.notes,''))
    on conflict (profile_id, academic_year) do update
       set status      = excluded.status,
           method      = coalesce(memberships.method, excluded.method),
           proof_path  = coalesce(memberships.proof_path, excluded.proof_path),
           paid_on     = coalesce(memberships.paid_on, excluded.paid_on),
           verified_by = coalesce(memberships.verified_by, excluded.verified_by),
           verified_at = coalesce(memberships.verified_at, excluded.verified_at),
           notes       = coalesce(memberships.notes, excluded.notes);
    moved_m := moved_m + 1;

    -- ---- committee interest, only where the person actually asked
    if coalesce(r.workforce, false) then
      insert into public.applications
        (profile_id, kind, cycle, committee_id, motivation, answers, status, created_at)
      values
        (p_id, 'workforce'::application_kind, yr, r.workforce_committee,
         r.workforce_motivation, '{}'::jsonb, 'submitted'::application_status,
         r.created_at)
      on conflict do nothing;
      moved_a := moved_a + 1;
    end if;

  end loop;

  raise notice 'Migrated % memberships, % applications. % registrations had no account and stay in the archive.',
    moved_m, moved_a, orphans;
end $$;


-- ---------------------------------------------------------------------------
-- 6. RETIRE THE REGISTRATIONS TABLE WITHOUT DESTROYING IT
--
-- The triggers and functions that wrote to it go, because the new model has no
-- anonymous registration path. The table itself is renamed, not dropped.
-- ---------------------------------------------------------------------------
drop trigger if exists registration_creates_membership_trg on public.registrations;
drop trigger if exists notify_new_registration            on public.registrations;
drop trigger if exists notify_payment_decision            on public.registrations;

drop function if exists public.registration_creates_membership() cascade;
drop function if exists public.sync_membership_from_registration(uuid, public.registrations) cascade;
drop function if exists public.approve_registration(uuid, text) cascade;
drop function if exists public.reject_registration(uuid, text) cascade;
drop function if exists public.interest_counts() cascade;

do $$
begin
  if exists (select 1 from pg_tables
              where schemaname='public' and tablename='registrations') then
    execute 'alter table public.registrations rename to registrations_archive';
    raise notice 'registrations renamed to registrations_archive. Nothing deleted.';
  end if;
end $$;

-- Archive is admin-only from here. It still holds phone numbers and payment
-- details, so it does not become readable simply because it is retired.
do $$
begin
  if exists (select 1 from pg_tables
              where schemaname='public' and tablename='registrations_archive') then
    execute 'alter table public.registrations_archive enable row level security';
    execute 'drop policy if exists archive_admin_read on public.registrations_archive';
    execute 'create policy archive_admin_read on public.registrations_archive
               for select to authenticated using (public.is_admin())';
  end if;
end $$;


-- ---------------------------------------------------------------------------
-- 7. SIGNUP CREATES A PROFILE. NOTHING ELSE.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  uni  text;
begin
  uni := nullif(meta->>'university', '');
  if uni is not null and uni not in ('BAU','LU','USJ') then
    uni := null;
  end if;

  -- role is never read from metadata. That value comes from the browser, and
  -- anyone can put anything in it. It always defaults to 'member'.
  insert into public.profiles (id, email, full_name, phone, university, academic_year)
  values (
    new.id,
    new.email,
    coalesce(nullif(meta->>'full_name',''), nullif(meta->>'name',''), ''),
    nullif(meta->>'phone',''),
    uni,
    nullif(meta->>'academic_year','')
  )
  on conflict (id) do nothing;

  -- No membership. No application. Deliberately.
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ---------------------------------------------------------------------------
-- 8. WHAT A MEMBER MAY DO TO THEIR OWN MEMBERSHIP
--
-- A member creates their membership and attaches proof. The status they may set
-- is limited to unpaid and pending, and the verification columns are closed to
-- them entirely. A row-level policy controls which ROWS you may touch, never
-- which COLUMNS, which is why this has to be a trigger.
-- ---------------------------------------------------------------------------
create or replace function public.guard_membership()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if public.is_admin() then
    return new;   -- admins may set anything, including paid
  end if;

  if tg_op = 'INSERT' then
    if new.profile_id <> auth.uid() then
      raise exception 'You may only create your own membership';
    end if;
    if new.status not in ('unpaid'::payment_status, 'pending'::payment_status) then
      raise exception 'You cannot create a membership already marked as paid';
    end if;
    new.verified_by := null;
    new.verified_at := null;
    new.paid_on     := null;
    new.amount_usd  := 10.00;
    return new;
  end if;

  -- UPDATE
  if old.status = 'paid'::payment_status then
    raise exception 'A confirmed payment can only be changed by an administrator';
  end if;
  if new.status not in ('unpaid'::payment_status, 'pending'::payment_status) then
    raise exception 'Only an administrator may set that status';
  end if;
  if new.verified_by is distinct from old.verified_by
  or new.verified_at is distinct from old.verified_at
  or new.paid_on     is distinct from old.paid_on
  or new.profile_id  is distinct from old.profile_id
  or new.academic_year is distinct from old.academic_year then
    raise exception 'Only an administrator may change that';
  end if;

  return new;
end $$;

drop trigger if exists guard_membership_trg on public.memberships;
create trigger guard_membership_trg
  before insert or update on public.memberships
  for each row execute function public.guard_membership();


-- ---------------------------------------------------------------------------
-- 9. ADMIN DECISIONS ON A PAYMENT
-- ---------------------------------------------------------------------------
create or replace function public.approve_membership(membership_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Administrators only';
  end if;
  update public.memberships
     set status      = 'paid'::payment_status,
         verified_by = auth.uid(),
         verified_at = now(),
         paid_on     = coalesce(paid_on, current_date)
   where id = membership_id;
end $$;

create or replace function public.reject_membership(
  membership_id uuid,
  member_message text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Administrators only';
  end if;
  update public.memberships
     set status      = 'rejected'::payment_status,
         verified_by = auth.uid(),
         verified_at = now(),
         notes       = coalesce(member_message,
                        'We could not verify this payment. Please send a clear '
                        'screenshot of the transfer, showing the date and '
                        'reference, to info@ladslb.org.')
   where id = membership_id;
end $$;


-- ---------------------------------------------------------------------------
-- 10. COMMITTEE APPLICATIONS
--
-- No capacity check. No count of existing members. No limit on applications.
-- Acceptance is the event that assigns the committee; rejection changes nothing
-- about the person's current committee.
-- ---------------------------------------------------------------------------
create or replace function public.accept_application(app_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare a public.applications%rowtype;
begin
  select * into a from public.applications where id = app_id;
  if not found then
    raise exception 'Application not found';
  end if;

  if not (public.is_admin()
          or (public.is_committee_head() and a.committee_id = public.my_committee())) then
    raise exception 'You may not decide this application';
  end if;

  if a.profile_id = auth.uid() then
    raise exception 'You cannot accept your own application';
  end if;

  update public.applications
     set status      = 'accepted'::application_status,
         reviewer_id = auth.uid(),
         decided_at  = now(),
         updated_at  = now()
   where id = app_id;

  -- Acceptance is what assigns the committee. Submitting never does.
  if a.committee_id is not null then
    update public.profiles
       set committee_id = a.committee_id,
           updated_at   = now()
     where id = a.profile_id;
  end if;
end $$;

create or replace function public.reject_application(
  app_id uuid,
  note   text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare a public.applications%rowtype;
begin
  select * into a from public.applications where id = app_id;
  if not found then
    raise exception 'Application not found';
  end if;

  if not (public.is_admin()
          or (public.is_committee_head() and a.committee_id = public.my_committee())) then
    raise exception 'You may not decide this application';
  end if;

  update public.applications
     set status        = 'rejected'::application_status,
         reviewer_id   = auth.uid(),
         reviewer_note = coalesce(note, reviewer_note),
         decided_at    = now(),
         updated_at    = now()
   where id = app_id;

  -- profiles.committee_id is deliberately untouched.
end $$;


-- ---------------------------------------------------------------------------
-- 11. NOBODY ASSIGNS THEMSELVES A ROLE OR A COMMITTEE
-- ---------------------------------------------------------------------------
create or replace function public.guard_role_changes()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.role is distinct from old.role
  or new.committee_id is distinct from old.committee_id then
    -- auth.uid() is null in the SQL Editor, in migrations and for the service
    -- role. All three are already fully trusted, and enforcing here would lock
    -- out the one place you would go to repair a bad role.
    if auth.uid() is not null and not public.is_admin() then
      raise exception 'Only an administrator may change roles or committee assignment';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists guard_role_changes_trg on public.profiles;
create trigger guard_role_changes_trg
  before update on public.profiles
  for each row execute function public.guard_role_changes();


-- =============================================================================
-- Policies are rebuilt in 13_policies.sql. Run that next.
-- =============================================================================

-- =============================================================================
-- LADS PORTAL, STAGE 3: PASSWORD ACCOUNTS
-- Run in the Supabase SQL Editor AFTER portal_schema.sql and
-- portal_dues_bridge.sql. Safe to re-run.
--
-- The portal now uses email and password rather than sign-in links, and the
-- signup form collects name, phone, university and year up front. This file
-- teaches the database to read those details when the account is created, so a
-- member's profile is complete the moment they confirm their email instead of
-- being an empty row they have to fill in themselves.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. FASTER, SAFER EMAIL MATCHING
--
-- Registrations are matched to profiles on lower(email). Without an index that
-- is a full table scan on every signup. It will not matter at 50 members and
-- will matter at 500.
-- ---------------------------------------------------------------------------
create index if not exists profiles_email_lower_idx
  on public.profiles (lower(email));

create index if not exists registrations_email_lower_idx
  on public.registrations (lower(email));


-- ---------------------------------------------------------------------------
-- 2. PROFILE CREATION, NOW WITH THE SIGNUP DETAILS
--
-- Supabase stores whatever the signup form passed in raw_user_meta_data. This
-- reads it out into real columns.
--
-- Order of precedence, deliberately:
--   1. What the person typed on the signup form
--   2. What they had already given on the public Join form
--   3. Empty
--
-- The person signing up is the better source: they are typing it now, and they
-- can see what they are typing. The registration form data may be months old.
--
-- IMPORTANT: raw_user_meta_data is supplied by the browser and a determined
-- person can put anything in it. That is acceptable for a phone number or a
-- year of study, which are theirs to state. It is NOT acceptable for anything
-- that grants access, which is why `role` is never read from it and stays at
-- its default of 'member'. Roles are only ever set by an executive.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  r    public.registrations%rowtype;
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  uni  text;
begin
  -- Only accept a university we actually recognise, so a hand-crafted signup
  -- cannot violate the check constraint and abort the whole trigger.
  uni := nullif(meta->>'university', '');
  if uni is not null and uni not in ('BAU','LU','USJ') then
    uni := null;
  end if;

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

  -- Most recent verified registration for this email, if any.
  select * into r
    from public.registrations
   where lower(email) = lower(new.email)
     and payment_verified = true
     and rejected = false
   order by created_at desc
   limit 1;

  if found then
    -- Fill only the gaps. Never overwrite what they just typed.
    update public.profiles
       set full_name     = case when full_name = '' then r.full_name else full_name end,
           phone         = coalesce(phone, r.phone),
           university    = coalesce(university, r.university),
           academic_year = coalesce(academic_year, r.academic_year),
           student_id    = coalesce(student_id, r.student_id)
     where id = new.id;

    insert into public.memberships
      (profile_id, academic_year, status, amount_usd, paid_on,
       method, proof_path, verified_by, verified_at, notes)
    values
      (new.id, public.dues_year_of(r.created_at::date), 'paid', 10.00,
       coalesce(r.verified_at::date, r.created_at::date),
       r.payment_method, r.payment_proof_path, r.verified_by, r.verified_at,
       'Linked automatically from public registration form')
    on conflict (profile_id, academic_year) do nothing;
  end if;

  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ---------------------------------------------------------------------------
-- 3. A MEMBER MAY NEVER PROMOTE THEMSELVES
--
-- profiles_self_update in portal_schema.sql already blocks role changes with
-- `role = public.my_role()` in its WITH CHECK. This adds the same protection at
-- the table level, so it holds even if a future board rewrites the policies and
-- forgets that clause.
--
-- The executive path is unaffected: profiles_exec_update runs as a different
-- policy, and this trigger explicitly allows changes made by an executive.
-- ---------------------------------------------------------------------------
create or replace function public.guard_role_changes()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.role is distinct from old.role or
     new.committee_id is distinct from old.committee_id then
    if not public.is_exec() then
      raise exception 'Only the Executive Committee may change roles';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists guard_role_changes_trg on public.profiles;
create trigger guard_role_changes_trg
  before update on public.profiles
  for each row execute function public.guard_role_changes();


-- =============================================================================
-- AFTER RUNNING THIS, CHANGE TWO SETTINGS IN THE DASHBOARD
--
-- 1. Authentication -> Sign In / Providers -> Email
--      Enable email provider ........ ON
--      Confirm email ................ ON     <- important, see below
--      Minimum password length ...... 8
--
--    "Confirm email" is what stops someone registering under another student's
--    address. Without it, anyone could create an account as their classmate and
--    the Treasurer would have no way to tell which one is real.
--
-- 2. Authentication -> URL Configuration -> Redirect URLs, add:
--      https://ladslb.org/auth-callback.html
--      https://ladslb.org/reset-password.html
--      https://ladslb.org/**
--
--    Password reset links go to reset-password.html. If it is not on this list
--    the link silently bounces and members cannot recover their accounts.
-- =============================================================================

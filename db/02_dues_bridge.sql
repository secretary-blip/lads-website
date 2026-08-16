-- =============================================================================
-- LADS PORTAL, STAGE 2: DUES BRIDGE
-- Run once in the Supabase SQL Editor, AFTER portal_schema.sql. Safe to re-run.
--
-- THE PROBLEM THIS SOLVES
-- The public Join form writes to `registrations`. A person can fill it in
-- without ever creating an account. The portal, meanwhile, shows dues from
-- `memberships`, which is keyed to a profile.
--
-- Without a bridge, the Treasurer could verify a payment and the member would
-- still see "Not paid" in their account forever. This file connects the two,
-- in both directions and in either order:
--
--   registration first, account later  -> membership is back-filled on signup
--   account first, registration later  -> membership is created on approval
--
-- All of it runs in the database, so it cannot be bypassed by a bug in the
-- website, and it keeps working if a future board rewrites the front end.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. ACADEMIC YEAR, IN SQL
-- The website already computes this in JavaScript. The database needs its own
-- copy so that server-side approval does not depend on what the browser sends.
-- Runs September to August, matching the Lebanese academic calendar.
-- ---------------------------------------------------------------------------
create or replace function public.academic_year_of(d date)
returns text
language sql immutable
as $$
  select case
    when extract(month from d) >= 9
      then extract(year from d)::int::text || '/' || (extract(year from d)::int + 1)::text
    else (extract(year from d)::int - 1)::text || '/' || extract(year from d)::int::text
  end
$$;

create or replace function public.current_academic_year()
returns text
language sql stable
as $$ select public.academic_year_of(current_date) $$;

-- Which year a PAYMENT belongs to, which is a different question from which
-- year we are currently in.
--
-- The academic year starts in September, but members pay ahead: someone who
-- transfers their dues in July 2026 is paying for 2026/2027, not for the year
-- that is about to end. Filing that payment under 2025/2026 would show them
-- "Not paid" all through the year they actually paid for.
--
-- So: July onward counts towards the year that starts that September.
create or replace function public.dues_year_of(d date)
returns text
language sql immutable
as $$
  select case
    when extract(month from d) >= 7
      then extract(year from d)::int::text || '/' || (extract(year from d)::int + 1)::text
    else (extract(year from d)::int - 1)::text || '/' || extract(year from d)::int::text
  end
$$;


-- ---------------------------------------------------------------------------
-- 2. REGISTRATIONS: LET THE BOARD READ THEM
--
-- The original setup gave anon INSERT only, with no SELECT policy at all.
-- That was correct for launch (nobody could read member data through the API)
-- but it also means the Treasurer's screen cannot see anything.
--
-- Grant read and update to treasurer/executive only. Members, committee heads
-- and the public still see nothing.
-- ---------------------------------------------------------------------------
alter table public.registrations enable row level security;

drop policy if exists registrations_staff_read on public.registrations;
create policy registrations_staff_read on public.registrations
  for select to authenticated
  using (public.handles_money());

drop policy if exists registrations_staff_update on public.registrations;
create policy registrations_staff_update on public.registrations
  for update to authenticated
  using (public.handles_money()) with check (public.handles_money());

-- Deliberately no DELETE policy. Registrations are a financial record and are
-- never destroyed, only marked.

-- Columns the Treasurer needs that the original table lacks.
alter table public.registrations
  add column if not exists verified_by uuid references public.profiles(id),
  add column if not exists verified_at timestamptz,
  add column if not exists rejected    boolean not null default false;


-- ---------------------------------------------------------------------------
-- 3. PAYMENT PROOF SCREENSHOTS
--
-- The bucket is private. Anon can upload (so the public form works) but cannot
-- read. Give read access to treasurer/executive so proofs can be reviewed in
-- the portal rather than by logging into the Supabase dashboard.
-- ---------------------------------------------------------------------------
-- Wrapped, because on some Supabase projects the SQL Editor role is not the
-- owner of storage.objects and this raises a permissions error. If that happens
-- the rest of the file still runs, and the policy can be added from the
-- dashboard instead: Storage -> payment-proofs -> Policies -> New policy.
do $$
begin
  drop policy if exists "staff can read payment proofs" on storage.objects;
  create policy "staff can read payment proofs"
    on storage.objects for select
    to authenticated
    using (bucket_id = 'payment-proofs' and public.handles_money());
exception
  when insufficient_privilege then
    raise notice 'Could not create the storage policy from SQL. Add it in the Storage dashboard instead, see PORTAL_SETUP.md.';
end $$;


-- ---------------------------------------------------------------------------
-- 4. APPROVE A REGISTRATION
--
-- Marks the registration verified and creates or updates the matching
-- membership row for the academic year. Matching is by email, case-insensitive,
-- because that is the only identifier the public form collects that also
-- exists on a profile.
--
-- If the person has not signed in yet there is no profile to attach to. That is
-- fine: the registration is still marked verified, and section 5 back-fills the
-- membership automatically the moment they first sign in.
--
-- SECURITY DEFINER, so it can write to memberships, with an explicit role check
-- as the first statement. Without that check any signed-in member could call it.
-- ---------------------------------------------------------------------------
create or replace function public.approve_registration(
  reg_id uuid,
  ay     text default null
)
returns text
language plpgsql security definer set search_path = public
as $$
declare
  r    public.registrations%rowtype;
  p_id uuid;
  yr   text;
begin
  if not public.handles_money() then
    raise exception 'Only the Treasurer or Executive Committee may verify payments';
  end if;

  select * into r from public.registrations where id = reg_id;
  if not found then
    raise exception 'Registration not found';
  end if;

  yr := coalesce(ay, public.dues_year_of(r.created_at::date));

  update public.registrations
     set payment_verified = true,
         confirmed        = true,
         rejected         = false,
         verified_by      = auth.uid(),
         verified_at      = now()
   where id = reg_id;

  select id into p_id
    from public.profiles
   where lower(email) = lower(r.email)
   limit 1;

  if p_id is null then
    return 'verified_no_account';
  end if;

  insert into public.memberships
    (profile_id, academic_year, status, amount_usd, paid_on,
     method, proof_path, verified_by, verified_at)
  values
    (p_id, yr, 'paid', 10.00, current_date,
     r.payment_method, r.payment_proof_path, auth.uid(), now())
  on conflict (profile_id, academic_year) do update
     set status      = 'paid',
         paid_on     = coalesce(memberships.paid_on, current_date),
         method      = excluded.method,
         proof_path  = coalesce(excluded.proof_path, memberships.proof_path),
         verified_by = auth.uid(),
         verified_at = now();

  return 'linked';
end $$;


-- ---------------------------------------------------------------------------
-- 5. REJECT A REGISTRATION
-- Used when a screenshot is unreadable or the payment cannot be found.
-- Nothing is deleted; the row is flagged and a note is recorded.
-- ---------------------------------------------------------------------------
create or replace function public.reject_registration(
  reg_id uuid,
  reason text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.handles_money() then
    raise exception 'Only the Treasurer or Executive Committee may reject payments';
  end if;

  update public.registrations
     set payment_verified = false,
         confirmed        = false,
         rejected         = true,
         verified_by      = auth.uid(),
         verified_at      = now(),
         notes            = coalesce(notes || E'\n', '') ||
                            coalesce(reason, 'Rejected, no reason given')
   where id = reg_id;
end $$;


-- ---------------------------------------------------------------------------
-- 6. BACK-FILL ON FIRST SIGN-IN
--
-- Replaces handle_new_user from portal_schema.sql. Same behaviour as before,
-- plus: when a profile is created, look for any already-verified registration
-- with the same email and create the membership record from it.
--
-- This is what makes the order of events irrelevant. Someone can pay in
-- September, get verified in October, and create their account in January, and
-- their account will still show the correct paid status and history.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  r public.registrations%rowtype;
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email,
          coalesce(new.raw_user_meta_data->>'full_name',
                   new.raw_user_meta_data->>'name', ''))
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
    -- Fill in details the person gave on the public form, without overwriting
    -- anything they may already have set on their profile.
    update public.profiles
       set full_name     = case when full_name = '' then r.full_name else full_name end,
           phone         = coalesce(phone, r.phone),
           university    = coalesce(university, r.university),
           academic_year = coalesce(academic_year, r.academic_year),
           student_id    = coalesce(student_id, r.student_id)
     where id = new.id;

    -- Year comes from when they registered, not from today. Someone who paid
    -- in 2026 and signs in for the first time in 2028 gets a 2026/2027 record,
    -- which is what actually happened.
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
-- 7. RETROACTIVE BACK-FILL
--
-- Section 6 only fires for accounts created from now on. This handles anyone
-- who already has an account and an already-verified registration.
-- Harmless to run repeatedly.
-- ---------------------------------------------------------------------------
insert into public.memberships
  (profile_id, academic_year, status, amount_usd, paid_on,
   method, proof_path, verified_by, verified_at, notes)
select p.id,
       public.dues_year_of(r.created_at::date),
       'paid',
       10.00,
       coalesce(r.verified_at::date, r.created_at::date),
       r.payment_method,
       r.payment_proof_path,
       r.verified_by,
       r.verified_at,
       'Linked automatically from public registration form'
  from public.registrations r
  join public.profiles p on lower(p.email) = lower(r.email)
 where r.payment_verified = true
   and r.rejected = false
on conflict (profile_id, academic_year) do nothing;


-- ---------------------------------------------------------------------------
-- 8. A COUNT THE BOARD CAN TRUST
--
-- Deliberately a function, not a view. A Postgres view runs with the
-- permissions of whoever created it and would bypass row-level security,
-- which is how member data leaks. This checks the caller's role every time.
-- ---------------------------------------------------------------------------
create or replace function public.dues_summary(ay text default null)
returns table (
  academic_year   text,
  paid            bigint,
  pending         bigint,
  unpaid          bigint,
  waived          bigint,
  total_usd       numeric
)
language plpgsql stable security definer set search_path = public
as $$
declare yr text;
begin
  if not public.is_staff() then
    raise exception 'Board members only';
  end if;

  yr := coalesce(ay, public.dues_year_of(current_date));

  return query
  select yr,
         count(*) filter (where m.status = 'paid'),
         count(*) filter (where m.status = 'pending_verification'),
         count(*) filter (where m.status = 'unpaid'),
         count(*) filter (where m.status = 'waived'),
         coalesce(sum(m.amount_usd) filter (where m.status = 'paid'), 0)
    from public.memberships m
   where m.academic_year = yr;
end $$;


-- =============================================================================
-- DONE. Expect "Success. No rows returned."
--
-- To check it worked, run:
--   select * from public.dues_summary();
-- =============================================================================

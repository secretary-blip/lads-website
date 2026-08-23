-- =============================================================================
-- LADS PORTAL, STAGE 9: MEMBERSHIP LIFECYCLE
-- Run after 08. One snippet. Safe to re-run.
--
-- WHAT CHANGES
--
-- A membership row now exists as soon as we know who someone is, instead of
-- only after their payment has been confirmed.
--
-- The gap this closes: somebody who registered, paid, and created an account
-- saw "Not paid" on their own page while they waited for the Treasurer. Wrong,
-- and the sort of thing that produces a message to the General Secretary in the
-- middle of September.
--
-- Uses only the four statuses that already exist. No new enum value, so this is
-- a single migration.
--
--   pending_verification   registered, waiting on the Treasurer
--   paid                   payment confirmed
--   unpaid                 not paid, or a payment we could not verify
--   waived                 the board decided this member owes nothing
--
-- A payment that could not be verified is recorded as `unpaid`, because that is
-- what it factually is, with a member-visible explanation in memberships.notes.
--
-- It is deliberately NOT recorded as `waived`. Waived means the board decided
-- someone owes nothing, and the site treats it as full membership: events.html
-- unlocks members-only events for `paid` and `waived` alike. Filing rejections
-- under waived would hand full access to people whose payment was never
-- verified, and would inflate the Waived figure in the Treasurer's totals with
-- decisions the board never made.
--
-- One row per member per academic year, forever, enforced by the unique
-- constraint on (profile_id, academic_year).
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. ONE FUNCTION THAT CREATES OR UPDATES A MEMBERSHIP
--
-- Three events need exactly this logic. Writing it out three times is how a
-- system ends up disagreeing with itself about who has paid.
--
-- Note what this function does NOT do: it never writes to registrations.
-- payment_verified is the record of money actually received, and only the
-- Treasurer's decision may change it. Creating an account, in particular, must
-- never touch it, or signing up after a confirmed payment would wipe the fact
-- that the money arrived.
-- ---------------------------------------------------------------------------
create or replace function public.sync_membership_from_registration(
  p_profile_id uuid,
  p_reg        public.registrations
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  new_status payment_status;
  new_note   text;
  yr         text;
begin
  if p_profile_id is null or p_reg.id is null then
    return;
  end if;

  yr := public.dues_year_of(p_reg.created_at::date);

  if p_reg.payment_verified then
    new_status := 'paid'::payment_status;
    new_note   := null;
  elsif p_reg.rejected then
    new_status := 'unpaid'::payment_status;
    -- Member-facing, and deliberately not the reason the Treasurer typed.
    -- That stays private on the registration.
    new_note   := 'We could not verify this payment. Please send a clear '
               || 'screenshot of the transfer, showing the date and reference, '
               || 'to info@ladslb.org and we will sort it out.';
  else
    new_status := 'pending_verification'::payment_status;
    new_note   := null;
  end if;

  insert into public.memberships
    (profile_id, academic_year, status, amount_usd, paid_on,
     method, proof_path, verified_by, verified_at, notes)
  values
    (p_profile_id, yr, new_status, 10.00,
     case when p_reg.payment_verified then coalesce(p_reg.verified_at::date, current_date) end,
     p_reg.payment_method, p_reg.payment_proof_path,
     p_reg.verified_by, p_reg.verified_at, new_note)
  on conflict (profile_id, academic_year) do update
     set status      = excluded.status,
         method      = coalesce(excluded.method, memberships.method),
         proof_path  = coalesce(excluded.proof_path, memberships.proof_path),
         -- A recorded payment date is a fact. If a payment was confirmed and
         -- later queried, the day the money arrived does not stop being true.
         paid_on     = coalesce(excluded.paid_on, memberships.paid_on),
         verified_by = coalesce(excluded.verified_by, memberships.verified_by),
         verified_at = coalesce(excluded.verified_at, memberships.verified_at),
         notes       = excluded.notes
     -- Never overwrite a waiver. That is a board decision, and a student
     -- re-submitting the form should not quietly undo it.
     where memberships.status <> 'waived'::payment_status;
end $$;


-- ---------------------------------------------------------------------------
-- 2. REGISTERED, AND ALREADY HAS AN ACCOUNT
-- ---------------------------------------------------------------------------
create or replace function public.registration_creates_membership()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare p_id uuid;
begin
  select id into p_id
    from public.profiles
   where lower(email) = lower(new.email)
   limit 1;

  if p_id is not null then
    perform public.sync_membership_from_registration(p_id, new);
  end if;

  return new;
end $$;

drop trigger if exists registration_creates_membership_trg on public.registrations;
create trigger registration_creates_membership_trg
  after insert on public.registrations
  for each row execute function public.registration_creates_membership();


-- ---------------------------------------------------------------------------
-- 3. SIGNED UP, AND ALREADY REGISTERED
--
-- Reads the registration. Never writes to it.
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
  uni := nullif(meta->>'university', '');
  if uni is not null and uni not in ('BAU','LU','USJ') then
    uni := null;
  end if;

  -- role is never read from metadata. That comes from the browser, so anyone
  -- could claim to be an executive. It always defaults to 'member'.
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

  select * into r
    from public.registrations
   where lower(email) = lower(new.email)
   order by created_at desc
   limit 1;

  if found then
    update public.profiles
       set full_name     = case when full_name = '' then r.full_name else full_name end,
           phone         = coalesce(phone, r.phone),
           university    = coalesce(university, r.university),
           academic_year = coalesce(academic_year, r.academic_year),
           student_id    = coalesce(student_id, r.student_id)
     where id = new.id;

    perform public.sync_membership_from_registration(new.id, r);
  end if;

  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ---------------------------------------------------------------------------
-- 4. THE TREASURER CONFIRMS A PAYMENT
-- Sets payment_verified true, and the membership to paid.
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
begin
  if not public.handles_money() then
    raise exception 'Only the Treasurer or Executive Committee may verify payments';
  end if;

  update public.registrations
     set payment_verified = true,
         confirmed        = true,
         rejected         = false,
         verified_by      = auth.uid(),
         verified_at      = now()
   where id = reg_id
  returning * into r;

  if r.id is null then
    raise exception 'Registration not found';
  end if;

  select id into p_id
    from public.profiles
   where lower(email) = lower(r.email)
   limit 1;

  if p_id is null then
    -- No account yet. handle_new_user creates the membership, already marked
    -- paid, the moment they sign up.
    return 'verified_no_account';
  end if;

  perform public.sync_membership_from_registration(p_id, r);
  return 'linked';
end $$;


-- ---------------------------------------------------------------------------
-- 5. THE TREASURER CANNOT VERIFY A PAYMENT
-- payment_verified stays false. The membership becomes unpaid with an
-- explanation the member can read. The row is kept, so they can see that
-- something needs doing rather than the record simply never appearing.
-- ---------------------------------------------------------------------------
create or replace function public.reject_registration(
  reg_id uuid,
  reason text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  r    public.registrations%rowtype;
  p_id uuid;
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
   where id = reg_id
  returning * into r;

  if r.id is null then
    raise exception 'Registration not found';
  end if;

  select id into p_id
    from public.profiles
   where lower(email) = lower(r.email)
   limit 1;

  if p_id is not null then
    perform public.sync_membership_from_registration(p_id, r);
  end if;
end $$;


-- ---------------------------------------------------------------------------
-- 6. BACK-FILL
-- Everyone who already has both a registration and an account but no membership
-- row, because the old logic only created one after confirmation.
-- ---------------------------------------------------------------------------
do $$
declare rec record;
begin
  for rec in
    select distinct on (p.id) p.id as profile_id, r.id as reg_id
      from public.registrations r
      join public.profiles p on lower(p.email) = lower(r.email)
     order by p.id, r.created_at desc
  loop
    perform public.sync_membership_from_registration(
      rec.profile_id,
      (select x from public.registrations x where x.id = rec.reg_id));
  end loop;
end $$;


-- =============================================================================
-- CHECK IT
--   select p.full_name, p.email, m.academic_year, m.status, m.notes
--     from public.memberships m
--     join public.profiles p on p.id = m.profile_id
--    order by p.full_name;
-- =============================================================================

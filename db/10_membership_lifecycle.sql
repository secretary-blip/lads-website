-- =============================================================================
-- LADS PORTAL, STAGE 10: MEMBERSHIP LIFECYCLE
-- Run AFTER 09_add_rejected_status.sql, as a separate snippet. Safe to re-run.
--
-- WHAT CHANGES
--
-- Until now a membership row only existed once a payment had been confirmed.
-- That left a real gap: somebody who registered, paid, and created an account
-- saw "Not paid" on their own page while they waited. Wrong, and exactly the
-- sort of thing that produces a message to the General Secretary.
--
-- Now the membership row is created as soon as we know who the person is, and
-- it carries the state:
--
--   pending_verification   registered, waiting on the Treasurer
--   paid                   confirmed
--   rejected               could not be verified, the member needs to act
--   waived                 dues waived by the board
--
-- payment_verified on the registration stays false unless money was actually
-- confirmed. Membership status is what members and the board read;
-- payment_verified is the raw fact about the payment.
--
-- The row is created whichever way round things happen:
--   register, then sign up   -> handle_new_user
--   sign up, then register   -> registration_creates_membership
-- =============================================================================



-- ---------------------------------------------------------------------------
-- 2. ONE PLACE THAT CREATES OR UPDATES A MEMBERSHIP FROM A REGISTRATION
--
-- Three different events need this exact logic, so it lives in one function
-- rather than being written out three times and drifting apart.
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
  yr         text;
begin
  if p_profile_id is null or p_reg.id is null then
    return;
  end if;

  yr := public.dues_year_of(p_reg.created_at::date);

  new_status := case
    when p_reg.payment_verified then 'paid'::payment_status
    when p_reg.rejected         then 'rejected'::payment_status
    else 'pending_verification'::payment_status
  end;

  insert into public.memberships
    (profile_id, academic_year, status, amount_usd, paid_on,
     method, proof_path, verified_by, verified_at)
  values
    (p_profile_id, yr, new_status, 10.00,
     case when p_reg.payment_verified then coalesce(p_reg.verified_at::date, current_date) end,
     p_reg.payment_method, p_reg.payment_proof_path,
     p_reg.verified_by, p_reg.verified_at)
  on conflict (profile_id, academic_year) do update
     set status      = excluded.status,
         method      = coalesce(excluded.method, memberships.method),
         proof_path  = coalesce(excluded.proof_path, memberships.proof_path),
         -- Never clear a payment date that was already recorded. If a payment
         -- was confirmed and later queried, the date it arrived is still a fact.
         paid_on     = coalesce(excluded.paid_on, memberships.paid_on),
         verified_by = coalesce(excluded.verified_by, memberships.verified_by),
         verified_at = coalesce(excluded.verified_at, memberships.verified_at)
     -- Do not touch a membership the board has waived. A waiver is a decision,
     -- and a later form submission should not quietly undo it.
     where memberships.status <> 'waived'::payment_status;
end $$;


-- ---------------------------------------------------------------------------
-- 3. NEW REGISTRATION, WHEN THE PERSON ALREADY HAS AN ACCOUNT
-- Covers: signed up first, registered afterwards.
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
-- 4. NEW ACCOUNT, WHEN THE PERSON ALREADY REGISTERED
-- Covers: registered first, signed up afterwards. Replaces the version in 03,
-- which only back-filled already-verified registrations.
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

  -- role is never read from metadata. It comes from the browser, so anyone
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

  -- Any registration for this email, whatever its state. Rejected ones included,
  -- so the member can see that something went wrong rather than seeing nothing.
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
-- 5. APPROVING A PAYMENT
-- Now only records the decision. The membership row already exists in most
-- cases, so this updates it rather than creating it from nothing.
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
    -- No account yet. handle_new_user will create the membership, already
    -- marked paid, the moment they sign up.
    return 'verified_no_account';
  end if;

  perform public.sync_membership_from_registration(p_id, r);
  return 'linked';
end $$;


-- ---------------------------------------------------------------------------
-- 6. REJECTING A PAYMENT
-- The membership row stays and becomes 'rejected', so the member can see that
-- something needs doing instead of the record silently vanishing.
-- payment_verified stays false, because no money was confirmed.
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
-- 7. BACK-FILL WHAT ALREADY EXISTS
-- Everyone who has both a registration and an account, but no membership row
-- because the old logic only created one after confirmation.
-- ---------------------------------------------------------------------------
do $$
declare rec record;
begin
  for rec in
    select distinct on (p.id) p.id as profile_id, r.*
      from public.registrations r
      join public.profiles p on lower(p.email) = lower(r.email)
     order by p.id, r.created_at desc
  loop
    perform public.sync_membership_from_registration(
      rec.profile_id,
      (select x from public.registrations x where x.id = rec.id));
  end loop;
end $$;


-- =============================================================================
-- CHECK IT
--   select m.academic_year, m.status, p.full_name, p.email
--     from public.memberships m join public.profiles p on p.id = m.profile_id
--    order by p.full_name;
-- =============================================================================

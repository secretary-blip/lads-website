-- ---------------------------------------------------------------------------
-- 21. Everyone who signs up gets a dues row
--
-- Signing up created a profile and nothing else, so a member who never opened
-- the payment page had no row in `memberships`. The dues page lists
-- memberships, so those people were invisible to the Treasurer: present in
-- Members and Roles, absent from the one screen that decides who still owes.
-- Six of them had built up before anyone noticed.
--
-- From here a profile gets an 'unpaid' membership for the current dues year as
-- soon as it is created, and the six existing ones are backfilled.
-- ---------------------------------------------------------------------------

-- guard_membership() refuses any insert whose profile_id is not the caller's
-- own. That is right for the browser and wrong for a trigger: during signup
-- there is no auth.uid() yet, so the guard would abort the whole signup. This
-- flag is the escape hatch. It is a transaction-local GUC set only by the
-- definer functions below; PostgREST does not expose set_config, so a member
-- cannot turn it on from the browser.
create or replace function public.guard_membership()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if coalesce(current_setting('lads.system', true), '') = 'on' then
    return new;   -- our own trigger or a migration, not a browser
  end if;

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
    new.amount_usd  := public.dues_amount(new.academic_year);
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


create or replace function public.profile_creates_membership()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  yr text := public.dues_year_of(current_date);
begin
  perform set_config('lads.system', 'on', true);

  insert into public.memberships (profile_id, academic_year, status, amount_usd)
  values (new.id, yr, 'unpaid'::payment_status, public.dues_amount(yr))
  on conflict (profile_id, academic_year) do nothing;

  return new;
end $$;

drop trigger if exists profile_creates_membership_trg on public.profiles;
create trigger profile_creates_membership_trg
  after insert on public.profiles
  for each row execute function public.profile_creates_membership();


-- The people who signed up before the trigger existed.
do $$
declare
  yr text := public.dues_year_of(current_date);
  n  int;
begin
  perform set_config('lads.system', 'on', true);

  insert into public.memberships (profile_id, academic_year, status, amount_usd)
  select p.id, yr, 'unpaid'::payment_status, public.dues_amount(yr)
    from public.profiles p
   where not exists (
           select 1 from public.memberships m
            where m.profile_id = p.id and m.academic_year = yr)
  on conflict (profile_id, academic_year) do nothing;

  get diagnostics n = row_count;
  raise notice 'Backfilled % unpaid membership(s) for %', n, yr;
end $$;

notify pgrst, 'reload schema';

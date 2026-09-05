-- ---------------------------------------------------------------------------
-- 20. The dues amount became 20 USD
--
-- Dues were 10 USD. From 2026/2027 they are 20. The old figure was written
-- into the column default and into guard_membership(), so a member creating
-- their own membership would still be billed 10 whatever the page said.
--
-- The amount belongs to an academic year, not to the association in general.
-- Rewriting it everywhere would restate what people paid in 2025/2026 and
-- would make the Treasurer's totals for that year wrong, so dues_amount()
-- keeps each year at the price actually charged.
-- ---------------------------------------------------------------------------

create or replace function public.dues_amount(ay text)
returns numeric
language sql immutable
as $$
  -- Academic years read '2026/2027', so a plain string compare orders them
  -- correctly: '2025/2026' < '2026/2027' < '2027/2028'.
  select (case when ay >= '2026/2027' then 20.00 else 10.00 end)::numeric(10,2)
$$;

comment on function public.dues_amount(text) is
  'Membership dues in USD for one academic year. 10 up to 2025/2026, 20 from 2026/2027.';

-- A row that names no amount is a current-year row.
alter table public.memberships
  alter column amount_usd set default 20.00;

-- Unchanged from migration 12 apart from the amount, which now follows the
-- year on the row instead of a constant.
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

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- 28. Dues for 2026/2027 are 15 USD
--
-- The board voted unanimously. 2026/2027 was briefly priced at 20, which is
-- what migration 20 set and what the site has been showing; it is now 15.
--
-- dues_amount() keeps each year at the price actually charged, so 2025/2026
-- stays at 10. Rewriting an earlier year would restate what people paid and
-- make the Treasurer's totals for that year wrong.
--
-- guard_membership() is lifted for the correction, as in migration 26: it
-- exempts admins, is_admin() reads auth.uid(), and auth.uid() is null over
-- psql, so the guard judges a correction run against the database as if a
-- member were editing their own row. It goes straight back on, inside the
-- transaction, so a failure rolls it back rather than leaving the table open.
--
-- Paid rows are left alone on principle. There are none for 2026/2027 today,
-- so nothing is skipped in practice, but a payment that lands between this
-- being written and being run must not be quietly repriced.
-- ---------------------------------------------------------------------------

create or replace function public.dues_amount(ay text)
returns numeric
language sql immutable
as $$
  -- Academic years read '2026/2027', so a plain string compare orders them.
  select (case when ay >= '2026/2027' then 15.00 else 10.00 end)::numeric(10,2)
$$;

comment on function public.dues_amount(text) is
  'Membership dues in USD for one academic year. 10 up to 2025/2026, 15 from 2026/2027 (board vote, Oct 2026; briefly 20).';

alter table public.memberships
  alter column amount_usd set default 15.00;

begin;

alter table public.memberships disable trigger guard_membership_trg;

update public.memberships
   set amount_usd = public.dues_amount(academic_year)
 where status <> 'paid'::payment_status
   and amount_usd is distinct from public.dues_amount(academic_year);

alter table public.memberships enable trigger guard_membership_trg;

commit;

notify pgrst, 'reload schema';

-- Read it back. Every 2026/2027 row that is not paid should say 15.00.
select academic_year, status, amount_usd, count(*)
  from public.memberships
 group by 1, 2, 3
 order by 1, 2;

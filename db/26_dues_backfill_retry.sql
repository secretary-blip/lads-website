begin;
alter table public.memberships disable trigger guard_membership_trg;
update public.memberships
   set amount_usd = public.dues_amount(academic_year)
 where status <> 'paid'::payment_status
   and amount_usd is distinct from public.dues_amount(academic_year);
alter table public.memberships enable trigger guard_membership_trg;
commit;
select academic_year, status, amount_usd, count(*)
  from public.memberships group by 1,2,3 order by 1,2;

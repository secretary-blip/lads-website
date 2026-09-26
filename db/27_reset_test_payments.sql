begin;
alter table public.memberships disable trigger guard_membership_trg;
update public.memberships
   set status      = 'unpaid'::payment_status,
       amount_usd  = public.dues_amount(academic_year),
       paid_on     = null,
       verified_by = null,
       verified_at = null,
       method      = null,
       proof_path  = null
 where academic_year = '2026/2027'
   and status = 'paid'::payment_status
   and amount_usd = 10.00;
alter table public.memberships enable trigger guard_membership_trg;
commit;
select academic_year, status, amount_usd, count(*)
  from public.memberships group by 1,2,3 order by 1,2;

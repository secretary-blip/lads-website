-- ---------------------------------------------------------------------------
-- 33. LADS dues status on the Journal Club member table
--
-- Nour wants to see, for each Journal Club member, whether they have paid this
-- year's LADS dues, so the ones who have not can be told at the first session.
-- Riad asked for it.
--
-- journal_member_list() gains two columns:
--   dues     'paid', 'pending' (receipt uploaded, Treasurer has not checked
--            it yet) or 'unpaid' (nothing, or a receipt that was rejected)
--   paid_on  the date the payment was made, when there is one
-- for the current academic year only. Nothing else about the payment leaves
-- the dues tables: no amount, no method, no receipt.
--
-- Who can call it is unchanged: the Scientific Committee head, the Executive
-- Committee and Journal Club leads. A function's return type cannot be
-- changed in place, so it is dropped and created again in one transaction.
-- ---------------------------------------------------------------------------

begin;

drop function if exists public.journal_member_list();

create function public.journal_member_list()
returns table (
  full_name      text,
  email          text,
  phone          text,
  university     text,
  year           text,
  joined_at      timestamptz,
  interests      text[],
  presenting     text,
  research_level text,
  mode_pref      text,
  access_needs   text,
  whatsapp       boolean,
  dues           text,
  paid_on        date
)
language sql stable security definer set search_path = public
as $$
  select coalesce(nullif(m.certificate_name,''), p.full_name),
         p.email, p.phone,
         coalesce(nullif(p.university,'Other'), p.university_other, p.university),
         p.academic_year, m.joined_at, m.interests, m.presenting,
         m.research_level, m.mode_pref, m.access_needs, m.consent_whatsapp,
         case
           when ms.status::text in ('paid','waived')                then 'paid'
           when ms.status::text in ('pending','pending_verification') then 'pending'
           else 'unpaid'
         end,
         case when ms.status::text in ('paid','waived') then ms.paid_on end
    from public.journal_members m
    join public.profiles p on p.id = m.profile_id
    left join public.memberships ms
           on ms.profile_id = m.profile_id
          and ms.academic_year = public.current_academic_year()
   where public.can_see_journal_members()
   order by m.joined_at
$$;

comment on function public.journal_member_list() is
  'Every Journal Club member, their answers and whether this year''s LADS dues '
  'are paid. Executive Committee, Scientific Committee head and Journal Club '
  'leads only; the guard is inside the query.';

revoke all on function public.journal_member_list() from public;
grant execute on function public.journal_member_list() to authenticated;

commit;

notify pgrst, 'reload schema';

select public.current_academic_year() as dues_year,
       count(*) filter (where ms.status::text in ('paid','waived')) as paid,
       count(*) as journal_members
  from public.journal_members m
  left join public.memberships ms
         on ms.profile_id = m.profile_id
        and ms.academic_year = public.current_academic_year();

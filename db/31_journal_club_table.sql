-- ---------------------------------------------------------------------------
-- 31. Journal Club responses as one table, for the people who run it
--
-- Nour runs the Journal Club and asked to see every sign up in one table
-- instead of one email each. Riad approved her access as the organiser.
--
-- Who sees the table: the head of the Scientific Committee, the Executive
-- Committee (super_admin), and Journal Club leads. Not other committee heads,
-- not the treasurer. The table holds members' phone numbers and notes.
--
-- 1. journal_leads. People who run the Journal Club without a board role.
--    Being listed opens this table and nothing else: no dues, no LADS member
--    records, no roles, no other board tools.
-- 2. can_see_journal_members(). The one check, used by the list and by the
--    portal to decide whether to show the card.
-- 3. journal_member_list(). Every member with their answers and contact
--    details. The guard is inside the query, so anybody else gets nothing.
-- 4. Nour (nro@ladslb.org) is added as a lead if her account exists. If the
--    last select shows no row, she signs up with that address first and this
--    file is run again. Safe to run twice.
-- ---------------------------------------------------------------------------

create table if not exists public.journal_leads (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  added_at   timestamptz not null default now()
);

comment on table public.journal_leads is
  'Journal Club organisers without a board role. Journal Club access only.';

alter table public.journal_leads enable row level security;

drop policy if exists journal_leads_own on public.journal_leads;
create policy journal_leads_own on public.journal_leads
  for select to authenticated
  using (profile_id = auth.uid());

grant select on public.journal_leads to authenticated;

create or replace function public.can_see_journal_members()
returns boolean
language sql stable security definer set search_path = public
as $$ select coalesce(
     (select role = 'super_admin'
          or (role = 'committee_head' and committee_id = 'scientific')
        from public.profiles where id = auth.uid()), false)
   or exists (select 1 from public.journal_leads where profile_id = auth.uid()) $$;

comment on function public.can_see_journal_members() is
  'True for the Executive Committee, the Scientific Committee head and Journal '
  'Club leads. Governs the Journal Club member table and nothing else.';

revoke all on function public.can_see_journal_members() from public;
grant execute on function public.can_see_journal_members() to authenticated;

create or replace function public.journal_member_list()
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
  whatsapp       boolean
)
language sql stable security definer set search_path = public
as $$
  select coalesce(nullif(m.certificate_name,''), p.full_name),
         p.email, p.phone,
         coalesce(nullif(p.university,'Other'), p.university_other, p.university),
         p.academic_year, m.joined_at, m.interests, m.presenting,
         m.research_level, m.mode_pref, m.access_needs, m.consent_whatsapp
    from public.journal_members m
    join public.profiles p on p.id = m.profile_id
   where public.can_see_journal_members()
   order by m.joined_at
$$;

comment on function public.journal_member_list() is
  'Every Journal Club member and their answers. Executive Committee, Scientific '
  'Committee head and Journal Club leads only; the guard is inside the query.';

revoke all on function public.journal_member_list() from public;
grant execute on function public.journal_member_list() to authenticated;

insert into public.journal_leads (profile_id)
select id from public.profiles where lower(email) = 'nro@ladslb.org'
on conflict (profile_id) do nothing;

notify pgrst, 'reload schema';

select p.full_name, p.email, l.added_at
  from public.journal_leads l
  join public.profiles p on p.id = l.profile_id;

-- =============================================================================
-- LADS PORTAL, STAGE 24: JOURNAL CLUB MEMBERS AND SESSION RSVPS
--
-- Two questions the NRO needs answered, and they are different questions:
--   who wants to be part of the club   -> journal_members, joined once
--   who is coming to this session      -> journal_rsvps, answered each time
-- Keeping them apart means a quiet semester does not look like people leaving,
-- and a full room does not look like recruitment.
--
-- Email works the way the Treasurer's does: a trigger calls the same
-- notify_membership_change() and the edge function branches on the table name.
-- One webhook, one secret, one place mail can break.
--
-- Run it in the SQL Editor, or `ladsdb -f db/24_journal_club_members.sql`.
-- Safe to run more than once.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. The other faculties
--
-- BAU, LU and USJ are not the whole picture: other universities and academies
-- in Lebanon teach dentistry, and their students were being turned away by a
-- CHECK constraint rather than by any decision anybody made. "Other" is now a
-- real answer, with room to name the place so the list can be corrected later
-- from evidence instead of guesswork.
-- -----------------------------------------------------------------------------
alter table public.profiles drop constraint if exists profiles_university_check;
alter table public.profiles
  add constraint profiles_university_check
  check (university is null or university in ('BAU','LU','USJ','Other'));

alter table public.profiles
  add column if not exists university_other text;

comment on column public.profiles.university_other is
  'Free text, only meaningful when university = ''Other''. Names the faculty or '
  'academy so the fixed list can be extended from what people actually enter.';

-- -----------------------------------------------------------------------------
-- 1b. The trigger has to agree with the constraint
--
-- handle_new_user() silently nulls any university it does not recognise, so a
-- hand-crafted signup cannot abort the whole trigger. Widening the CHECK
-- without widening this would let a student pick "Other" and quietly lose the
-- answer, which is worse than refusing it, because nobody would know.
--
-- This is 12_architecture.sql's body with two lines changed. 12 deliberately
-- removed the registrations backfill and the membership insert that 03 had
-- ("No membership. No application. Deliberately."), and 21 moved membership
-- creation to profile_creates_membership(). Reinstating any of that here would
-- undo those decisions by accident.
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  meta  jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  uni   text;
  uni_o text;
begin
  uni := nullif(meta->>'university', '');
  if uni is not null and uni not in ('BAU','LU','USJ','Other') then
    uni := null;
  end if;
  -- Only meaningful alongside 'Other'. Dropped otherwise, so the column cannot
  -- hold a second answer that contradicts the first.
  uni_o := case when uni = 'Other' then nullif(meta->>'university_other','') end;

  -- role is never read from metadata. That value comes from the browser, and
  -- anyone can put anything in it. It always defaults to 'member'.
  insert into public.profiles
    (id, email, full_name, phone, university, university_other, academic_year)
  values (
    new.id,
    new.email,
    coalesce(nullif(meta->>'full_name',''), nullif(meta->>'name',''), ''),
    nullif(meta->>'phone',''),
    uni,
    uni_o,
    nullif(meta->>'academic_year','')
  )
  on conflict (id) do nothing;

  -- No membership. No application. Deliberately.
  return new;
end $$;


-- -----------------------------------------------------------------------------
-- 2. Club membership
--
-- Everything the old Google Form asked that the profile does not already know.
-- Name, email, phone, university and year are deliberately absent: they live on
-- the profile, and asking twice is how you end up with two answers.
-- -----------------------------------------------------------------------------
create table if not exists public.journal_members (
  profile_id        uuid primary key references public.profiles(id) on delete cascade,
  joined_at         timestamptz not null default now(),

  -- the name a certificate has to carry, which is not always the profile name
  certificate_name  text,

  interests         text[] not null default '{}',
  presenting        text,          -- willing to present a paper, and how willing
  research_level    text,
  mode_pref         text,          -- in person, virtual, hybrid, no preference

  -- Accessibility needs only. The old form asked for "medical requirements",
  -- which the club has no use for and would have to protect once collected.
  access_needs      text,

  -- Separate, optional, and off by default. The old form bundled these into one
  -- mandatory tick with the terms, which meant a student who did not want their
  -- face in LADS promotion could not register at all. That is not consent.
  consent_photos    boolean not null default false,
  consent_whatsapp  boolean not null default false,

  updated_at        timestamptz not null default now()
);

comment on table public.journal_members is
  'One row per member of the Journal Club. Joined once, not per session.';

create or replace function public.touch_journal_member()
returns trigger language plpgsql
as $$ begin new.updated_at := now(); return new; end $$;

drop trigger if exists journal_members_touch on public.journal_members;
create trigger journal_members_touch
  before update on public.journal_members
  for each row execute function public.touch_journal_member();


-- -----------------------------------------------------------------------------
-- 3. Session RSVPs
--
-- One row per person per session. Unique on the pair, so a member changing
-- their mind updates their answer instead of adding a second one.
-- -----------------------------------------------------------------------------
create table if not exists public.journal_rsvps (
  id          uuid primary key default gen_random_uuid(),
  paper_id    uuid not null references public.journal_papers(id) on delete cascade,
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  attending   boolean not null default true,
  mode        text,                -- how they plan to attend this one
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (paper_id, profile_id)
);

comment on table public.journal_rsvps is
  'Who is coming to a given session. Answered per session, unlike membership.';

create index if not exists journal_rsvps_paper_idx on public.journal_rsvps (paper_id);

drop trigger if exists journal_rsvps_touch on public.journal_rsvps;
create trigger journal_rsvps_touch
  before update on public.journal_rsvps
  for each row execute function public.touch_journal_member();


-- -----------------------------------------------------------------------------
-- 4. Row level security
--
-- A member reads and writes only their own row. The board reads everything and
-- writes nothing: an RSVP is the member's statement, and the NRO correcting it
-- silently would make the list less trustworthy, not more.
-- -----------------------------------------------------------------------------
alter table public.journal_members enable row level security;
alter table public.journal_rsvps   enable row level security;

drop policy if exists journal_members_own on public.journal_members;
create policy journal_members_own on public.journal_members
  for all to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

drop policy if exists journal_members_board_read on public.journal_members;
create policy journal_members_board_read on public.journal_members
  for select to authenticated
  using (public.can_manage_journal());

drop policy if exists journal_rsvps_own on public.journal_rsvps;
create policy journal_rsvps_own on public.journal_rsvps
  for all to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

drop policy if exists journal_rsvps_board_read on public.journal_rsvps;
create policy journal_rsvps_board_read on public.journal_rsvps
  for select to authenticated
  using (public.can_manage_journal());

grant select, insert, update, delete on public.journal_members to authenticated;
grant select, insert, update, delete on public.journal_rsvps   to authenticated;


-- -----------------------------------------------------------------------------
-- 5. The email, on the Treasurer's wiring
--
-- notify_membership_change() is misnamed for this but it is the right function:
-- it posts {type, table, record, old_record} and the edge function branches on
-- the table. Reusing it means one webhook secret, and one place to look when
-- mail stops arriving.
--
-- A join fires once. An RSVP fires when it is created and when someone changes
-- their answer, because "six became three" is exactly what the NRO needs to
-- know before she books a room.
-- -----------------------------------------------------------------------------
drop trigger if exists notify_journal_member_joined on public.journal_members;
create trigger notify_journal_member_joined
  after insert on public.journal_members
  for each row execute function public.notify_membership_change();

drop trigger if exists notify_journal_rsvp on public.journal_rsvps;
create trigger notify_journal_rsvp
  after insert on public.journal_rsvps
  for each row execute function public.notify_membership_change();

drop trigger if exists notify_journal_rsvp_changed on public.journal_rsvps;
create trigger notify_journal_rsvp_changed
  after update on public.journal_rsvps
  for each row
  when (old.attending is distinct from new.attending)
  execute function public.notify_membership_change();


-- -----------------------------------------------------------------------------
-- 6. What the NRO actually opens
--
-- A function, not a view: a view bypasses row level security, which this
-- project has avoided deliberately. This is admin-only and says so.
-- -----------------------------------------------------------------------------
create or replace function public.journal_session_list(session_paper_id uuid)
returns table (
  full_name  text,
  email      text,
  phone      text,
  university text,
  year       text,
  mode       text,
  attending  boolean
)
language sql stable security definer set search_path = public
as $$
  select p.full_name, p.email, p.phone,
         coalesce(nullif(p.university,'Other'), p.university_other, p.university),
         p.academic_year, r.mode, r.attending
    from public.journal_rsvps r
    join public.profiles p on p.id = r.profile_id
   where r.paper_id = session_paper_id
     and public.can_manage_journal()
   order by r.attending desc, p.full_name
$$;

comment on function public.journal_session_list(uuid) is
  'Who said they are coming to one session. Board only; returns nothing to '
  'anybody else because the guard is inside the query.';

revoke all on function public.journal_session_list(uuid) from public;
grant execute on function public.journal_session_list(uuid) to authenticated;

notify pgrst, 'reload schema';

-- =============================================================================
-- LADS PORTAL, STAGE 5: THE JOIN SURVEY
-- Run in the Supabase SQL Editor after 04_security.sql. Safe to re-run.
--
-- The Join form used to ask which committee a member wanted to join. That was
-- the wrong question. A first-year has no idea what the Editorial Committee
-- does, but they know perfectly well whether they want to spend a Saturday
-- screening children's teeth in Tripoli.
--
-- So we now ask what they are interested in DOING, and follow up with the
-- practical questions that decide whether they can actually be used: can they
-- travel, do they have transport, can they get a school to say yes.
--
-- Committees are still offered, but only to people who explicitly want to join
-- the workforce as a deputy head. That is a different, more serious commitment
-- and deserves its own question.
-- =============================================================================

alter table public.registrations
  -- Broad areas, e.g. {volunteering, public_health, exchange}
  add column if not exists interests text[],

  -- Answers to the follow-up questions, keyed by area. Kept as jsonb rather
  -- than thirty nullable columns, because these questions will change every
  -- year and a future board should be able to edit the form without a
  -- migration. The Treasurer's screen renders whatever is in here.
  add column if not exists interest_details jsonb not null default '{}'::jsonb,

  -- Deputy head applications
  add column if not exists workforce boolean not null default false,
  add column if not exists workforce_committee text references public.committees(id),
  add column if not exists workforce_motivation text;

create index if not exists registrations_interests_idx
  on public.registrations using gin (interests);

create index if not exists registrations_workforce_idx
  on public.registrations (workforce) where workforce = true;


-- ---------------------------------------------------------------------------
-- COMMITTEE DESCRIPTIONS
--
-- The Join form shows these to anyone who says they want to join the workforce.
-- They live in the database rather than hard-coded in the page so that a
-- committee head can have their own description corrected without anybody
-- editing HTML.
-- ---------------------------------------------------------------------------
update public.committees set description = v.description
from (values
  ('scientific',    'Research, scientific conferences, lectures and workshops, in coordination with the IADS research programme.'),
  ('fundraising',   'Sponsorships and partnerships. Approaching companies and clinics, and preparing sponsorship agreements.'),
  ('exchange',      'The annual exchange period and international placements, run with the IADS Exchange Board.'),
  ('training',      'Soft skills and professional development sessions during General Assemblies and beyond.'),
  ('public_health', 'Awareness campaigns, school visits and community screenings across Lebanon.'),
  ('voluntary',     'Oral health care in underserved regions, and hosting IADS International Voluntary Projects.'),
  ('activities',    'Trips, gatherings, sports days and clubs. The reason dental school is bearable.'),
  ('editorial',     'The LADS Gazette, posters, graphics and the visual identity of the Association.'),
  ('social_media',  'Our social platforms, digital campaigns and the online community.')
) as v(id, description)
where public.committees.id = v.id;


-- ---------------------------------------------------------------------------
-- LET THE PUBLIC FORM READ COMMITTEE NAMES
--
-- committees_read in 01_schema.sql only granted access to `authenticated`.
-- The Join form is filled in by people with no account, so the committee
-- rundown would have come back empty for exactly the audience it is for.
--
-- Committee names and descriptions are already published on the public
-- Committees page, so there is nothing here that is not already visible.
-- ---------------------------------------------------------------------------
drop policy if exists committees_public_read on public.committees;
create policy committees_public_read on public.committees
  for select to anon using (true);


-- ---------------------------------------------------------------------------
-- WHAT THE BOARD CAN ASK OF THIS
--
-- Once registrations come in, these answer the questions a committee head
-- actually has. Staff only; the role check is inside the function.
-- ---------------------------------------------------------------------------
create or replace function public.interest_counts()
returns table (interest text, people bigint)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception 'Board members only';
  end if;
  return query
  select i.interest, count(*)
    from public.registrations r,
         lateral unnest(coalesce(r.interests, '{}')) as i(interest)
   where r.rejected = false
   group by i.interest
   order by count(*) desc;
end $$;


-- =============================================================================
-- Expect "Success. No rows returned."
-- =============================================================================

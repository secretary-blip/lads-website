-- =============================================================================
-- LADS PORTAL, STAGE 19: READABLE EVENT ADDRESSES
--
-- Each activity gets its own page, so each activity needs its own address. A
-- database id works but produces a link nobody can read or trust:
--
--   event.html?id=cee002a9-dcc1-4d9d-9926-fab802adc14c
--   event.html?e=healing-hands-for-little-hearts
--
-- The second is what gets pasted into a sponsor email or an Instagram bio, so
-- the slug is worth a column. It is derived from the title and the year, filled
-- in for every activity already recorded, and kept up to date by a trigger so
-- nobody has to remember it when adding an activity.
--
-- Run it in the SQL Editor. Safe to run more than once.
-- =============================================================================

alter table public.events add column if not exists slug text;

comment on column public.events.slug is
  'Readable address for the public activity page. Filled automatically from the '
  'title and the year. Unique across all events.';


-- -----------------------------------------------------------------------------
-- 1. Title to slug
--
-- Arabic and accented titles matter here: "Télé Lumière" and the Arabic
-- campaign posts have to survive as something typable. unaccent is not
-- guaranteed to be installed, so this folds the accents it can and drops
-- anything else, falling back to the year and a number when a title leaves
-- nothing behind at all.
-- -----------------------------------------------------------------------------
create or replace function public.slugify(src text)
returns text
language sql immutable
as $$
  select nullif(
    trim(both '-' from
      regexp_replace(
        regexp_replace(
          lower(translate(coalesce(src, ''),
            'àáâãäåòóôõöøèéêëçìíîïùúûüÿñšžÀÁÂÃÄÅÒÓÔÕÖØÈÉÊËÇÌÍÎÏÙÚÛÜŸÑŠŽ',
            'aaaaaaooooooeeeeciiiiuuuuynszAAAAAAOOOOOOEEEECIIIIUUUUYNSZ')),
          '[^a-z0-9]+', '-', 'g'),
        '-{2,}', '-', 'g')),
    '');
$$;


-- -----------------------------------------------------------------------------
-- 2. A slug that is free
--
-- Two activities can share a title across years, and "Valentine's Day
-- Distributions" already does. The year settles most of those; a counter
-- settles the rest.
-- -----------------------------------------------------------------------------
create or replace function public.event_slug(p_title text, p_starts timestamptz, p_id uuid)
returns text
language plpgsql stable security definer set search_path = public
as $$
declare
  base text;
  try  text;
  n    int := 1;
begin
  base := coalesce(public.slugify(p_title), 'activity');
  base := base || '-' || to_char(p_starts at time zone 'Asia/Beirut', 'YYYY');
  try  := base;
  while exists (select 1 from public.events
                 where slug = try and (p_id is null or id <> p_id)) loop
    n := n + 1;
    try := base || '-' || n;
  end loop;
  return try;
end $$;


-- -----------------------------------------------------------------------------
-- 3. Fill in what is already recorded, oldest first so the plain slug goes to
--    the first activity of that name rather than to whichever row came back
--    first from the planner.
-- -----------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select id, title, starts_at from public.events
            where slug is null order by starts_at loop
    update public.events
       set slug = public.event_slug(r.title, r.starts_at, r.id)
     where id = r.id;
  end loop;
end $$;


-- -----------------------------------------------------------------------------
-- 4. Keep it that way
--
-- A slug is set once and then left alone. Renaming an activity after it has
-- been shared would otherwise break every link already sent out, so a rename
-- changes the title on the page and nothing else.
-- -----------------------------------------------------------------------------
create or replace function public.events_set_slug()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.slug is null or new.slug = '' then
    new.slug := public.event_slug(new.title, new.starts_at, new.id);
  end if;
  return new;
end $$;

drop trigger if exists events_slug on public.events;
create trigger events_slug
  before insert or update of title, starts_at on public.events
  for each row execute function public.events_set_slug();

create unique index if not exists events_slug_uniq on public.events (slug);

notify pgrst, 'reload schema';


-- =============================================================================
-- Confirm
-- =============================================================================
-- select slug, title from public.events order by starts_at desc limit 10;
--
-- Expect:  healing-hands-for-little-hearts-2026
--          adopt-a-heart-dar-al-aytam-al-islamiya-2026
--          valentine-s-day-distributions-2025

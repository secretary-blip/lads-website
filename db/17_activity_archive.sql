-- =============================================================================
-- LADS member portal — archive migration
--
-- Adds what the public activity archive needs:
--   1. four descriptive columns on public.events
--   2. a public.event_media table for carousels and video
--   3. public read access, scoped to published, non-members-only events
--
-- Run once in the Supabase SQL Editor. Safe to re-run.
-- Applied to production 3 September 2026.
-- Nothing here alters existing rows, existing columns, or existing policies.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Descriptive columns
--
-- image_url is the SINGLE card image — the one photograph that represents the
-- event in the grid. Everything else that belongs to the event lives in
-- event_media below. Keeping the card image here means the archive grid renders
-- from one query with no join.
-- -----------------------------------------------------------------------------
alter table public.events add column if not exists partners   text;
alter table public.events add column if not exists impact     text;
alter table public.events add column if not exists image_url  text;
alter table public.events add column if not exists category   text;

comment on column public.events.partners  is
  'Organisations that sponsored, hosted or co-delivered. Comma separated; group sponsor tiers with a vertical bar.';
comment on column public.events.impact    is
  'Documented outcome — people reached, units distributed, procedures done. Null when no figure was recorded. Never estimate.';
comment on column public.events.image_url is
  'Card image for the archive grid. Additional photographs and video belong in event_media.';
comment on column public.events.category  is
  'Public programme area, used to group the projects page.';

alter table public.events drop constraint if exists events_category_check;
alter table public.events add  constraint events_category_check
  check (category is null or category in (
    'Free care',
    'Prevention & education',
    'Student development',
    'Community & humanitarian',
    'Governance & internal'
  ));


-- -----------------------------------------------------------------------------
-- 2. Event media — ordered carousel slides and video
--
-- One row per photograph or clip. sort_order drives carousel sequence.
-- A single Instagram carousel becomes N rows sharing one event_id.
-- Deleting an event removes its media with it.
-- -----------------------------------------------------------------------------
do $$ begin
  create type media_kind as enum ('image','video');
exception when duplicate_object then null; end $$;

create table if not exists public.event_media (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events(id) on delete cascade,
  url         text not null,
  kind        media_kind not null default 'image',
  sort_order  int  not null default 0,
  caption     text,
  poster_url  text,
  width       int,
  height      int,
  created_at  timestamptz not null default now()
);

comment on table  public.event_media           is 'Photographs and video attached to an event. Ordered by sort_order.';
comment on column public.event_media.url        is 'Supabase storage path, or a site-relative asset path.';
comment on column public.event_media.poster_url is 'Still frame for a video. Ignored for images.';
comment on column public.event_media.width      is 'Pixel width, so the page can reserve space and avoid layout shift.';

create index if not exists event_media_event_idx on public.event_media (event_id, sort_order);

-- One media item cannot occupy the same slot twice within an event.
create unique index if not exists event_media_order_uniq
  on public.event_media (event_id, sort_order);


-- -----------------------------------------------------------------------------
-- 3. Indexes for the archive page
-- -----------------------------------------------------------------------------
create index if not exists events_public_archive_idx
  on public.events (starts_at desc)
  where published and not members_only;

create index if not exists events_category_idx on public.events (category);


-- -----------------------------------------------------------------------------
-- 4. Public read access
--
-- The existing policy set is default-deny and grants reads to authenticated
-- users only, so an anonymous visitor currently sees nothing. The archive is
-- meant to be public, so the anon role may read ONLY events that are explicitly
-- published and explicitly not members-only — and only the media belonging to
-- those events. Everything else stays invisible exactly as before.
--
-- This is the one part of the migration that changes who can see what.
-- Read it before you run it.
-- -----------------------------------------------------------------------------
alter table public.event_media enable row level security;

drop policy if exists events_public_read on public.events;
create policy events_public_read on public.events
  for select to anon
  using (published and not members_only);

drop policy if exists event_media_public_read on public.event_media;
create policy event_media_public_read on public.event_media
  for select to anon
  using (exists (
    select 1 from public.events e
     where e.id = event_media.event_id
       and e.published
       and not e.members_only
  ));

-- Staff manage media. Mirrors how events are already managed.
drop policy if exists event_media_staff_write on public.event_media;
create policy event_media_staff_write on public.event_media
  for all to authenticated
  using (public.is_staff())
  with check (public.is_staff());


-- =============================================================================
-- Verify
-- =============================================================================
-- select column_name, data_type from information_schema.columns
--  where table_schema='public' and table_name='events'
--    and column_name in ('partners','impact','image_url','category');
--
-- select tablename, policyname, roles from pg_policies
--  where schemaname='public' and tablename in ('events','event_media');

-- No functions are created here, so PostgREST does not need a schema reload
-- for RPC. The new columns and table are picked up on the next request.

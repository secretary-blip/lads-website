-- =============================================================================
-- LADS PORTAL, STAGE 18: ARCHIVE PHOTOGRAPHS FROM THE PORTAL
--
-- Until now the archive photographs could only be changed from the Supabase
-- dashboard, with SQL, by one person. This lets the board manage them from
-- admin-media.html instead: upload, reorder, caption, delete, choose a cover.
--
-- Two things are needed for that, and nothing else changes.
--
--   1. A single definition of who may manage media. 17_activity_archive.sql
--      used is_staff(), which covers committee_head, treasurer and executive
--      but NOT admin or super_admin, so the people most likely to be doing this
--      were locked out of their own archive.
--
--   2. Write access to the 'media' storage bucket for those same people.
--      Reads stay public: the bucket holds the photographs the archive page
--      shows to visitors.
--
-- Run it in the SQL Editor. Safe to run more than once.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Who may manage archive media
-- -----------------------------------------------------------------------------
create or replace function public.can_manage_media()
returns boolean
language sql stable security definer set search_path = public
as $$ select coalesce(
     (select role in ('committee_head','treasurer','executive','admin','super_admin')
        from public.profiles where id = auth.uid()), false) $$;

comment on function public.can_manage_media() is
  'True for any board role. Used by the archive media policies so that admins '
  'and super admins are not locked out of the archive by is_staff().';

grant execute on function public.can_manage_media() to authenticated;


-- -----------------------------------------------------------------------------
-- 2. The event_media table
--
-- Public read stays exactly as 17 left it: anonymous visitors see the media of
-- published, non members-only events and nothing else. Only the write policy
-- widens, from is_staff() to can_manage_media().
-- -----------------------------------------------------------------------------
drop policy if exists event_media_staff_write on public.event_media;
create policy event_media_staff_write on public.event_media
  for all to authenticated
  using (public.can_manage_media())
  with check (public.can_manage_media());


-- -----------------------------------------------------------------------------
-- 3. A cover photograph is a change to the event row
--
-- events_update in 13_policies.sql allows admins and committee heads. A
-- treasurer or executive editing the archive would be refused halfway through,
-- after the upload had already happened, which is a confusing place to fail.
-- This adds a narrow second policy for the same board roles.
-- -----------------------------------------------------------------------------
drop policy if exists events_media_update on public.events;
create policy events_media_update on public.events
  for update to authenticated
  using (public.can_manage_media())
  with check (public.can_manage_media());


-- -----------------------------------------------------------------------------
-- 4. Storage
--
-- The bucket is public to read, which is the point: the archive is public.
-- Writing is restricted to the board. Delete is allowed here, unlike the
-- payment-proofs bucket, because a photograph is not evidence and a board
-- member has to be able to take down a photograph that should not be up.
--
-- Wrapped, because on some projects storage.objects is owned by the storage
-- role and the SQL Editor cannot alter its policies. If that happens the same
-- four policies can be added from Storage, Policies in the dashboard.
-- -----------------------------------------------------------------------------
do $$
begin
  drop policy if exists media_public_read on storage.objects;
  drop policy if exists media_board_insert on storage.objects;
  drop policy if exists media_board_update on storage.objects;
  drop policy if exists media_board_delete on storage.objects;

  create policy media_public_read on storage.objects
    for select to anon, authenticated
    using (bucket_id = 'media');

  create policy media_board_insert on storage.objects
    for insert to authenticated
    with check (bucket_id = 'media' and public.can_manage_media());

  create policy media_board_update on storage.objects
    for update to authenticated
    using (bucket_id = 'media' and public.can_manage_media())
    with check (bucket_id = 'media' and public.can_manage_media());

  create policy media_board_delete on storage.objects
    for delete to authenticated
    using (bucket_id = 'media' and public.can_manage_media());
exception
  when insufficient_privilege then
    raise notice 'storage.objects policies must be set from the dashboard on this project.';
end $$;

-- 25 MB a file, and only the types the archive page can actually display.
-- The uploader shrinks photographs in the browser before sending, so a normal
-- photograph lands well under this. Videos are the reason it is not smaller.
update storage.buckets
   set public = true,
       file_size_limit = 26214400,
       allowed_mime_types = array[
     'image/png','image/jpeg','image/webp','image/gif','video/mp4','video/quicktime']
 where id = 'media';

notify pgrst, 'reload schema';


-- =============================================================================
-- Confirm
-- =============================================================================
-- select policyname from pg_policies
--  where tablename = 'objects' and schemaname = 'storage' and policyname like 'media%';
-- select public.can_manage_media();

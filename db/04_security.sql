-- =============================================================================
-- LADS PORTAL, STAGE 4: SECURITY FIXES
-- Run in the Supabase SQL Editor after the other three files. Safe to re-run.
--
-- Found while auditing the row-level security policies before launch. Three of
-- these are real privilege problems, not theoretical ones. All three are
-- invisible from the website, because the website never asks for the things
-- that were possible. They matter because the database was still allowing them
-- to anyone who sent a request directly to the API, which takes about two
-- minutes to work out and requires no special access.
--
-- The pattern behind all three: a row-level policy controls WHICH ROWS you may
-- touch, not WHICH COLUMNS. Saying "you may update your own application" also
-- said "you may set your own application to accepted".
-- =============================================================================


-- ---------------------------------------------------------------------------
-- FIX 1: AN APPLICANT COULD ACCEPT THEIR OWN APPLICATION
--
-- applications_insert allowed any signed-in member to create a row as long as
-- profile_id was their own. It said nothing about status, so a member could
-- submit an application already marked 'accepted', with a reviewer note they
-- wrote themselves.
--
-- applications_update had the same hole in the other direction: an applicant
-- could change their own submitted application to 'accepted' at any time.
--
-- The apply page only ever sets 'withdrawn', so nothing on the website did
-- this. That is not a defence. The API is public and the anon key is in the
-- page source, which is by design; the database is what has to say no.
--
-- Now: members may create applications only as 'submitted', and may only ever
-- move their own to 'withdrawn'. Everything else is for reviewers.
-- ---------------------------------------------------------------------------
create or replace function public.guard_applications()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  reviewer boolean;
begin
  reviewer := public.is_exec() or (
    public.my_role() = 'committee_head'
    and coalesce(new.committee_id, old.committee_id) = public.my_committee()
  );

  if tg_op = 'INSERT' then
    if not reviewer then
      new.status        := 'submitted';
      new.reviewer_id   := null;
      new.reviewer_note := null;
      new.decided_at    := null;
    end if;
    return new;
  end if;

  -- UPDATE
  if not reviewer then
    -- The applicant may withdraw, and nothing else.
    if new.status is distinct from old.status and new.status <> 'withdrawn' then
      raise exception 'Only a reviewer may change the status of an application';
    end if;
    if new.reviewer_id   is distinct from old.reviewer_id
    or new.reviewer_note is distinct from old.reviewer_note
    or new.decided_at    is distinct from old.decided_at
    or new.committee_id  is distinct from old.committee_id
    or new.profile_id    is distinct from old.profile_id then
      raise exception 'Only a reviewer may change that';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists guard_applications_trg on public.applications;
create trigger guard_applications_trg
  before insert or update on public.applications
  for each row execute function public.guard_applications();


-- ---------------------------------------------------------------------------
-- FIX 2: THE SAME HOLE IN PROPOSALS
--
-- proposals_update was already limited to reviewers, so the update side was
-- fine. The insert side was not: a member could submit a project idea already
-- marked 'approved' with a note supposedly from the board.
-- ---------------------------------------------------------------------------
create or replace function public.guard_proposals()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if not (public.is_exec() or public.my_role() = 'committee_head') then
      new.status        := 'submitted';
      new.reviewer_id   := null;
      new.reviewer_note := null;
      new.decided_at    := null;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists guard_proposals_trg on public.proposals;
create trigger guard_proposals_trg
  before insert or update on public.proposals
  for each row execute function public.guard_proposals();


-- ---------------------------------------------------------------------------
-- FIX 3: MEMBERS COULD MARK THEMSELVES AS HAVING ATTENDED
--
-- eventregs_update let a member update their own registration row, which is
-- correct: they need to be able to cancel. But `attended` lives on that same
-- row, so they could also mark themselves present at an event they skipped.
--
-- Attendance is not trivial. It is what a certificate of participation, an
-- exchange application, or an IADS report would be based on. It has to be
-- something only the board can assert.
-- ---------------------------------------------------------------------------
create or replace function public.guard_event_registrations()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if not public.is_staff() then
      new.attended := null;
    end if;
    return new;
  end if;

  if new.attended is distinct from old.attended and not public.is_staff() then
    raise exception 'Only the board may record attendance';
  end if;
  if new.profile_id is distinct from old.profile_id
  or new.event_id   is distinct from old.event_id then
    raise exception 'A registration cannot be moved to another person or event';
  end if;

  return new;
end $$;

drop trigger if exists guard_event_registrations_trg on public.event_registrations;
create trigger guard_event_registrations_trg
  before insert or update on public.event_registrations
  for each row execute function public.guard_event_registrations();


-- ---------------------------------------------------------------------------
-- FIX 4: A MEMBER COULD REGISTER FOR AN UNPUBLISHED EVENT
--
-- Members cannot see draft events, because events_read hides them. But
-- eventregs_insert only checked that profile_id was their own, so someone who
-- learned a draft event's id could register for it before it was announced.
-- Small, but it defeats the point of drafting.
--
-- Also enforces capacity in the database rather than in the page, so the
-- twentieth person cannot get a place in a twenty-place room by clicking at the
-- same moment as somebody else.
-- ---------------------------------------------------------------------------
create or replace function public.guard_event_capacity()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  e     public.events%rowtype;
  taken int;
begin
  select * into e from public.events where id = new.event_id;
  if not found then
    raise exception 'That event does not exist';
  end if;

  if not public.is_staff() then
    if not e.published then
      raise exception 'That event is not open for registration yet';
    end if;
    if e.registration_opens is not null and now() < e.registration_opens then
      raise exception 'Registration for that event has not opened yet';
    end if;
    if e.registration_closes is not null and now() > e.registration_closes then
      raise exception 'Registration for that event has closed';
    end if;
  end if;

  if e.capacity is not null and coalesce(new.cancelled, false) = false then
    select count(*) into taken
      from public.event_registrations
     where event_id = new.event_id
       and cancelled = false
       and id is distinct from new.id;
    if taken >= e.capacity then
      raise exception 'That event is full';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists guard_event_capacity_trg on public.event_registrations;
create trigger guard_event_capacity_trg
  before insert or update on public.event_registrations
  for each row execute function public.guard_event_capacity();


-- ---------------------------------------------------------------------------
-- FIX 5: LIMIT WHAT CAN BE UPLOADED AS A PAYMENT PROOF
--
-- The public Join form uploads to the payment-proofs bucket as an anonymous
-- visitor, which it has to, because the person paying does not have an account
-- yet. That means anyone on the internet can upload to it.
--
-- Capping size and file type turns "someone could fill our storage quota with
-- video files" into "someone could upload a lot of small images", which is
-- merely annoying rather than an outage.
-- ---------------------------------------------------------------------------
update storage.buckets
   set file_size_limit = 5242880,   -- 5 MB, matches the check in join.html
       allowed_mime_types = array['image/png','image/jpeg','image/webp','image/heic','application/pdf']
 where id = 'payment-proofs';


-- ---------------------------------------------------------------------------
-- FIX 6: THE ROLE GUARD MUST NOT LOCK OUT THE DATABASE OWNER
--
-- guard_role_changes (in 03_auth_update.sql) refuses any role change unless
-- is_exec() is true. In the SQL Editor there is no signed-in user, so auth.uid()
-- is null, is_exec() is false, and the guard blocks the one person trying to fix
-- things. If the only executive ever demoted themselves, nobody could put it
-- back, from anywhere.
--
-- A guard meant for the public API should not apply to the database owner, who
-- already has unrestricted access by definition. So: enforce it when there is an
-- authenticated user, skip it when there is not.
-- ---------------------------------------------------------------------------
create or replace function public.guard_role_changes()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.role is distinct from old.role or
     new.committee_id is distinct from old.committee_id then
    -- auth.uid() is null in the SQL Editor, in migrations, and for the service
    -- role. All three are already trusted contexts.
    if auth.uid() is not null and not public.is_exec() then
      raise exception 'Only the Executive Committee may change roles';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists guard_role_changes_trg on public.profiles;
create trigger guard_role_changes_trg
  before update on public.profiles
  for each row execute function public.guard_role_changes();


-- =============================================================================
-- REVIEWED AND DELIBERATELY LEFT AS THEY ARE
--
-- These came up in the audit and are not bugs, but the next board should know
-- the decision was made rather than overlooked.
--
-- 1. ALL NINE COMMITTEE HEADS CAN READ EVERY MEMBER'S PROFILE.
--    profiles_self_read grants read access to anyone with a staff role, which
--    includes phone numbers and email addresses for the whole membership.
--    That is a lot of people holding a lot of personal data.
--    Kept because heads genuinely need to contact members about their
--    committee's activities, and the alternative is fifteen people asking the
--    General Secretary for phone numbers all year.
--    If the board would rather tighten it, change is_staff() to
--    handles_money() or is_exec() in that one policy.
--
-- 2. ANY STAFF MEMBER CAN EDIT ANY EVENT.
--    events_update is open to all staff, so a committee head can edit another
--    committee's event. Kept because the board is fifteen students who cover
--    for each other constantly, and the audit trail matters more than the lock.
--
-- 3. ANYONE CAN SUBMIT THE PUBLIC JOIN FORM.
--    It has to be open, or nobody could join. Supabase applies its own rate
--    limits. If it is ever abused, the answer is a captcha on that form, not a
--    policy change.
--
-- 4. THE ANON KEY IS VISIBLE IN THE PAGE SOURCE.
--    That is how Supabase is designed to work and it is not a leak. The key
--    identifies the project, it does not grant access. Every table has RLS
--    enabled and no policy grants blanket reads. This is exactly why the fixes
--    above had to be made in the database rather than in the website.
-- =============================================================================

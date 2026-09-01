-- =============================================================================
-- LADS PORTAL, STAGE 16: MEMBERSHIP AUDIT TRAIL AND REVERSIBLE VERIFICATION
-- Run after 15. Safe to re-run.
--
-- Two problems, one file.
--
-- 1. Verification was a one-way ratchet. admin-dues.html hid every action once
--    a membership reached 'paid', so a payment confirmed by mistake, or one
--    where the transfer never actually arrived, could not be undone through the
--    website at all.
--
-- 2. `verified_by` and `verified_at` are single columns, so they are overwritten
--    every time. The moment verification can be reversed, "who changed this and
--    why" stops being reconstructable, and for money that is the wrong place to
--    have a gap.
--
-- What this does NOT do is grant DELETE on memberships. 13_policies.sql says
--   "No DELETE. A payment record is not something anyone deletes through a
--    website."
-- That still holds. A payment that never arrived is a status change with a
-- reason attached, not a row that disappears. LADS is a registered NGO and
-- these are its financial records.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 1. THE LOG
--
-- Append only. Nothing writes to it except the trigger below, which is security
-- definer and so bypasses RLS. There is deliberately no insert, update or
-- delete policy: a log a board member can edit is not a log.
-- ---------------------------------------------------------------------------
create table if not exists public.membership_events (
  id             uuid primary key default gen_random_uuid(),
  membership_id  uuid not null references public.memberships(id) on delete cascade,
  actor_id       uuid references public.profiles(id),
  from_status    payment_status,
  to_status      payment_status not null,
  note           text,
  created_at     timestamptz not null default now()
);

create index if not exists membership_events_membership_idx
  on public.membership_events(membership_id, created_at desc);

alter table public.membership_events enable row level security;

-- A member may read their own history, so "I was marked paid then unmarked"
-- is something they can see rather than something that happens to them
-- invisibly. Admins read everything.
drop policy if exists membership_events_read on public.membership_events;
create policy membership_events_read on public.membership_events
  for select to authenticated
  using (
    public.is_admin()
    or exists (
      select 1 from public.memberships m
       where m.id = membership_events.membership_id
         and m.profile_id = auth.uid()
    )
  );


-- ---------------------------------------------------------------------------
-- 2. THE TRIGGER
--
-- actor_id is auth.uid(), which is null when a row is changed from the SQL
-- Editor rather than through the site. That is correct and worth keeping: a
-- null actor means "changed directly in the database", which is exactly the
-- thing an audit trail should not quietly attribute to a person.
-- ---------------------------------------------------------------------------
create or replace function public.log_membership_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.membership_events (membership_id, actor_id, from_status, to_status, note)
    values (new.id, auth.uid(), null, new.status, new.notes);
  elsif new.status is distinct from old.status then
    insert into public.membership_events (membership_id, actor_id, from_status, to_status, note)
    values (new.id, auth.uid(), old.status, new.status, new.notes);
  end if;
  return new;
end $$;

drop trigger if exists log_membership_status_change on public.memberships;
create trigger log_membership_status_change
  after insert or update on public.memberships
  for each row execute function public.log_membership_status();


-- ---------------------------------------------------------------------------
-- 3. REVERSING A CONFIRMATION
--
-- Deliberately lands on 'rejected' rather than 'unpaid'. The notify function
-- already emails the member on 'rejected' and puts `notes` in the body, so the
-- reason the Treasurer types is what the member reads. Reversing to 'unpaid'
-- would send nothing at all, and a membership that silently stops being valid
-- is worse than one that is withdrawn with an explanation.
--
-- The reason is required. A reversal with no explanation is the case that
-- generates the angry message to the Treasurer three weeks later.
-- ---------------------------------------------------------------------------
create or replace function public.reverse_membership(
  membership_id uuid,
  reason        text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_status payment_status;
begin
  if not public.is_admin() then
    raise exception 'Administrators only';
  end if;

  if reason is null or btrim(reason) = '' then
    raise exception 'A reversal needs a reason. The member is sent this text.';
  end if;

  select status into current_status
    from public.memberships
   where id = reverse_membership.membership_id;

  if current_status is null then
    raise exception 'No such membership';
  end if;

  if current_status <> 'paid'::payment_status then
    raise exception 'Only a confirmed payment can be reversed';
  end if;

  update public.memberships
     set status      = 'rejected'::payment_status,
         notes       = btrim(reason),
         verified_by = auth.uid(),
         verified_at = now(),
         paid_on     = null
   where id = reverse_membership.membership_id;
end $$;

revoke all on function public.reverse_membership(uuid, text) from public;
grant execute on function public.reverse_membership(uuid, text) to authenticated;

comment on function public.reverse_membership(uuid, text) is
  'Undo a confirmed payment. Admin only, reason required, logged in membership_events.';

comment on table public.membership_events is
  'Append-only record of every membership status change. Written by trigger only.';

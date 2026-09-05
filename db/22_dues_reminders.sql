-- ---------------------------------------------------------------------------
-- 22. Sending a dues reminder from the portal
--
-- The reminder button opened the Treasurer's mail client. That works, but it
-- leaves no record: nobody can tell who was chased, when, or how often, and
-- the next Treasurer inherits none of it. This makes a reminder the same shape
-- as confirming a payment: one RPC, sent by the server, written to the row.
--
-- No new secret. The trigger below calls notify_membership_change(), which
-- already holds the webhook secret from migration 15, so the reminder goes out
-- through the same Edge Function as every other membership email.
-- ---------------------------------------------------------------------------

alter table public.memberships
  add column if not exists reminder_sent_at timestamptz,
  add column if not exists reminder_count   integer not null default 0;

comment on column public.memberships.reminder_sent_at is
  'When the member was last chased for these dues. Null means never.';

-- Admin only. A member must not be able to email themselves from their own
-- row, and the guard trigger would refuse the write anyway, hence the flag.
create or replace function public.remind_membership(membership_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  m public.memberships;
begin
  if not public.is_admin() then
    raise exception 'Only an administrator may send a reminder';
  end if;

  select * into m from public.memberships where id = membership_id;
  if not found then
    raise exception 'No such membership';
  end if;

  -- Chasing someone who has paid, or who is waiting on us to check their
  -- screenshot, is the fastest way to make the portal look broken.
  if m.status not in ('unpaid'::payment_status, 'rejected'::payment_status) then
    raise exception 'That membership is not outstanding';
  end if;

  perform set_config('lads.system', 'on', true);

  update public.memberships
     set reminder_sent_at = now(),
         reminder_count   = reminder_count + 1
   where id = membership_id;
end $$;

revoke all on function public.remind_membership(uuid) from public;
grant execute on function public.remind_membership(uuid) to authenticated;

-- Fires only when the reminder stamp actually moves, so editing a note or
-- confirming a payment never sends one.
drop trigger if exists notify_membership_reminded on public.memberships;
create trigger notify_membership_reminded
  after update on public.memberships
  for each row
  when (new.reminder_sent_at is distinct from old.reminder_sent_at
        and new.reminder_sent_at is not null)
  execute function public.notify_membership_change();

notify pgrst, 'reload schema';

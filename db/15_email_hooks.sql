-- =============================================================================
-- LADS PORTAL, STAGE 15: EMAIL TRIGGERS ON MEMBERSHIPS
-- Run after 14. Safe to re-run.
--
-- Replaces the triggers that fired on `registrations`, which no longer exists.
-- Emails are now driven by the membership status:
--
--   -> pending    the Treasurer is told a payment is waiting
--   -> paid       the member is told they are confirmed
--   -> rejected   the member is told what to send instead
--
-- BEFORE RUNNING: replace WEBHOOK_SECRET_HERE below with your secret, the same
-- string set in Edge Functions -> Secrets. Two places.
--
-- Run it and leave the file with the placeholder. Do not commit your filled-in
-- copy.
-- =============================================================================

create extension if not exists pg_net;

create or replace function public.notify_membership_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  fn_url text := 'https://fazswkdinsbqymgwlebr.supabase.co/functions/v1/notify';
  secret text := 'WEBHOOK_SECRET_HERE';   -- <<< replace
begin
  -- Fire and forget. net.http_post queues the request and returns at once, so a
  -- slow or failing mail provider can never block or roll back a payment. A
  -- member submitting their dues must never see an error because Resend was
  -- having a bad afternoon.
  perform net.http_post(
    url     := fn_url,
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'x-webhook-secret', secret
               ),
    body    := jsonb_build_object(
                 'type',       tg_op,
                 'table',      tg_table_name,
                 'record',     to_jsonb(new),
                 'old_record', case when tg_op = 'UPDATE' then to_jsonb(old) else null end
               )
  );
  return new;
end $$;


-- Retire the old ones. They pointed at a table that no longer exists.
drop trigger if exists notify_new_registration on public.registrations_archive;
drop trigger if exists notify_payment_decision on public.registrations_archive;
drop function if exists public.notify_registration_change() cascade;


-- A membership created already in `pending` means someone submitted proof at the
-- same moment they created the record, which is the normal path from pay.html.
drop trigger if exists notify_membership_submitted on public.memberships;
create trigger notify_membership_submitted
  after insert on public.memberships
  for each row
  when (new.status = 'pending'::payment_status)
  execute function public.notify_membership_change();


-- Only real transitions. Without the WHEN clause this fires on every edit, and
-- a member would get "your membership is confirmed" again each time the
-- Treasurer corrected a typo in the notes.
drop trigger if exists notify_membership_changed on public.memberships;
create trigger notify_membership_changed
  after update on public.memberships
  for each row
  when (
    old.status is distinct from new.status
    and new.status in ('pending'::payment_status,
                       'paid'::payment_status,
                       'rejected'::payment_status)
  )
  execute function public.notify_membership_change();


-- =============================================================================
-- CHECKING IT
--   select status_code, error_msg, created
--     from net._http_response order by created desc limit 5;
--
--   200  the function accepted it, check resend.com -> Logs next
--   401  the secret here does not match Edge Functions -> Secrets
--   404  the function is not deployed, or is not named exactly "notify"
--   none the trigger did not fire
-- =============================================================================

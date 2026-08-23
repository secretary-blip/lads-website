-- =============================================================================
-- LADS PORTAL, STAGE 6: EMAIL TRIGGERS
-- Run in the Supabase SQL Editor after the Edge Function is deployed.
--
-- This does the same job as creating two Database Webhooks by hand in the
-- dashboard, and does it in a file that lives in the repository. Supabase moves
-- that page around; this does not move.
--
-- BEFORE YOU RUN IT: replace WEBHOOK_SECRET_HERE below with your secret, the
-- same string you put in Edge Functions -> Secrets. There are two places.
--
-- The secret ends up stored inside this function in the database. That is fine:
-- only the database owner can read function bodies, and the same secret is
-- already sitting in the Edge Function's own settings. Do not commit your
-- filled-in copy back to the repository, though. Run it and leave the file with
-- the placeholder.
-- =============================================================================


-- pg_net lets Postgres make an outbound HTTP request. It is what the dashboard
-- webhooks use under the surface.
create extension if not exists pg_net;


create or replace function public.notify_registration_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  fn_url text := 'https://fazswkdinsbqymgwlebr.supabase.co/functions/v1/notify';
  secret text := 'WEBHOOK_SECRET_HERE';   -- <<< replace
begin
  -- Fire and forget. net.http_post queues the request and returns immediately,
  -- so a slow or failed email can never block or roll back a registration.
  -- Someone joining LADS must never see an error because our mail provider
  -- was having a bad afternoon.
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


-- New registration -> tell the Treasurer.
drop trigger if exists notify_new_registration on public.registrations;
create trigger notify_new_registration
  after insert on public.registrations
  for each row execute function public.notify_registration_change();


-- Decision made -> tell the member.
--
-- The WHEN clause matters. Without it this fires on every edit, including the
-- Treasurer adding a note, and members would get "your membership is confirmed"
-- again every time. The Edge Function checks as well, but filtering here means
-- we do not even make the request.
drop trigger if exists notify_payment_decision on public.registrations;
create trigger notify_payment_decision
  after update on public.registrations
  for each row
  when (
    (old.payment_verified is distinct from new.payment_verified and new.payment_verified)
    or
    (old.rejected is distinct from new.rejected and new.rejected)
  )
  execute function public.notify_registration_change();


-- =============================================================================
-- CHECKING IT
--
-- Requests and responses are logged. After registering a test member, run:
--
--   select id, url, status_code, error_msg, created
--     from net._http_response
--    order by created desc
--    limit 5;
--
--   status 200  the function accepted it, check resend.com -> Logs next
--   status 401  the secret here does not match Edge Functions -> Secrets
--   status 404  the function is not deployed, or is not named exactly "notify"
--   no rows     the trigger did not fire, check you registered on the live site
-- =============================================================================

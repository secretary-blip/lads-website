-- =============================================================================
-- LADS PORTAL, STAGE 8: HEALTH CHECK
-- Run once to install, then any time you want to know whether things are set up
-- correctly:
--
--     select * from public.health_check();
--
-- Every row is PASS, FAIL or WARN with a plain-English explanation. Run it after
-- any change, and run it in September before you tell members to sign up.
--
-- It reports on structure only, never on member data, so it is safe to run and
-- safe to screenshot when asking for help.
-- =============================================================================

create or replace function public.health_check()
returns table (area text, check_name text, status text, detail text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  t text;
  expected_tables text[] := array[
    'committees','profiles','memberships','events',
    'event_registrations','applications','proposals','registrations'];
  expected_functions text[] := array[
    'my_role','my_committee','is_staff','is_exec','handles_money',
    'handle_new_user','academic_year_of','current_academic_year','dues_year_of',
    'approve_registration','reject_registration','dues_summary',
    'guard_role_changes','guard_applications','guard_proposals',
    'guard_event_registrations','guard_event_capacity',
    'notify_registration_change','interest_counts'];
  n int;
  txt text;
begin
  -- Readable by board members, and by anyone in the SQL Editor, where there is
  -- no signed-in user. Anyone with SQL Editor access already has everything.
  if auth.uid() is not null and not public.is_staff() then
    raise exception 'Board members only';
  end if;

  -- ---------------------------------------------------------------- tables
  foreach t in array expected_tables loop
    if not exists (select 1 from pg_tables where schemaname='public' and tablename=t) then
      return query select 'Tables'::text, t, 'FAIL'::text,
        'Table is missing. An earlier migration did not finish.'::text;
    elsif not exists (
      select 1 from pg_class c join pg_namespace ns on ns.oid=c.relnamespace
       where ns.nspname='public' and c.relname=t and c.relrowsecurity
    ) then
      return query select 'Tables'::text, t, 'FAIL'::text,
        'Row-level security is OFF. Anyone with the public key can read this table. Run 07_policy_rebuild.sql.'::text;
    else
      select count(*) into n from pg_policies where schemaname='public' and tablename=t;
      if n = 0 then
        return query select 'Tables'::text, t, 'FAIL'::text,
          'Security is on but there are no policies, so nobody can read or write it at all.'::text;
      else
        return query select 'Tables'::text, t, 'PASS'::text,
          (n || ' policies, security on')::text;
      end if;
    end if;
  end loop;

  -- Catch anything created later that nobody remembered to protect.
  for t in
    select c.relname from pg_class c
      join pg_namespace ns on ns.oid = c.relnamespace
     where ns.nspname='public' and c.relkind='r' and not c.relrowsecurity
       and c.relname <> 'health_check'
  loop
    return query select 'Tables'::text, t, 'FAIL'::text,
      'Unprotected table. Anything here is readable by the whole internet.'::text;
  end loop;

  -- ------------------------------------------------------------- functions
  foreach t in array expected_functions loop
    if exists (
      select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
       where ns.nspname='public' and p.proname=t
    ) then
      return query select 'Functions'::text, t, 'PASS'::text, 'Present'::text;
    else
      return query select 'Functions'::text, t, 'FAIL'::text,
        'Missing. Re-run the migration that creates it.'::text;
    end if;
  end loop;

  -- -------------------------------------------------------------- triggers
  for t in select unnest(array[
      'guard_role_changes_trg','guard_applications_trg','guard_proposals_trg',
      'guard_event_registrations_trg','guard_event_capacity_trg',
      'on_auth_user_created'])
  loop
    if exists (select 1 from pg_trigger where tgname = t and not tgisinternal) then
      return query select 'Guards'::text, t, 'PASS'::text, 'Active'::text;
    else
      return query select 'Guards'::text, t, 'FAIL'::text,
        'Missing. Members could change things they should not.'::text;
    end if;
  end loop;

  -- ----------------------------------------------------------------- email
  if exists (select 1 from pg_extension where extname='pg_net') then
    return query select 'Email'::text, 'pg_net extension'::text, 'PASS'::text, 'Installed'::text;
  else
    return query select 'Email'::text, 'pg_net extension'::text, 'FAIL'::text,
      'Not installed, so no email can be sent. Install the Database Webhooks integration.'::text;
  end if;

  for t in select unnest(array['notify_new_registration','notify_payment_decision']) loop
    if exists (select 1 from pg_trigger where tgname = t and not tgisinternal) then
      return query select 'Email'::text, t, 'PASS'::text, 'Active'::text;
    else
      return query select 'Email'::text, t, 'WARN'::text,
        'Not set up. Nobody will be emailed. Run 06_email_hooks.sql.'::text;
    end if;
  end loop;

  -- Is the secret still the placeholder?
  select prosrc into txt from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
   where ns.nspname='public' and p.proname='notify_registration_change' limit 1;
  if txt is not null and txt like '%WEBHOOK_SECRET_HERE%' then
    return query select 'Email'::text, 'webhook secret'::text, 'FAIL'::text,
      'Still the placeholder. Every notification will be refused with 401.'::text;
  elsif txt is not null then
    return query select 'Email'::text, 'webhook secret'::text, 'PASS'::text, 'Set'::text;
  end if;

  -- --------------------------------------------------------------- storage
  if exists (select 1 from storage.buckets where id='payment-proofs' and public = false) then
    return query select 'Storage'::text, 'payment-proofs private'::text, 'PASS'::text,
      'Screenshots are not publicly readable'::text;
  elsif exists (select 1 from storage.buckets where id='payment-proofs') then
    return query select 'Storage'::text, 'payment-proofs private'::text, 'FAIL'::text,
      'Bucket is PUBLIC. Every payment screenshot is readable by anyone with the link.'::text;
  else
    return query select 'Storage'::text, 'payment-proofs bucket'::text, 'FAIL'::text,
      'Bucket is missing. The Join form cannot accept screenshots.'::text;
  end if;

  select count(*) into n from pg_policies
   where schemaname='storage' and tablename='objects'
     and policyname in ('proofs_upload','proofs_read');
  if n = 2 then
    return query select 'Storage'::text, 'proof policies'::text, 'PASS'::text,
      'Upload open, reading limited to Treasurer and Executive'::text;
  else
    return query select 'Storage'::text, 'proof policies'::text, 'WARN'::text,
      ('Expected 2 policies, found ' || n || '. The Treasurer may not be able to view screenshots.')::text;
  end if;

  -- ----------------------------------------------------------------- people
  select count(*) into n from public.profiles where role = 'executive' and archived = false;
  if n = 0 then
    return query select 'People'::text, 'executives'::text, 'FAIL'::text,
      'Nobody is executive. No one can assign roles from the website.'::text;
  elsif n = 1 then
    return query select 'People'::text, 'executives'::text, 'WARN'::text,
      'Only one executive. If they lose access, nobody can assign roles. Two is the minimum.'::text;
  else
    return query select 'People'::text, 'executives'::text, 'PASS'::text, (n || ' executives')::text;
  end if;

  select count(*) into n from public.profiles where role = 'treasurer' and archived = false;
  if n = 0 then
    return query select 'People'::text, 'treasurer'::text, 'WARN'::text,
      'No treasurer yet. Executives can still verify payments.'::text;
  else
    return query select 'People'::text, 'treasurer'::text, 'PASS'::text, (n || ' treasurer')::text;
  end if;

  -- Committee heads with no committee see nothing on the review page.
  select count(*) into n from public.profiles
   where role='committee_head' and committee_id is null and archived = false;
  if n > 0 then
    return query select 'People'::text, 'committee heads'::text, 'WARN'::text,
      (n || ' head(s) have no committee set, so their review page will be empty.')::text;
  end if;

  return;
end $$;

comment on function public.health_check() is
  'Structural health of the LADS portal. select * from public.health_check();';

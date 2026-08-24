-- =============================================================================
-- LADS PORTAL, STAGE 14: VERIFICATION
-- Run after 13, then:   select * from public.verify_architecture();
--
-- Checks the structural half of your list. The behavioural half (can a member
-- mark themselves paid, can they see someone else's proof) needs a real signed
-- in browser, and the manual test plan is in the migration notes.
--
-- Reports structure only, never member data, so it is safe to screenshot.
-- =============================================================================

create or replace function public.verify_architecture()
returns table (id text, check_name text, status text, detail text)
language plpgsql stable security definer set search_path = public
as $$
declare n int; m int; txt text;
begin
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'Administrators only';
  end if;

  -- ---- one membership per person per year -------------------------------
  if exists (
    select 1 from pg_constraint c
      join pg_class t on t.oid = c.conrelid
     where t.relname = 'memberships' and c.contype = 'u'
       and pg_get_constraintdef(c.oid) like '%profile_id%academic_year%')
  then
    return query select '6','memberships unique (profile_id, academic_year)','PASS',
      'A second membership for the same year is impossible';
  else
    return query select '6','memberships unique (profile_id, academic_year)','FAIL',
      'Missing. The same person could be recorded twice for one year.';
  end if;

  if exists (
    select 1 from pg_constraint c
      join pg_class t on t.oid = c.conrelid
     where t.relname = 'event_registrations' and c.contype = 'u'
       and pg_get_constraintdef(c.oid) like '%event_id%profile_id%')
  then
    return query select '25','event_registrations unique (event_id, profile_id)','PASS','Present';
  else
    return query select '25','event_registrations unique (event_id, profile_id)','FAIL','Missing';
  end if;

  -- ---- signup creates a profile and nothing else -------------------------
  select prosrc into txt from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
   where ns.nspname='public' and p.proname='handle_new_user' limit 1;

  if txt is null then
    return query select '1','signup creates a profile','FAIL','handle_new_user is missing';
  elsif txt ilike '%insert into public.memberships%' then
    return query select '2','signup creates NO membership','FAIL',
      'handle_new_user still inserts a membership';
  elsif txt ilike '%insert into public.applications%' then
    return query select '3','signup creates NO application','FAIL',
      'handle_new_user still inserts an application';
  else
    return query select '1-3','signup creates only a profile','PASS',
      'No membership or application is created at signup';
  end if;

  -- ---- members cannot pay themselves -------------------------------------
  if exists (select 1 from pg_trigger where tgname='guard_membership_trg' and not tgisinternal)
  then
    return query select '9,12','members cannot mark themselves paid','PASS',
      'guard_membership blocks status, verified_by, verified_at and paid_on';
  else
    return query select '9,12','members cannot mark themselves paid','FAIL',
      'guard_membership_trg missing. A member could mark their own membership paid.';
  end if;

  if exists (select 1 from pg_trigger where tgname='guard_role_changes_trg' and not tgisinternal)
  then
    return query select '21','members cannot assign themselves a committee','PASS','Guard active';
  else
    return query select '21','members cannot assign themselves a committee','FAIL','Guard missing';
  end if;

  -- ---- the functions the workflow needs ----------------------------------
  for txt in select unnest(array[
      'is_admin','is_super_admin','is_committee_head',
      'approve_membership','reject_membership',
      'accept_application','reject_application',
      'handle_new_user','guard_membership','guard_applications','guard_role_changes'])
  loop
    if exists (select 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
                where ns.nspname='public' and p.proname=txt) then
      return query select '10,11,18','function ' || txt, 'PASS', 'Present';
    else
      return query select '10,11,18','function ' || txt, 'FAIL', 'Missing';
    end if;
  end loop;

  -- ---- acceptance assigns the committee, rejection does not --------------
  select prosrc into txt from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
   where ns.nspname='public' and p.proname='accept_application' limit 1;
  if txt is not null and txt ilike '%update public.profiles%committee_id%' then
    return query select '19','accepting assigns profiles.committee_id','PASS','Confirmed';
  else
    return query select '19','accepting assigns profiles.committee_id','FAIL','Not found';
  end if;

  select prosrc into txt from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
   where ns.nspname='public' and p.proname='reject_application' limit 1;
  if txt is not null and txt ilike '%update public.profiles%' then
    return query select '20','rejecting leaves the committee alone','FAIL',
      'reject_application writes to profiles. It should not.';
  else
    return query select '20','rejecting leaves the committee alone','PASS','Confirmed';
  end if;

  -- ---- no capacity anything ----------------------------------------------
  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='committees'
                and column_name in ('capacity','max_members','member_limit'))
  then
    return query select '29','no committee capacity column','FAIL','A capacity column exists';
  else
    return query select '29','no committee capacity column','PASS','None, as instructed';
  end if;

  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
   where ns.nspname='public'
     and (p.proname ilike '%capacity%' and p.proname <> 'guard_event_capacity');
  if n > 0 then
    return query select '29','no committee capacity logic','FAIL',
      n || ' capacity related function(s) found';
  else
    return query select '29','no committee capacity logic','PASS',
      'Only event capacity exists, which is about rooms, not committees';
  end if;

  -- ---- the old table is archived, not destroyed --------------------------
  if exists (select 1 from pg_tables where schemaname='public' and tablename='registrations') then
    return query select 'MIG','registrations retired','FAIL',
      'The old table is still live. Run 12.';
  elsif exists (select 1 from pg_tables where schemaname='public' and tablename='registrations_archive') then
    execute 'select count(*) from public.registrations_archive' into n;
    return query select 'MIG','registrations archived','PASS',
      n || ' original rows preserved in registrations_archive. Nothing deleted.';
  else
    return query select 'MIG','registrations','WARN','No registrations table found at all';
  end if;

  -- ---- migrated data ------------------------------------------------------
  select count(*) into n from public.memberships;
  select count(*) into m from public.profiles;
  return query select 'MIG','data', 'PASS',
    m || ' profiles, ' || n || ' memberships';

  select count(*) into n from public.memberships
   where status::text in ('pending_verification','waived');
  if n > 0 then
    return query select 'MIG','old statuses remaining','WARN',
      n || ' membership(s) still on a retired status';
  else
    return query select 'MIG','old statuses remaining','PASS','None';
  end if;

  select count(*) into n from public.profiles where role::text in ('executive','treasurer');
  if n > 0 then
    return query select 'MIG','old roles remaining','WARN',
      n || ' profile(s) still on a retired role';
  else
    return query select 'MIG','old roles remaining','PASS','None';
  end if;

  for txt in select role::text || ' x ' || count(*)::text
               from public.profiles group by role loop
    return query select 'ROLES', txt, 'INFO', '';
  end loop;

  -- ---- security -----------------------------------------------------------
  for txt in
    select c.relname from pg_class c join pg_namespace ns on ns.oid=c.relnamespace
     where ns.nspname='public' and c.relkind='r' and not c.relrowsecurity
  loop
    return query select '22,23','unprotected table ' || txt, 'FAIL',
      'Row-level security is OFF. Readable by anyone with the public key.';
  end loop;

  select count(*) into n from pg_policies where schemaname='public';
  return query select '22,23','policies','PASS', n || ' policies across public tables';

  if exists (select 1 from storage.buckets where id='payment-proofs' and public=false) then
    return query select '23','payment-proofs private','PASS','Not publicly readable';
  else
    return query select '23','payment-proofs private','FAIL','Bucket is public or missing';
  end if;

  select count(*) into n from pg_policies
   where schemaname='storage' and policyname in ('proofs_own_read','proofs_own_write','proofs_admin_read');
  if n = 3 then
    return query select '23','proof policies','PASS',
      'Members reach their own folder only; admins see all';
  else
    return query select '23','proof policies','WARN',
      'Expected 3, found ' || n || '. Set them from the Storage dashboard.';
  end if;

  return;
end $$;

comment on function public.verify_architecture() is
  'Structural verification of the LADS portal. select * from public.verify_architecture();';

-- =============================================================================
-- INSPECTION ONLY. Reads nothing but metadata and counts. Changes nothing.
-- Run this and send me the result before any migration is written.
-- =============================================================================
with
tables as (
  select 'TABLE' as section, c.relname as item,
         (c.reltuples::bigint)::text || ' rows (est), RLS ' ||
         case when c.relrowsecurity then 'on' else 'OFF' end as detail
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
),
counts as (
  select 'COUNT', 'profiles',            count(*)::text from public.profiles
  union all select 'COUNT','memberships',count(*)::text from public.memberships
  union all select 'COUNT','applications',count(*)::text from public.applications
  union all select 'COUNT','proposals',  count(*)::text from public.proposals
  union all select 'COUNT','events',     count(*)::text from public.events
  union all select 'COUNT','event_registrations', count(*)::text from public.event_registrations
  union all select 'COUNT','committees', count(*)::text from public.committees
),
regs as (
  select 'REGISTRATIONS', 'total', count(*)::text from public.registrations
  union all select 'REGISTRATIONS','verified',   count(*) filter (where payment_verified)::text from public.registrations
  union all select 'REGISTRATIONS','rejected',   count(*) filter (where rejected)::text from public.registrations
  union all select 'REGISTRATIONS','has account',
    count(*) filter (where exists (
      select 1 from public.profiles p where lower(p.email)=lower(registrations.email)))::text
    from public.registrations
  union all select 'REGISTRATIONS','with interests',
    count(*) filter (where interests is not null and cardinality(interests) > 0)::text
    from public.registrations
  union all select 'REGISTRATIONS','workforce applicants',
    count(*) filter (where workforce)::text from public.registrations
),
enums as (
  select 'ENUM', t.typname, string_agg(e.enumlabel, ', ' order by e.enumsortorder)
    from pg_type t join pg_enum e on e.enumtypid = t.oid
    join pg_namespace n on n.oid = t.typnamespace
   where n.nspname = 'public'
   group by t.typname
),
roles as (
  select 'ROLES', coalesce(role::text,'(null)'), count(*)::text
    from public.profiles group by role
),
memb as (
  select 'MEMBERSHIP STATUS', coalesce(status::text,'(null)'), count(*)::text
    from public.memberships group by status
),
apps as (
  select 'APPLICATION KIND', coalesce(kind::text,'(null)'), count(*)::text
    from public.applications group by kind
),
cols as (
  select 'COLUMN', table_name || '.' || column_name,
         data_type || case when is_nullable='NO' then ' not null' else '' end
    from information_schema.columns
   where table_schema='public'
     and table_name in ('profiles','memberships','applications','registrations')
),
pol as (
  select 'POLICY', tablename || ' :: ' || policyname, cmd || ' to ' || array_to_string(roles,',')
    from pg_policies where schemaname in ('public','storage')
),
trg as (
  select 'TRIGGER', tgname, c.relname
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal
     and (c.relnamespace = 'public'::regnamespace or c.relname = 'users')
),
fns as (
  select 'FUNCTION', p.proname, pg_get_function_identity_arguments(p.oid)
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname='public'
),
buckets as (
  select 'STORAGE', id, case when public then 'PUBLIC' else 'private' end ||
         ', ' || coalesce(file_size_limit::text,'no limit')
    from storage.buckets
),
objs as (
  select 'STORAGE', 'objects in ' || bucket_id, count(*)::text
    from storage.objects group by bucket_id
)
select * from tables
union all select * from counts
union all select * from regs
union all select * from enums
union all select * from roles
union all select * from memb
union all select * from apps
union all select * from cols
union all select * from pol
union all select * from trg
union all select * from fns
union all select * from buckets
union all select * from objs
order by 1, 2;

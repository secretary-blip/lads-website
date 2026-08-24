-- =============================================================================
-- LADS PORTAL, STAGE 11: NEW ENUM VALUES
-- Run this ON ITS OWN, then run 12. Safe to re-run.
--
-- Its own file for a specific reason: PostgreSQL will not let a new enum value
-- be USED by anything in the same transaction that ADDED it, and the Supabase
-- SQL Editor runs each snippet as one transaction. Putting these in the same
-- file as the migration that writes them fails with
-- "unsafe use of new value of enum type".
--
-- Nothing here removes an existing value. Removing an enum value in PostgreSQL
-- means rebuilding the type and every column that uses it, which is exactly the
-- kind of destructive operation this migration is meant to avoid. Old values
-- stay defined and simply stop being written.
-- =============================================================================

-- Roles. member and committee_head already exist and are kept:
-- committee heads review applications for their own committee without seeing
-- payment records, which is a distinction worth keeping.
alter type user_role add value if not exists 'admin';
alter type user_role add value if not exists 'super_admin';

-- Payment status. unpaid and paid already exist.
-- pending replaces pending_verification. rejected is new.
-- waived stays defined but is no longer written by anything.
alter type payment_status add value if not exists 'pending';
alter type payment_status add value if not exists 'rejected';

-- Application kinds. IDRP, IVP, exchange and other already exist and stay,
-- so historical applications keep their meaning.
alter type application_kind add value if not exists 'committee';
alter type application_kind add value if not exists 'workforce';


-- =============================================================================
-- Confirm before running 12:
--
--   select t.typname, string_agg(e.enumlabel, ', ' order by e.enumsortorder)
--     from pg_type t join pg_enum e on e.enumtypid = t.oid
--    where t.typname in ('user_role','payment_status','application_kind')
--    group by t.typname;
--
-- user_role        member, committee_head, treasurer, executive, admin, super_admin
-- payment_status   unpaid, pending_verification, paid, waived, pending, rejected
-- application_kind IDRP, IVP, exchange, other, committee, workforce
-- =============================================================================

-- =============================================================================
-- LADS PORTAL, STAGE 9: A STATUS FOR PAYMENTS THAT COULD NOT BE VERIFIED
-- Run this on its own, then run 10. Safe to re-run.
--
-- This is one line, in its own file, for a specific reason: PostgreSQL will not
-- let a new enum value be USED by anything in the same transaction that ADDED
-- it, and the Supabase SQL Editor runs each snippet as one transaction.
--
-- Put this in the same file as the code that writes 'rejected' and the whole
-- migration fails with "unsafe use of new value of enum type". Two snippets,
-- two transactions, no problem.
-- =============================================================================

alter type payment_status add value if not exists 'rejected';

-- Confirm before running 10:
--   select unnest(enum_range(null::payment_status));
-- Expect: unpaid, pending_verification, paid, waived, rejected

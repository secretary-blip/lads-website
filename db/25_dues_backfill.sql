-- ---------------------------------------------------------------------------
-- 25. Rows written before migration 20 still say 10 USD
--
-- Migration 20 moved the amount onto dues_amount() and changed the column
-- default, but it only governs rows written after it ran. Every 2026/2027
-- membership created before that still carries 10.00, and the reminder email
-- reads the amount off the row, so members are being told the wrong price.
--
-- Only rows that are not paid are touched. A paid row records what somebody
-- actually handed over, and rewriting it would restate the Treasurer's
-- history to match a price that was never charged.
-- ---------------------------------------------------------------------------

update public.memberships
   set amount_usd = public.dues_amount(academic_year)
 where status <> 'paid'::payment_status
   and amount_usd is distinct from public.dues_amount(academic_year);

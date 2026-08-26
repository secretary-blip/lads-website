# Migrations

Run in numbered order. Every file is safe to run more than once.

## On the live database, from where it is now

- [ ] `INSPECT.sql` — reads metadata only, changes nothing. Look before you leap.
- [ ] `11_new_enum_values.sql` — **on its own snippet**
- [ ] `12_architecture.sql`
- [ ] `13_policies.sql`
- [ ] `14_verify.sql`, then `select * from public.verify_architecture();`
- [ ] `15_email_hooks.sql` — paste your webhook secret in first

11 must be a separate run. PostgreSQL will not let a new enum value be *used* in
the transaction that *added* it, and the SQL Editor treats each snippet as one
transaction.

## On a brand new project

`01` through `05`, then `07`, then `09`, then `11` onwards. Files 01 to 09 build
the original schema; 11 onwards migrate it to the current architecture. It is a
longer path than a fresh install needs, but it is the path that has actually been
tested, which counts for more.

## Gaps in the numbering

`06` and `08` were removed rather than renumbered, because renumbering files
somebody has already run is how you end up running one twice.

| Gone | Replaced by | Why |
|---|---|---|
| `06_email_hooks.sql` | `15_email_hooks.sql` | Fired on `registrations`, which no longer exists |
| `08_healthcheck.sql` | `14_verify.sql` | Checked functions that 12 drops |

## What each file does

| File | Purpose |
|---|---|
| `01_schema.sql` | Original tables, roles, RLS |
| `02_dues_bridge.sql` | Connected the old public form to member accounts |
| `03_auth_update.sql` | Password accounts |
| `04_security.sql` | Closed privilege gaps found in the pre-launch audit |
| `05_join_survey.sql` | The interests survey |
| `07_policy_rebuild.sql` | First full policy rebuild |
| `09_membership_lifecycle.sql` | Membership rows created before confirmation |
| `11_new_enum_values.sql` | `admin`, `super_admin`, `pending`, `rejected`, `committee`, `workforce` |
| `12_architecture.sql` | Account / membership / committee split. Archives `registrations` |
| `13_policies.sql` | Every policy for the new roles |
| `14_verify.sql` | `verify_architecture()` |
| `15_email_hooks.sql` | Emails driven by membership status |

## Two things that are deliberate

**Nothing is dropped.** `12` renames `registrations` to `registrations_archive`.
Drop it yourself once you have checked the migration, not before.

**Old enum values stay defined.** `treasurer`, `executive`, `pending_verification`
and `waived` still exist and are simply never written. Removing an enum value
means rebuilding the type and every column using it.

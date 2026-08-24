# Architecture migration

**Nothing is dropped.** `registrations` is copied out and renamed to
`registrations_archive`. If any of this is wrong, the original rows are still
there to compare against. You drop it yourself, later, once you have checked.

---

## Before you run anything

```sql
-- db/INSPECT.sql
```

Reads metadata and counts only, changes nothing. Send me the output if anything
in it looks unexpected. Everything below is written to adapt to whatever it
finds, but a look first is cheap.

## Then, four snippets, in order

- [ ] `db/11_new_enum_values.sql` — **on its own**
- [ ] `db/12_architecture.sql`
- [ ] `db/13_policies.sql`
- [ ] `db/14_verify.sql`

11 has to be separate. PostgreSQL will not let a new enum value be *used* in the
transaction that *added* it, and the SQL Editor treats each snippet as one
transaction. Combined, the whole migration fails.

Then:

```sql
select * from public.verify_architecture();
```

---

## What changed

### The three concepts are now separate

| | What it is | What creates it |
|---|---|---|
| **Account** | `auth.users` + `profiles` | Signing up. Nothing else. |
| **Membership** | One row per profile per academic year, carrying the payment | The member, from inside the portal |
| **Committee** | `profiles.committee_id` | An admin **accepting** an application |

Signing up no longer creates a membership or an application. A person can log in
having paid nothing, which is what you asked for and is also what makes the
"create an account first" flow honest.

### Roles: four, not three

You chose to keep `committee_head`. So:

| Old | New |
|---|---|
| `executive` | `super_admin` |
| `treasurer` | `admin` |
| `committee_head` | unchanged |
| `member` | unchanged |

Committee heads sit between member and admin: they review applications to their
own committee and can read profiles to contact applicants, but **cannot read
memberships**. Nine people do not need to see who has paid.

### Membership status

`unpaid → pending → paid`, or `rejected`.

`pending_verification` rows became `pending`. `waived` rows became `paid` with
the reason written into `notes`, since the new model has no separate word for it.

The old values stay defined in the enum but nothing writes them. Removing an
enum value means rebuilding the type and every column that uses it, which is
exactly the destructive operation this migration avoids.

### What happened to the registrations data

Each column went to exactly one place. Nothing was copied to two tables, because
two copies of one fact is how they end up disagreeing.

| Old column | Went to |
|---|---|
| full_name, email, phone, university, academic_year, student_id | `profiles`, filling blanks only |
| interests, interest_details | `profiles` |
| payment_method, payment_proof_path, payment_verified, rejected, verified_by, verified_at, notes | `memberships` |
| workforce, workforce_committee, workforce_motivation | `applications`, kind `workforce` |
| committee_interest | not migrated; superseded by the interests survey |

Profile fields were filled **only where empty**. Somebody who had already edited
their own details keeps what they typed; the registration was months old and they
were not.

**Registrations with no matching account were not migrated.** There is no profile
to attach them to, and inventing one would create accounts nobody can sign into.
They stay in the archive, and the verification report tells you how many.

### Members create their own membership

A member creates their membership row and attaches proof. `guard_membership`
limits them to `unpaid` and `pending`, and closes `verified_by`, `verified_at`
and `paid_on` entirely.

This has to be a trigger, not a policy. A row-level policy controls which **rows**
you may touch, never which **columns**. "You may update your own membership"
would otherwise also mean "you may mark your own membership paid" — the same
class of bug as the three we found last week.

Admins use `approve_membership(id)` and `reject_membership(id, message)`.

### Committee applications

`accept_application(id)` sets the status, records the reviewer, and sets
`profiles.committee_id`. `reject_application(id, note)` records the decision and
**does not touch** `committee_id`.

Nobody can decide their own application, whatever role they hold.

**No capacity anything.** No column, no constraint, no trigger, no count before
accepting. `14_verify.sql` actively asserts their absence, so if someone adds one
later the verification fails and tells you.

### Payment proofs

The path is now the permission:

```
payment-proofs/<user id>/whatever.png
```

A member can read and write only inside their own folder. Admins see everything.

Files from the old anonymous form are flat names that do not match that shape, so
they remain **admin-readable only**. Nothing is lost and nothing leaks.

---

## What this breaks on the website

This is the part worth being straight about. The migration is safe; the site is
not yet updated to match it.

| File | Why |
|---|---|
| `join.html` | Writes to `registrations`, which no longer exists |
| `admin-dues.html` | Reads `registrations`, calls `approve_registration` |
| `account.html` | Uses `pending_verification` and `waived` |
| `events.html` | Unlocks on `["paid","waived"]` |
| `apply.html` | Kinds are IDRP/IVP/exchange, not committee/workforce |
| `admin-members.html` | Offers the old four roles |
| `js/portal.js` | `DUES_LABEL`, `ROLE_LABEL`, `isStaff` |
| Edge Function `notify` | Reads the registrations payload |
| `08_healthcheck.sql` | Checks functions that no longer exist |

**Do not deploy the current site against the migrated database.** Either hold the
migration until the front end is rewritten, or run it and accept that the portal
is down until it is.

Given registrations open in three weeks, my recommendation is to run
`INSPECT.sql` now, look at the output together, and then do the migration and the
front-end rewrite in one sitting rather than leaving a gap where neither half
matches the other.

---

## The behavioural checks

`verify_architecture()` covers the structural half of your list. These need a
real browser and a second account:

- A member cannot mark their own membership paid
- A member cannot see another member's membership or proof
- Submitting an application does not assign a committee
- Accepting one does
- Rejecting one does not
- A member cannot approve their own application

I will write these up as a test script once the front end matches.

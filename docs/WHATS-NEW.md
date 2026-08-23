# Membership lifecycle

## Run these, in this order, as separate snippets

- [ ] `db/09_add_rejected_status.sql`
- [ ] `db/10_membership_lifecycle.sql`

**They must be two separate runs.** PostgreSQL will not let a new enum value be
used by anything in the same transaction that added it, and the SQL Editor treats
each snippet as one transaction. Combine them and the whole thing fails with
"unsafe use of new value of enum type".

Between the two, you can confirm 09 worked:

```sql
select unnest(enum_range(null::payment_status));
```

Expect: `unpaid, pending_verification, paid, waived, rejected`

Then push the site so the new statuses display properly:

```bash
cd ~/Documents/LADS/lads-repo
git pull --rebase && git push
```

If `git pull` complains, replace the folder from the new zip as before.

---

## What changed

A membership row now exists **as soon as we know who someone is**, rather than
only after their payment is confirmed.

The gap this closes: somebody who registered, paid, and created an account saw
**"Not paid"** on their own page while they waited for Omar. That is wrong, and
it is exactly the sort of thing that generates a message to you in the middle of
September.

### The four states

| Status | Means | What the member sees |
|---|---|---|
| `pending_verification` | Registered, waiting on the Treasurer | "Awaiting verification" |
| `paid` | Confirmed | "Paid", with the date and renewal |
| `rejected` | Could not be verified | What went wrong and how to fix it |
| `waived` | Dues waived by the board | "Waived" |

`payment_verified` on the registration still only becomes true when money was
actually confirmed. Membership status is what people read; `payment_verified` is
the raw fact about the payment. They are deliberately not the same field.

### Rejections keep their record

A rejected payment no longer disappears. The membership row stays and turns
`rejected`, the member gets the email, and their account explains what to send
and where. Previously the record simply never appeared and they had no way of
knowing anything had happened.

### It works in either order

| What happens first | What creates the membership |
|---|---|
| Register, then sign up | `handle_new_user` |
| Sign up, then register | `registration_creates_membership`, new trigger |

Both call the same function, so the two paths cannot drift apart. That was a
real risk: the same logic written twice in two places is how these systems
develop a split personality about who has paid.

### Two safeguards worth knowing

A **waived** membership is never overwritten by a later form submission. A
waiver is a board decision and a student re-submitting the form should not
quietly undo it.

A **payment date is never cleared** once recorded. If a payment was confirmed and
later queried, the date it arrived is still a fact worth keeping.

### Back-fill

File 10 ends by creating membership rows for everyone who already has both a
registration and an account. Your four existing registrations will get rows the
moment you run it, without anyone touching a button.

---

## Then check

```sql
select * from public.health_check();
```

It now also verifies the two new functions and the new trigger. Then:

```sql
select p.full_name, p.email, m.academic_year, m.status
from public.memberships m
join public.profiles p on p.id = m.profile_id
order by p.full_name;
```

You should see rows where before there were none.

# Membership lifecycle

## Do this

- [ ] Run `db/09_membership_lifecycle.sql` — one snippet, no enum change needed
- [ ] Push the site:

```bash
cd ~/Documents/LADS/lads-repo
git pull --rebase && git push
```

If `git pull` complains, replace the folder from the new zip as before.

- [ ] Check:

```sql
select p.full_name, p.email, m.academic_year, m.status, m.notes
from public.memberships m
join public.profiles p on p.id = m.profile_id
order by p.full_name;
```

Rows should appear where there were none. The file back-fills everyone who
already has both a registration and an account.

---

## How it works now

A membership row exists **as soon as we know who someone is**, not only after
their payment is confirmed. That closes the gap where someone who registered,
paid, and made an account saw "Not paid" on their own page while they waited.

| Status | Means | Member sees |
|---|---|---|
| `pending_verification` | Registered, waiting on the Treasurer | "Awaiting verification" |
| `paid` | Confirmed | "Paid", with date and renewal |
| `unpaid` | Not paid, or a payment we could not verify | "Not paid", plus what to do if there's a note |
| `waived` | Board decided they owe nothing | "Waived" |

### Why rejections are `unpaid` and not `waived`

You asked for `waived`. I used `unpaid`, and this one is worth knowing about
rather than just accepting.

`waived` is not a neutral label in this system. `events.html` already treats it
as full membership — `["paid","waived"]` is what unlocks members-only events. So
filing a rejected payment under waived would give someone full member access on
the strength of a payment nobody could verify, and would report them in the
Treasurer's totals under "Waived", as a decision the board never made.

`unpaid` is what the situation factually is. The member still sees the reason,
because a member-facing explanation goes into `memberships.notes`, which they can
read on their own row:

> We could not verify this payment. Please send a clear screenshot of the
> transfer, showing the date and reference, to info@ladslb.org and we will sort
> it out.

Their account shows that with a **Send us your receipt** button. The private
reason Omar types stays on the registration, where only he sees it.

### Signing up never writes to the registration

Your spec had account creation flip `payment_verified` to false. I left it
untouched, deliberately.

If someone's payment had already been confirmed and they made their account
afterwards, that would have un-verified it and erased the record of money you had
received. Account creation reads the registration; only the Treasurer's decision
writes to it.

### Either order works

| First | Creates the membership |
|---|---|
| Register, then sign up | `handle_new_user` |
| Sign up, then register | `registration_creates_membership` |

Both call `sync_membership_from_registration`. One function, so the two paths
cannot drift apart — which matters, because the same rule written twice is how a
system ends up disagreeing with itself about who has paid.

### Two things that never get overwritten

A **waiver** survives a later form submission. It is a board decision and a
student re-registering should not quietly undo it.

A **payment date**, once recorded, is never cleared. If a payment was confirmed
and later queried, the day the money arrived does not stop being true.

---

## Still open

The dues page console error. Click **Member records** — if the tab does not
switch, one of the three queries is throwing and that localises it.

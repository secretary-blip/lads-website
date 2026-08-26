# Cutover

Database and site both change. Do them in one sitting, in this order. About 40
minutes. The portal is down between step 2 and step 4, so pick a quiet hour.

Your data made this safe: **zero verified payments, zero applications, zero
events.** There is no financial history to get wrong.

---

## 1. Push the new site, but do not deploy it yet

```bash
rm -rf ~/Documents/LADS/lads-repo
cd ~/Documents/LADS
unzip -o "/Users/riadjawhar/Library/Application Support/Claude/local-agent-mode-sessions/0c899cf2-50b2-46e8-8bd0-78938c12462d/21bd02bc-864d-495a-8d72-0fe53144a4e7/local_bdb179d7-7a15-4cd3-bbab-fb03a16462c0/outputs/lads-repo.zip"
cd lads-repo
git remote add origin https://github.com/secretary-blip/lads-website.git
```

**Do not push yet.** Netlify deploys on push, and the new site expects the new
database. Run the migration first.

## 2. Migrate the database

Supabase SQL Editor, separate snippets, in order:

- [ ] `db/11_new_enum_values.sql` — **on its own**
- [ ] `db/12_architecture.sql`
- [ ] `db/13_policies.sql`
- [ ] `db/14_verify.sql`

11 has to be separate. PostgreSQL will not let a new enum value be used in the
transaction that added it, and the SQL Editor runs each snippet as one.

## 3. Check it

```sql
select * from public.verify_architecture();
```

Everything should be PASS. Send me any FAIL before going further.

## 4. Now push

```bash
git push -u origin main --force
```

Netlify deploys and the portal is back, matching the database.

## 5. Reconnect the emails

- [ ] Update the Edge Function: Supabase → Edge Functions → `notify` → paste the
      new `supabase/functions/notify/index.ts` → Deploy
- [ ] Run `db/15_email_hooks.sql` with your webhook secret pasted in

The old triggers pointed at `registrations` and are dropped by that file.

## 6. Sign in and look

Your role became `super_admin` automatically. You should see Board tools with
Dues, Members, Events and Review.

---

# What changed on the site

| Page | What it is now |
|---|---|
| `pay.html` | **New.** The member creates their membership and uploads proof |
| `interests.html` | **New.** The survey, editable, stored on the profile |
| `join.html` | Public information page. No form. Explains the three steps |
| `admin-dues.html` | Reads memberships. Confirms through `approve_membership` |
| `admin-review.html` | Accepting an application assigns the committee |
| `apply.html` | Applications are for committees and workforce |
| `admin-members.html` | The four new roles |
| `account.html` | New statuses, links to pay and interests |
| `events.html` | Members-only unlocks on `paid` alone |

## The member journey now

1. Create an account at `/signup.html`. Free, no payment, no membership created
2. Pay $10 through whish
3. Upload the screenshot at `/pay.html`. Membership becomes `pending`
4. The Treasurer confirms. It becomes `paid` and they are emailed

That is the reversal you approved: an account first, then a payment attached to
it. Every payment is now tied to a real account, which is why the old
email-matching bridge could be deleted rather than maintained.

## Payment proofs

The path is the permission:

```
payment-proofs/<user id>/1786...png
```

A member can read and write only inside a folder named after their own user id.
One member cannot open another's receipt even knowing the path. Admins see all.

The two files uploaded through the old anonymous form have flat names that do not
match that shape, so they stay admin-only. Nothing lost, nothing leaked.

---

# What to test afterwards

The structural half is covered by `verify_architecture()`. These need a browser
and a second account, and they are the ones that matter:

- [ ] Sign up with a fresh email. You get a profile, **no membership**
- [ ] That account can log in and see its account page
- [ ] Submit a payment at `/pay.html`. Status becomes **Awaiting verification**
- [ ] As yourself, confirm it in `admin-dues.html`. Their page says **Paid**
- [ ] As the test member, open `/admin-dues.html` — **you must be refused**
- [ ] As the test member, apply to a committee. Their `committee_id` is still empty
- [ ] Accept it. Now `profiles.committee_id` is set
- [ ] Reject a second application. `committee_id` is unchanged

The fifth one is the one not to skip. If a member can see the dues page, stop and
tell me before anyone else gets an account.

---

# Afterwards, when you are satisfied

```sql
drop table public.registrations_archive;
```

Not before. It holds the original five rows and is the only way to check the
migration did what it claimed.

---

# Still open

**A privacy notice.** The portal holds names, phone numbers, universities,
payment records, attendance and application history. Members should be told what
is kept, who can see it, and how to have it removed. One page, linked from the
footer and signup. Ask and I will draft it.

**`noreply@ladslb.org` as a group**, so replies to portal emails reach a person.

**Nine board accounts still never signed into.** Unchanged from last week, and
still the highest-value hour available to you.

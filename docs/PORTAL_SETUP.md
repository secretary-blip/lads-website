# Portal setup, stage 1

The login and account pages are built. They will not work until the four
Supabase settings below are configured. Roughly 15 minutes.

---

## 1. Run the schema (5 min)

Supabase → SQL Editor → New query → paste all of `portal_schema.sql` → Run.

Creates: profiles, memberships, events, event_registrations, applications,
proposals, committees, all row-level security policies, and the trigger that
creates a profile automatically on first login.

Safe to re-run.

---

## 2. Set the redirect URLs (2 min)

Supabase → **Authentication → URL Configuration**

- **Site URL:** `https://ladslb.org`
- **Redirect URLs**, add all of these:
  ```
  https://ladslb.org/auth-callback.html
  https://ladslb.org/**
  http://localhost:*/**
  ```

Without this, sign-in links will bounce.

---

## 3. Turn on Google sign-in — OPTIONAL, skip for now

**Recommendation: leave this until after everything else works.** Magic-link
sign-in is fully functional without it. The Google button will simply show an
error until configured, and it can be enabled later without any code changes.

When you do want it:

Supabase → Authentication → **Sign In / Providers** (in the CONFIGURATION section
of the sidebar, above Passkeys). Supabase renamed this from "Providers".

**Not "OAuth Apps"** — that page is for making Supabase act as an identity
provider for other applications, which is the opposite of what we want.

Scroll to Google, enable it. It asks for a Client ID and Secret, which come from
console.cloud.google.com → APIs & Services → Credentials → Create OAuth client ID
→ Web application. In the Google console, set the **Authorised redirect URI** to
the callback URL Supabase displays on the provider page, which looks like:
`https://fazswkdinsbqymgwlebr.supabase.co/auth/v1/callback`

Note: Supabase moves things around in their dashboard fairly often. If a menu
name here does not match what you see, look for something similar in the same
section rather than assuming the step is missing.

---

## 4. Fix email delivery (3 min) — important

Supabase's built-in email sender is rate-limited to a handful per hour and
frequently lands in spam. For real members you need proper SMTP.

Supabase → **Project Settings → Authentication → SMTP Settings** → enable, then:

| Field | Value |
|---|---|
| Host | smtp.gmail.com |
| Port | 587 |
| Username | info@ladslb.org (or your Workspace address) |
| Password | a Google App Password, not your normal password |
| Sender email | info@ladslb.org |
| Sender name | LADS |

Create the App Password at myaccount.google.com → Security → 2-Step
Verification → App passwords. This requires 2FA on the account, which you have.

---

## 5. Make yourself executive (1 min)

Sign in once at `https://ladslb.org/login.html` so your profile is created. Then
in the SQL Editor:

```sql
update public.profiles
set role = 'executive'
where email = 'YOUR_EMAIL_HERE';
```

Do the same for the President. Recommend exactly two executives.

To set the Treasurer and committee heads later:

```sql
-- treasurer
update public.profiles set role = 'treasurer' where email = 'omar@example.com';

-- a committee head, must also set which committee
update public.profiles
set role = 'committee_head', committee_id = 'fundraising'
where email = 'head@example.com';
```

Valid committee ids: `scientific`, `fundraising`, `exchange`, `training`,
`public_health`, `voluntary`, `activities`, `editorial`, `social_media`.

---

## Testing it

1. Open `https://ladslb.org/login.html`
2. Enter your email, click the link in your inbox
3. You should land on `account.html` showing your name and dues status
4. Edit your details, save, reload, confirm they persisted
5. Sign out, then try Google sign-in if you enabled it

**Test that security works:** sign in with a second email, and confirm that
account cannot see the first account's record. The database should refuse
regardless of what the page does.

---

## What members will see

| Situation | Account page shows |
|---|---|
| Dues paid | "Paid for 2026/2027", payment date, renewal date |
| Awaiting verification | "Awaiting verification", explains the Treasurer is checking |
| Not paid | "Not paid", amount, and a link to the Join page |
| No record yet | Empty history with an explanation |

Board members additionally see a "Board tools" section linking to the admin
pages, which are the next stage.

---

---

# Portal setup, stage 2: the Treasurer's screen

## 6. Run the dues bridge (2 min)

SQL Editor → new snippet → paste all of `portal_dues_bridge.sql` → Run.
Safe to re-run. Expect "Success. No rows returned."

**Why this file exists.** The public Join form writes to `registrations`. The
portal reads `memberships`. Nothing connected the two, so a payment could be
verified and the member would still see "Not paid" forever. This file joins
them, in whichever order things happen:

| What happens first | What the file does |
|---|---|
| They register, then make an account later | Membership is created the moment they first sign in |
| They have an account, then register | Membership is created when you confirm the payment |
| They registered last year, account today | Membership is filed under the correct past year |

It also gives the Treasurer read access to registrations and to the payment
screenshots, which nobody had before.

**If you see a notice about the storage policy**, the file could not create it
because of Supabase permissions. Everything else still ran. Add it by hand:
Storage → payment-proofs → Policies → New policy → for `SELECT`, target role
`authenticated`, using expression:

```sql
bucket_id = 'payment-proofs' and public.handles_money()
```

Without it the Treasurer sees "Could not load the screenshot" when viewing proofs.

**Check it worked:**

```sql
select * from public.dues_summary();
```

## 7. Use it

`https://ladslb.org/admin-dues.html`, also linked from Board tools on your
account page. Visible to the Treasurer and the Executive Committee only.

Three tabs:

- **Awaiting verification** — every Join form submission not yet dealt with.
  Full details, the payment screenshot, and two buttons: Confirm payment, or
  Cannot verify. Confirming writes the membership record and the member sees it
  immediately.
- **Member records** — everyone's dues for the current year, searchable, with
  manual Mark paid, Waive dues, and an undo.
- **Processed** — everything already handled, kept as a financial record.

Nothing is ever deleted. Rejections are flagged with a private reason and stay
on file.

## A note on the membership year

Two different questions, two different rules, deliberately:

- **Which year are we in?** September to August. Used for display.
- **Which year is this payment for?** July onward counts towards the year
  starting that September, because members pay ahead over the summer. Someone
  paying in July 2026 is paying for 2026/2027.

If you ever change one, change the other: `duesYear()` in `js/portal.js` and
`public.dues_year_of()` in the database must agree.

---

## Still to build

- `admin-members.html`, Executive assigns roles
- `admin-events.html`, staff create events
- `admin-review.html`, committee heads review applications
- `events.html`, `apply.html`, `propose.html`, member-facing

The account page already links to these; the links will 404 until built.

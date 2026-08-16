# LADS Workspace rollout, version 2

Updated against the accounts that actually exist. You used IADS officer titles
rather than the generic names I first suggested, which is the better call:
`neo@`, `npo@` and `nro@` are what IADS itself writes to, and a partner emailing
the National Exchange Officer should not have to guess that we call it something
else.

---

## 1. What exists now

Fourteen confirmed from your Admin console, in the order they appeared.

| Address | Held by | Signed in? |
|---|---|---|
| `president@ladslb.org` | Rasha Badih | Yes |
| `vicepresident@ladslb.org` | Raneem Al Sheikh Ali | Yes |
| `secretary@ladslb.org` | Riad Jawhar | Yes |
| `treasurer@ladslb.org` | Omar Al Batal | **No** |
| `delegate@ladslb.org` | Mahmoud Mahmoud | **No** |
| `neo@ladslb.org` | Ali Khalife | Yes |
| `npo@ladslb.org` | Maysa Abou El Saad | **No** |
| `nro@ladslb.org` | Nour El Jamal | **No** |
| `training@ladslb.org` | Aya Omais | **No** |
| `editorial@ladslb.org` | Aya El Ghandour | **No** |
| `voluntary@ladslb.org` | Fouad El Mawlawy | Yes |
| `activities@ladslb.org` | Majida Jabr | **No** |
| `social@ladslb.org` | Sara Saddik | **No** |
| `info@ladslb.org` | LADS Inquiries | Yes |

**Nine of fourteen have never signed in.** That is the normal shape of a rollout
at this stage and it is also the thing that quietly kills it. An account nobody
opens is an account that misses the first sponsor email, and by week three people
have gone back to their personal Gmail and the whole exercise was for nothing.
Chase the nine. It is the highest-value hour in this document.

## 2. What is missing

Your screenshot was cut off at the top and bottom, so confirm these exist:

- [ ] **`scientific@ladslb.org`** for Tia Majed. `nro@` covers research, but the
      Scientific Committee is a separate thing on your own website.
- [ ] **`fundraising@ladslb.org`** for Alaa Al Kork
- [ ] **Kristina Hajj Geagea**, second head of Fundraising. Not a second account:
      delegate `fundraising@` to her, see below.

Also worth deciding: `npo@` is the National Public health Officer, which on the
website is the Public Health Committee. Same person, two names. Pick one for
public use so members are not looking for a committee that appears to have
vanished.

## 3. Two accounts still to create

### `admin@ladslb.org`, break-glass super admin

Belongs to nobody. Exists so the organisation always has a way in that does not
depend on a particular student still being enrolled and reachable. You lost weeks
to a lockout in July. This is the specific fix for that.

- Password in a password manager shared between President and General Secretary
- Two-step verification on
- Recovery phone and recovery email pointing at two different people
- Never used for daily mail

### `noreply@ladslb.org`

The portal sends sign-in and password-reset emails from this address through
Resend. It does not exist yet, which means every member who replies to one, and
they will, is writing into nothing.

Make it a **group**, not a user. Costs no licence. Members: `secretary@`, `info@`.

## 4. Groups to create

Free, no licence. Admin console → Directory → Groups.

| Address | Members | Who can post |
|---|---|---|
| `board@ladslb.org` | All 15 | Members only |
| `exec@ladslb.org` | president, vicepresident, secretary, treasurer, delegate | Members only |
| `heads@ladslb.org` | The 9 committee heads | Members only |
| `noreply@ladslb.org` | secretary, info | Anyone |

`info@` already exists as a user account. Consider converting it to a group so it
is never one person's inbox, and so it survives without consuming a licence.

## 5. Aliases

Free and instant. Admin console → the user → Alternate email addresses.

| Alias | Delivers to | Why |
|---|---|---|
| `exchange@ladslb.org` | `neo@` | What students will guess |
| `publichealth@ladslb.org` | `npo@` | Matches the website |
| `research@ladslb.org` | `nro@` | What students will guess |
| `iads@ladslb.org` | `delegate@` | What IADS will guess |
| `sponsorship@ladslb.org` | `fundraising@` | What companies write to |
| `gazette@ladslb.org` | `editorial@` | Named publication |
| `media@ladslb.org` | `social@` | Press enquiries |

The pattern: keep the IADS officer title as the real address, and add the plain
English word as an alias. Nobody has to know which one to use.

## 6. Fundraising has two heads and one mailbox

Do not share a password. Sign in as `fundraising@` once, then Gmail → Settings →
Accounts → *Grant access to your account* → add Kristina.

She reads and sends from it under her own login, every action is attributable,
and access is removed with one click at handover.

---

# This week

## Monday, finish the accounts

- [ ] Create `admin@ladslb.org`, make it super admin, 2FA on, recovery set
- [ ] Store its password in a password manager shared with Rasha, not in a chat
- [ ] Confirm or create `scientific@` and `fundraising@`
- [ ] Delegate `fundraising@` to Kristina
- [ ] Message the nine people who have not signed in, individually

## Tuesday, groups and aliases

- [ ] Create `board@`, `exec@`, `heads@`, `noreply@`
- [ ] Add all seven aliases
- [ ] Test: send from a personal address to `info@`, `board@` and `noreply@`, confirm all three arrive
- [ ] Send the signature template to `board@`

## Wednesday, the parts that outlive you

- [ ] Create a **Shared Drive** called LADS, one folder per committee
- [ ] Move existing Drive content into it. Files in a personal Drive are deleted
      with the account, which is the same continuity problem as email but harder
      to notice until it happens
- [ ] Shared calendar for LADS events, shared with `board@`
- [ ] Admin → Security → enforce 2-step verification, two-week grace period
- [ ] Turn `info@` into a Collaborative Inbox so two people cannot answer the
      same enquiry twice

## Thursday, the portal

Four SQL files, in this order, each as a new snippet in the Supabase SQL Editor:

- [ ] `portal_schema.sql` (already run)
- [ ] `portal_dues_bridge.sql`
- [ ] `portal_auth_update.sql`
- [ ] `portal_security.sql`

Then:

- [ ] Authentication → Sign In / Providers → Email: **Confirm email ON**, minimum password length 8
- [ ] Authentication → URL Configuration → add `https://ladslb.org/reset-password.html` to Redirect URLs
- [ ] Deploy the new site folder to Netlify
- [ ] Set roles: Rasha executive, Omar treasurer, and each committee head

## Friday, test it like a stranger

- [ ] Create an account from scratch at `/signup.html` with an address you control
- [ ] Confirm the email arrives, and that the link works
- [ ] Submit the Join form as that person with a screenshot
- [ ] Have Omar confirm the payment in `admin-dues.html`
- [ ] Check the member's account now says Paid
- [ ] Create a draft event, publish it, register, cancel, register again
- [ ] Submit an application and a project idea; approve one, decline the other
- [ ] **The one that matters:** sign in as a second member and confirm you cannot
      see the first member's record. If you can, stop and tell me before anyone
      else gets an account.

## Weekend, make it survivable

- [ ] Write down every account, who holds it, and where the password lives
- [ ] Confirm two people can reach every critical system: Workspace, Namecheap,
      Netlify, Supabase, Resend
- [ ] Reply to Google confirming the approval

---

## Still open, and worth deciding before members sign up

**A privacy notice.** The portal now stores names, phone numbers, universities,
payment records, event attendance and application history. Members should be told
what is held, who can see it, and how to ask for it to be deleted. One short page,
linked from the footer and the signup form. Say the word and I will draft it.

**Who can see member phone numbers.** As it stands, all nine committee heads can
read every member's contact details. That is a deliberate choice and a defensible
one, but it should be the board's choice rather than a default nobody noticed. It
is a one-line change if you would rather restrict it.

**How long records are kept.** My suggestion: archived, never deleted, so
historical membership numbers stay accurate for grant applications and IADS
reporting. Minute the decision either way.

---

## The rule that matters most

**Never fewer than two people with access to anything.** Not Workspace, not the
domain, not Netlify, not Supabase, not Resend.

Everything that went wrong this summer traced back to a single point of failure:
one domain nobody had registered, one admin account nobody else could open. Every
account above should have a second person who can reach it, written down where the
next board can find it.

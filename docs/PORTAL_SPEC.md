# LADS Member Portal, Specification

Purpose: give every LADS member a permanent, self-owned record, and give the
board a shared tool. Built so it outlives any single board.

---

## Decisions taken

| Decision | Choice |
|---|---|
| Sign-in | Magic link (email) **and** Google, member picks |
| Roles | member, committee_head, treasurer, executive |
| Data store | Supabase (Postgres + Auth + Storage), free tier |
| Hosting | Netlify, deploying from GitHub |

### Why magic link and Google, no passwords
Nobody forgets a magic link. There are no resets for a board member to handle,
no weak passwords, no credential leaks. Google is there for the majority who
have Gmail and want one tap.

### Why four roles
Splitting treasurer from executive means payment records and screenshots are
visible to the two people who need them, not to all nine committee heads.
Committee heads see applications to **their own committee only**.

---

## Who can see what

| | Own profile | All profiles | Own dues | All dues | Applications | Events |
|---|---|---|---|---|---|---|
| **member** | read/edit | no | read | no | own only | published |
| **committee_head** | read/edit | read | read | no | own committee | all + create |
| **treasurer** | read/edit | read | read | read/edit | own only | all + create |
| **executive** | read/edit | read/edit | read | read | all | all + create |

Enforced in the database itself through Row Level Security, not in the website
code. That matters: even if the website had a bug, the database still refuses.

---

## Data model

**profiles** — one per person, created automatically on first login.
Holds name, contact, university, year, role.

**memberships** — one row per member *per academic year*. This is the
continuity record. A member who joins in 2026 still has a visible history in
2031, across five different boards. Holds status, amount, payment method,
proof, who verified it and when.

**events** + **event_registrations** — board publishes, members register,
attendance can be marked afterwards.

**applications** — IDRP, IVP, exchange. Structured, with status tracking from
submitted through to a decision, and a reviewer note.

**proposals** — members propose project ideas; committee heads review.

**committees** — reference list, used to route applications and proposals.

Nothing is hard-deleted. Records are archived.

---

## Pages to build

### Public (already live)
Home, About, Committees, Projects, Resources, News, Join

### Member portal (new)
| Page | Purpose |
|---|---|
| `/login` | Enter email for magic link, or continue with Google |
| `/auth/callback` | Handles the redirect after sign-in |
| `/account` | Dashboard: dues status, next renewal, my events, my applications |
| `/account/profile` | Edit own contact details |
| `/events` | Upcoming events, register |
| `/apply` | Submit IDRP / IVP / exchange application |
| `/propose` | Submit a project idea |

### Board tools
| Page | Who |
|---|---|
| `/admin/members` | Executive: view members, assign roles |
| `/admin/dues` | Treasurer: verify payments, mark paid |
| `/admin/events` | Staff: create and publish events |
| `/admin/review` | Committee heads: applications and proposals for their committee |

---

## Build order

Each stage is usable on its own, so if time runs short you still ship something whole.

1. **Schema + auth** — login works, profile auto-created, dashboard shows dues status
2. **Treasurer dues screen** — payments verified in the portal instead of the raw table editor
3. **Events** — publish and register
4. **Applications and proposals** — with committee-head review
5. **Member and role admin** — executive assigns roles

---

## Handover, built in from the start

The continuity risk is real: this must not become something only one person
understands.

- **GitHub from day one.** Every change is versioned and readable. A future
  board can hand the repository to anyone.
- **Schema is one documented SQL file.** The whole database can be rebuilt from it.
- **Permissions live in the database**, in one place, commented, auditable.
- **No build step, no framework.** Plain HTML, CSS and JavaScript. Anyone who
  knows basic web development can maintain it. Nothing to keep updated.
- **A written runbook** (HANDOVER.md) covering accounts, deploys and checks.
- **Two people with access minimum.** Never one.

---

## Things that need a decision before members use it

1. **Privacy notice.** The portal stores names, phone numbers, universities and
   payment records. Members should be told what is held, who can see it, and how
   to request deletion. One short page, linked from the footer and the signup form.

2. **Who is executive.** Recommend exactly two: the General Secretary and the
   President. More than that and role control gets loose.

3. **Data retention.** How long are records kept after someone graduates?
   Suggest: archived, not deleted, so historical membership counts stay accurate.

4. **Email sending.** Supabase's built-in email is rate-limited and lands in
   spam often. For reliable magic links, connect a proper SMTP sender. Google
   Workspace SMTP works and costs nothing given the nonprofit account.

---

## Honest assessment of timeline

Stages 1 and 2 are realistic before September. Stages 3 to 5 are realistic
during the autumn term if someone stays on it.

Trying to ship all five before September, alongside launching the public site
and the whish rollout, is where this would break. Better to have accounts and
dues working properly in September than four half-finished features.

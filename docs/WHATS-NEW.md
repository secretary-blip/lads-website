# Getting to a clean state

Four steps. Then you run one command and the database tells you what is working,
instead of you guessing.

---

## 1. Replace your local copy and push

Your folder is several commits behind, which is why the dues page was blank.

```bash
rm -rf ~/Documents/LADS/lads-repo
cd ~/Documents/LADS
unzip -o ~/Downloads/lads-repo.zip
cd lads-repo
git remote add origin https://github.com/secretary-blip/lads-website.git
git push -u origin main --force
```

Adjust the unzip path to wherever the zip actually downloaded. The force push is
safe: this copy contains every commit GitHub already has, plus six new ones.

Netlify deploys within a minute.

---

## 2. Run three migrations

Supabase → SQL Editor → new snippet for each, in this order.

- [ ] `db/05_join_survey.sql` — the interests survey columns
- [ ] `db/07_policy_rebuild.sql` — every security policy, rebuilt
- [ ] `db/08_healthcheck.sql` — installs the health check

All three are safe to run more than once.

## 3. Ask the database how it is

```sql
select * from public.health_check();
```

Around forty rows, each PASS, FAIL or WARN with a plain explanation. This is the
answer to "I can't tell if anything is working".

Expect some WARNs until the email setup is finished. **Any FAIL needs fixing
before September.** Send me a screenshot and I will tell you which file to run.

Run it again any time you change something, and once more in September before
you tell members to sign up.

## 4. Finish the emails

Follow `docs/EMAIL_SETUP.md`. The health check will confirm when it is done,
including whether the webhook secret is still the placeholder, which is the
mistake that produces silent 401s and no emails at all.

---

# What changed, and why

## Every security policy was rebuilt

Three policies had to be corrected while you were setting up, and all three
failed the same way: each was written for the situation that existed when it was
written, and quietly stopped being right when the situation changed.

| Policy | Written for | What broke |
|---|---|---|
| `anyone can register` | nobody had accounts | signed-in members could not use the Join form |
| `guard_role_changes` | stopping self-promotion | also blocked the SQL Editor, so a bad role could not be fixed anywhere |
| `committees_read` | signed-in users | the Join form's committee list was empty for people without accounts |

Patching a fourth would have been the wrong answer. `07_policy_rebuild.sql` now
states the entire permission model in one file, checked against every real flow:
anonymous visitor, member, committee head, treasurer, executive. It also drops
every existing policy by name first, because two policies on one table are OR'd
together and an old permissive one silently defeats a new strict one with no
warning.

Read that one file and you know exactly who can see what.

## A health check

`select * from public.health_check();` reports on:

- Row-level security enabled on all eight tables, and **any table that is not
  protected**, including ones added later that nobody remembered to lock down
- Tables with security on but no policies, which locks everyone out silently
- All nineteen required functions
- All six guard triggers
- The email triggers, and whether the webhook secret is still the placeholder
- Whether the payment screenshot bucket is private
- Whether there are at least two executives, and whether any committee head is
  missing a committee, which would leave their review page permanently empty

It reports structure only, never member data, so it is safe to screenshot when
asking for help.

## Two small additions

Executives can now edit committee descriptions through the database rather than
only via SQL, so the deputy head rundown on the Join page can be corrected
without anybody touching a migration.

`tools/check_sql.py` parses every migration against the real PostgreSQL grammar
before you run it. All eight currently pass.

---

## After September

Two things I would still do, but not now:

**A privacy notice.** The portal holds names, phone numbers, universities,
payment records, attendance and application history. Members should be told what
is kept, who sees it, and how to have it removed. One page, linked from the
footer and the signup form.

**Decide who can see phone numbers.** As it stands all nine committee heads can
read every member's contact details. Defensible, since heads need to reach the
people who volunteered. But it should be a board decision that was made, not a
default nobody noticed. One line to change if you want it tighter.

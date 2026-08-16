# START HERE

Everything needed to get the LADS portal live, in order. About 75 minutes.

You have two files in this folder and nothing else. `lads-repo.zip` is the whole
project. This is the only guide.

**Do the parts in order.** Each one depends on the one before it. If you stop
halfway, stop after a numbered part, not in the middle of one.

**Read this first, it will save you ten minutes of confusion:**
Your existing account, `ladsvicepresident@gmail.com`, was created with a sign-in
link and therefore has **no password**. The portal now uses passwords. You will
not be able to sign in with it until Part 5, where you set one. This is expected.
Nothing is broken.

---

# Part 1, the database (15 min)

Unzip `lads-repo.zip`. Inside is a `db` folder with four files. The first is
already done. You are running the other three.

Go to **supabase.com** → your LADS project → **SQL Editor**.

For each file: click **New snippet**, open the file in a text editor, copy
everything, paste, click **Run**. Expect *Success. No rows returned.*

- [ ] `db/02_dues_bridge.sql`
- [ ] `db/03_auth_update.sql`
- [ ] `db/04_security.sql`

**Run them in that order.** Each builds on the last. Running 04 before 02 will
fail with a complaint about a missing function, which is the file doing its job.

### If you see a yellow NOTICE about a storage policy

Only in file 02. It means Supabase would not let the SQL Editor create one
policy. Everything else ran. Fix it by hand:

Storage → **payment-proofs** → Policies → New policy → *For full customization*

- Policy name: `staff can read payment proofs`
- Allowed operation: **SELECT**
- Target roles: **authenticated**
- USING expression:

```sql
bucket_id = 'payment-proofs' and public.handles_money()
```

Without this the Treasurer sees "Could not load the screenshot" when reviewing
payments. Everything else still works.

### Check it worked

New snippet, run this:

```sql
select * from public.dues_summary();
```

A single row of zeros is a pass. An error means something above did not run.

---

# Part 2, Supabase settings (10 min)

These are not in the SQL. The portal will not work without them.

### 2a. Turn on passwords and email confirmation

**Authentication → Sign In / Providers → Email**

- [ ] Enable email provider: **ON**
- [ ] Confirm email: **ON**
- [ ] Minimum password length: **8**
- [ ] Save

*Confirm email is the important one.* Without it, anyone can create an account
using another student's address, and the Treasurer has no way to tell which
registration is real.

### 2b. Redirect URLs

**Authentication → URL Configuration**

Site URL: `https://ladslb.org`

Redirect URLs, all four:

```
https://ladslb.org/auth-callback.html
https://ladslb.org/reset-password.html
https://ladslb.org/**
http://localhost:*/**
```

- [ ] All four added and saved

**`reset-password.html` is the one people forget.** Leave it out and password
resets silently do nothing. Members cannot recover their accounts and you will
have no error message to look at.

### 2c. Confirm email is still sending

**Project Settings → Authentication → SMTP Settings**

- [ ] Host is `smtp.resend.com`, username is the word `resend`, sender is
      `noreply@ladslb.org`, and the toggle is on

You set this up already. Just confirm it did not get switched off.

---

# Part 3, GitHub (20 min)

Skippable tonight if you are running out of energy. Jump to Part 4 and deploy the
old way. But do it this week: right now the only complete copy of this website is
on your laptop.

### 3a. Create the repository

github.com → **New repository**

- [ ] Create a **LADS organisation** first if you can, rather than using your
      personal account. Your personal account leaves when you graduate. Same
      reasoning as role-based email.
- [ ] Name: `lads-website`
- [ ] **Private**
- [ ] Do **not** tick "Add a README", the project already has one

### 3b. Push

Open Terminal, `cd` into the unzipped `lads-repo` folder, then:

```bash
git remote add origin https://github.com/YOUR-ORG/lads-website.git
git push -u origin main
```

Git history and the first commit are already in there. You are only pointing it
at GitHub.

If it asks for a password, GitHub wants a **personal access token**, not your
account password: github.com → Settings → Developer settings → Personal access
tokens → Fine-grained → Contents: Read and write.

- [ ] Pushed, and the files are visible on github.com

---

# Part 4, deploy (10 min)

## Option A, connect Netlify to GitHub (do this if you did Part 3)

Netlify → your ladslb.org site → **Site configuration** → **Build & deploy** →
**Link repository** → GitHub → `lads-website`

| Field | Value |
|---|---|
| Branch | `main` |
| Build command | leave empty |
| **Publish directory** | **`site`** |

- [ ] Publish directory is `site`, not blank, not `/`

**This is the single most important setting on this page.** The repository
contains your database files and internal documents alongside the website. Only
`site` should ever be public.

## Option B, drag and drop (if you skipped GitHub)

Drag the **`site`** folder from inside `lads-repo` onto Netlify's deploy area.

**Drag `site`, not `lads-repo`.** Dragging the outer folder publishes your
database schema and every security policy to the open internet.

## Either way

- [ ] Open `https://ladslb.org/signup.html`. If you see the signup form, deployed.

### One thing to check afterwards

In the version you deployed before tonight, the SQL files sat next to
`index.html`, which means **ladslb.org/portal_schema.sql** currently downloads
your entire database structure. Deploying tonight removes it.

- [ ] Visit `https://ladslb.org/portal_schema.sql` after deploying. You want a
      404 page. If it downloads a file, your publish directory is wrong, go back.

---

# Part 5, get yourself back in (5 min)

Your old account has no password.

- [ ] Go to `https://ladslb.org/forgot-password.html`
- [ ] Enter `ladsvicepresident@gmail.com`
- [ ] Open the email, click the link, set a password
- [ ] You land on your account page

Then make yourself executive. Supabase → SQL Editor → New snippet:

```sql
update public.profiles
set role = 'executive'
where email = 'ladsvicepresident@gmail.com';
```

- [ ] Ran it, then reloaded `account.html` and can see **Board tools**

If Board tools does not appear, the update matched no rows. Check the email is
exactly the one you signed in with.

---

# Part 6, give the board access (10 min)

Only Omar is needed tonight. The rest can wait.

Each person must **create their own account first** at
`https://ladslb.org/signup.html`, then you set their role.

- [ ] Ask Omar to sign up, then run:

```sql
update public.profiles
set role = 'treasurer'
where email = 'HIS_EMAIL_HERE';
```

Everyone else, once they have signed up, is easier from
`https://ladslb.org/admin-members.html` — search, pick a role, save. No SQL.

Committee heads need a committee as well as a role, and the admin page handles
that for you.

---

# Part 7, test it (10 min)

Do not skip this. It is how you find out tonight rather than in September.

- [ ] Create a brand new account at `/signup.html` with an email you control
- [ ] The confirmation email arrives, and the link works
- [ ] You land on the account page and it says **Not paid** for 2026/2027
- [ ] Change the password from the account page
- [ ] Sign out, sign back in with the new password
- [ ] Go to `/admin-events.html`, create an event, publish it
- [ ] As the test member, go to `/events.html`, register, cancel, register again
- [ ] Submit something at `/apply.html` and at `/propose.html`
- [ ] As yourself, go to `/admin-review.html` and accept one, decline the other

### The one that actually matters

- [ ] Signed in as the test member, open `https://ladslb.org/admin-dues.html`

You should see **"This page is for the Treasurer and the Executive Committee."**

If you see real payment records instead, **stop, tell me, and do not give anyone
else an account.** Everything else on this list is a feature. This one is member
privacy.

---

# If something goes wrong

**A page loads but does nothing.**
Right-click → Inspect → Console. Red text there tells you which file and line.
Send me the message.

**"Could not save" on a board page.**
Almost always a role. Check `select email, role from public.profiles;`

**No emails arriving.**
resend.com → Logs shows every attempt and the exact reason. Much better than
Supabase's error, which is deliberately vague.

**Something worked this morning and does not now.**
Netlify → Deploys → find the last good one → **Publish deploy**. Back in about
ten seconds. Nothing is lost.

**You want to undo a database change.**
You cannot, easily. This is why the SQL files are numbered and safe to re-run.
Ask before running anything not in `db/`.

---

# Not tonight

Leave these. They are in `docs/WORKSPACE_ROLLOUT.md` when you have the energy.

- The nine board members who have never signed into their @ladslb.org email.
  This is the highest-value hour of your week, but it is not tonight.
- `admin@ladslb.org`, the break-glass super admin
- `noreply@ladslb.org` as a group, so replies to sign-in emails go somewhere
- Confirming `scientific@` and `fundraising@` exist
- Shared Drive, groups, aliases
- A privacy notice for the portal, which should exist before you advertise it
  widely. Ask me and I will draft it.

---

# When you are done

The portal is live and you are the only account on it that can do anything. That
is the right place to stop.

Tell me how Part 7 went, particularly the last check.

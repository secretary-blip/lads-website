# Putting LADS on GitHub, and deploying from it

About fifteen minutes. After this, updating the website means editing a file and
pushing. No more dragging folders into Netlify, and no more wondering which zip
was the live one.

---

## Why bother

Right now the only complete copy of this website is a folder on your laptop. If
that laptop dies, the Association loses the site. If you change something and it
breaks, there is no way back to the version that worked.

GitHub fixes both, and adds the thing that actually matters for LADS: a future
board can be handed a link instead of a zip, and can see every change ever made
and who made it.

---

## 1. Create the repository

github.com → **New repository**

- Owner: create a **LADS organisation** if you can, rather than your personal
  account. Same reasoning as role-based email: your personal account leaves when
  you do. An organisation can have the next General Secretary added as an owner.
- Name: `lads-website`
- **Private**, unless the board decides otherwise
- Do **not** tick "Add a README". The repository below already has one.

## 2. Push it

Unzip `lads-repo.zip`. It already has git history and one commit, so you only
need to point it at GitHub:

```bash
cd lads-repo
git remote add origin https://github.com/YOUR-ORG/lads-website.git
git push -u origin main
```

If it asks for a password, GitHub wants a **personal access token**, not your
account password. github.com → Settings → Developer settings → Personal access
tokens → Fine-grained → generate one with Contents: Read and write.

## 3. Connect Netlify

In Netlify, open the existing ladslb.org site → **Site configuration** → **Build
& deploy** → **Link repository** → GitHub → pick `lads-website`.

Settings, which `netlify.toml` already declares:

| Field | Value |
|---|---|
| Branch to deploy | `main` |
| Build command | leave empty |
| Publish directory | `site` |

**Publish directory must be `site`, not the repository root.** That is what keeps
the SQL migrations and internal docs off the public website.

From now on every push to `main` deploys automatically, usually inside a minute.

## 4. Add a second person

Repository → Settings → Collaborators → add the President as an **admin**.

Netlify → Site configuration → Members → add them too.

Never fewer than two people with access. This is the whole reason the summer went
the way it did.

---

## Something to know about what was fixed here

In the folder you have been deploying, the database files sat next to
`index.html`. That means anyone could open **ladslb.org/portal_schema.sql** in a
browser and read every table and every security policy the portal uses.

It is not a catastrophe, because none of the security depends on those files
being secret. But there was no reason to publish them, and it saves an attacker
the trouble of guessing. The repository puts them in `db/`, outside the published
folder, so it cannot happen again.

**If you have already deployed the previous zip, this is live right now.**
Deploying from this repository replaces it and the files disappear. Worth doing
sooner rather than later.

---

## Making changes from now on

```bash
cd lads-repo
# edit something in site/
python3 tools/check.py     # catches broken scripts, dead links, leaked keys
git add -A
git commit -m "Describe what changed and why"
git push
```

Netlify deploys it. If something breaks, Netlify → Deploys → find the last good
one → **Publish deploy**. The site is back in about ten seconds.

Run `tools/check.py` before pushing. It takes a second and it catches the errors
that are invisible until a member hits them: a typo that silently stops a whole
page working, a link to a page that was renamed, a key pasted where it should not
be. GitHub runs the same checks on every push.

---

## What is in the repository

```
site/     the website and portal. Netlify publishes only this
db/       01_schema, 02_dues_bridge, 03_auth_update, 04_security
docs/     setup guide, workspace rollout, specification
tools/    check.py, run before pushing
```

---

## For the next General Secretary

Read `README.md` first, then `docs/PORTAL_SETUP.md`.

The short version: it is plain HTML, CSS and JavaScript with no build step, so
anyone who has done a web tutorial can maintain it. All the rules about who can
see what live in `db/` as database policies, not in the pages, so the site can be
redesigned without putting member data at risk.

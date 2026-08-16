# LADS website and member portal

The website and member portal of the **Lebanese Association of Dental Students**,
a non-profit NGO registered in Lebanon since 2015.

Live at **https://ladslb.org**

---

## Why it is built this way

This project is maintained by a board of dental students that changes every year.
Nobody here is a full-time developer, and the person who understands it best in
June has usually graduated by the following June. Every technical decision was
made with that in mind.

**Plain HTML, CSS and JavaScript. No framework, no build step.**
There is nothing to install, nothing to compile, and nothing that breaks because
a dependency released a new major version while everyone was on holiday. Open a
file, change it, push. Anyone who has done a web tutorial can maintain this.

**Permissions live in the database, not in the pages.**
Every rule about who can see what is a row-level security policy in
`db/`. If a future board rewrites the entire front end, member data stays
protected, because the protection was never in the front end.

**Membership is recorded per academic year.**
A member who joins in 2026 still has a visible record in 2031, across five
different boards. That continuity is the point of the whole portal.

---

## Layout

```
site/     the public website and portal. This is what Netlify publishes
db/       database migrations, run in order in the Supabase SQL Editor
docs/     setup guide, handover notes, specification
```

Nothing outside `site/` is ever served to the public. That split matters: the SQL
files describe every table and every security policy, and there is no reason for
them to be downloadable from the website.

---

## Making a change

1. Edit the file in `site/`
2. Commit and push to `main`
3. Netlify deploys it within a minute or so

That is the whole process. There is no build to run and no server to restart.

To preview locally before pushing:

```bash
cd site
python3 -m http.server 8000
```

Then open http://localhost:8000

Sign-in will not work on `localhost` unless `http://localhost:8000` is listed
under Supabase → Authentication → URL Configuration → Redirect URLs.

---

## The services this depends on

| What | Used for | Where it is managed |
|---|---|---|
| **Netlify** | Hosting, deploys from this repository | app.netlify.com |
| **Supabase** | Database, accounts, file storage | supabase.com |
| **Resend** | Sending sign-in and password emails | resend.com |
| **Namecheap** | The ladslb.org domain and DNS | namecheap.com |
| **Google Workspace** | Board email, Drive, Calendar | admin.google.com |

**Every one of these must have at least two board members who can get into it.**
In 2026 the Association lost several weeks of work because one account had a
single point of failure. Do not let that happen again.

---

## Database

Run these in the Supabase SQL Editor in order. Each is safe to run more than once.

| File | What it does |
|---|---|
| `db/01_schema.sql` | Tables, roles, and all row-level security policies |
| `db/02_dues_bridge.sql` | Connects public registrations to member accounts |
| `db/03_auth_update.sql` | Password accounts, profile creation on signup |
| `db/04_security.sql` | Closes privilege gaps found in the pre-launch audit |

Full instructions, including the Supabase dashboard settings that are not in SQL,
are in `docs/PORTAL_SETUP.md`.

---

## A note on the key in the source

`site/js/portal.js` contains a Supabase publishable key. **This is meant to be
public** and is not a mistake. It identifies the project; it grants nothing by
itself. Every table has row-level security enabled and no policy allows blanket
reads.

What must never be committed: the Supabase `service_role` key, the Resend API
key, or any Google Workspace password. Those live in Supabase settings and in the
board's password manager.

---

## Licence and ownership

Owned by the Lebanese Association of Dental Students. Maintained by the
Executive Committee of the day.

Questions: info@ladslb.org

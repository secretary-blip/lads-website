# LADS Digital Infrastructure, Handover

Everything the Association runs on, who controls it, and how to keep it working.
Written for the General Secretary. Hand this to your successor.

---

## 1. What we own

| Thing | Where | Cost | Renews |
|---|---|---|---|
| Domain, ladslb.org | Namecheap | ~$14/year | Yearly, auto-renew ON |
| Website hosting | Netlify | Free | Never expires |
| Membership database | Supabase | Free | Never expires |
| Email + Drive | Google Workspace for Nonprofits | Free | Yearly re-verification |

Only real cost is the domain. **If the domain lapses, the website, the email, and
the Workspace account all break at once.** Keep auto-renew on and keep a working
card on the Namecheap account.

---

## 2. Accounts and who holds them

All four should be under the LADS Google account, not a personal one.
When the board changes, transfer these before anything else.

- Namecheap, holds the domain
- Netlify, hosts the site
- Supabase, holds member data
- Google Workspace admin, admin.google.com

Store the passwords in one place the Executive Committee can reach.

---

## 3. Updating the website

### The safe way
Tell Claude what to change, get a new zip back, then:

1. app.netlify.com, open the LADS site
2. **Deploys** tab
3. Drag the `lads-website` folder onto the drop area
4. Live in about 30 seconds

Netlify keeps every past version. If something breaks: Deploys, click an older
one, **Publish deploy**. Instant rollback.

### Edits you can make yourself
Open the file in TextEdit or Notepad, change text between `>` and `<`, save, redeploy.

| Want to change | File | Look for |
|---|---|---|
| Add a news item | news.html | copy a `<div class="news-item">` block |
| Committee head changed | committees.html and about.html | the person's name |
| Whish number | join.html | "Not available at this moment" |
| Contact email | all pages | info@ladslb.org |

### Do not edit without help
- `css/style.css`, controls the whole look of every page
- the `<script>` block at the bottom of `join.html`, this is the registration form

### Worth doing later
Connect the site to a GitHub repository instead of dragging folders. Edits then
deploy automatically and you get real version history. More setup once, less
friction forever after.

---

## 4. Supabase, checking it works

### Monthly, two minutes
1. supabase.com, open the LADS project
2. **Table Editor**, `registrations`. New sign-ups appear as rows.
3. **Storage**, `payment-proofs`. Payment screenshots land here.
4. If both have recent entries and the numbers match, everything is fine.

### After any change to the website, test the form end to end
1. Open the live site, Join page
2. Fill it in with your own details, attach any image, submit
3. You should see the green success message
4. Check the row appeared in Table Editor
5. **Delete your test row afterwards**

If the form errors: press F12, open the **Console** tab, screenshot the red text,
send it to Claude. That message says exactly what broke.

### Watch the free-tier limits
**Project Settings, Usage.** Free tier gives 500MB database and 1GB file storage.
Payment screenshots are what fill it up. A few thousand registrations is fine.
If storage climbs past ~800MB, download old screenshots to Drive and delete them
from the bucket.

**Important:** Supabase pauses free projects after 7 days with zero activity.
The pause is reversible, one click to restore, but the form stops accepting
submissions while paused. Opening the dashboard counts as activity, so the monthly
check also prevents this.

### Security, do not undo these
- The `registrations` table has Row Level Security on. The public can submit but
  cannot read anyone's data. If you ever see "Unrestricted" next to a table or
  view in the dashboard, that data is publicly readable. Fix it before continuing.
- Never create database **views** on member data. Views bypass Row Level Security
  by default. This exact mistake exposed our data once and was caught before launch.
- The key in the website code is the **publishable** key. That one is safe in public.
  The **secret** key must never appear on the website or in any shared file.

### Adding the Treasurer
Project Settings, Team, Invite member. Role: **Developer**. They can read and edit
data but cannot delete the project.

### Exporting the member list
Table Editor, `registrations`, the ⋮ menu, Download as CSV.

---

## 5. Google Workspace

- Admin console: admin.google.com, signed in as vicepresident@ladslb.org
- Nonprofit status must be re-verified yearly. Google emails a reminder. Ignoring
  it means the account reverts to paid.
- **The account has recovery phone and recovery email set. Keep them current.**
  It was locked out for days once because neither was configured. Do not remove them.
- Creating an address for a board member: Directory, Users, Add new user.

---

## 6. If something breaks

| Symptom | Likely cause | Fix |
|---|---|---|
| Site shows "Not Found" | Deploy failed | Netlify, Deploys, republish the last good one |
| Whole site is down | Domain expired | Namecheap, renew immediately |
| Form says "Error:" on submit | Supabase paused or schema changed | Open Supabase dashboard, check the project is active |
| Email stops arriving | MX records changed | Namecheap, Advanced DNS, MX must be smtp.google.com priority 1 |
| Site loads unstyled | css/style.css missing from upload | Redeploy the complete folder |

---

## 7. Still outstanding

- Real photos. Homepage uses six grey placeholders at `assets/photo1.jpg` to `photo6.jpg`.
  Replace with real files of the same names, no code change needed.
- Whish number, goes into join.html when the account is ready.
- Whish Pay merchant account, Treasurer's task. Once approved, the manual
  screenshot step can be replaced with a real payment button.
- Registration opens September. The join page says so; update that notice when it does.

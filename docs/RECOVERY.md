# Workspace Recovery Plan — do in this order (20 min total)

## Root cause
Google Workspace was created on domain **ladslb.org**.
That domain was never purchased. It does not exist in DNS (confirmed via .org registry, 2026-07-10).
No DNS = no domain verification = every recovery path fails.
Good news: ladslb.org is available to register right now.

## Step 1 — Buy ladslb.org (5 min)
- Namecheap.com → search "ladslb.org" → buy (~$10-13/year)
- Use LADS/treasurer card or personal + reimburse
- IMPORTANT: buy exactly **ladslb.org** — the Workspace is bound to this exact spelling.
  (ladsleb.org can be bought later as extra and redirected, optional.)

## Step 2 — Add recovery CNAME (5 min)
Namecheap → Domain List → ladslb.org → Advanced DNS → Add New Record:

| Type  | Host      | Value      | TTL  |
|-------|-----------|------------|------|
| CNAME | 73128785  | google.com | 3600 |

Host field: number only, nothing else.

## Step 3 — Verify with Google (2 min + wait)
- Return to the Google Admin Toolbox recovery tab (reference #73128785)
- Click **CHECK AGAIN**
- If it fails immediately: wait 30-60 min, click again (propagation)
- Google also emailed a link with the reference number — check inbox used in the form

## Step 4 — After account recovered
- Reset password for vicepresident@ladslb.org
- IMMEDIATELY add: recovery phone + recovery email (prevents repeat of this lockout)
- Enable 2FA
- Keep the CNAME until fully done, then it can be deleted

## Step 5 — Point rest of DNS (website + email), same Advanced DNS screen

| Type  | Host | Value                  | Purpose            |
|-------|------|------------------------|--------------------|
| A     | @    | 75.2.60.5              | Netlify website    |
| CNAME | www  | YOUR-SITE.netlify.app  | Netlify website    |
| MX    | @    | smtp.google.com (pri 1)| Workspace email    |
| TXT   | @    | (Google gives this in Admin console → verify domain) | Workspace |

## Notes
- Website email addresses should become info@ladslb.org (site files currently say
  info@ladsleb.org — Claude will swap them once domain confirmed).
- Update the pending Google support case after recovery: "resolved via domain
  registration + CNAME verification" — or leave it, it closes itself.

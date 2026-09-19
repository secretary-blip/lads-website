# Turning the Journal Club on

About 15 minutes, mostly in the browser. The code and the database are already
done; this is the part that cannot be shipped in a patch.

When it is finished, four things happen on their own:

| When | Who gets an email |
|---|---|
| A member joins the club | The NRO gets their answers |
| A member joins the club | The member gets a welcome, and the group link if they asked for it |
| A member says they are coming to a session | The NRO |
| A member changes their mind | The NRO |

---

## Before you start

**`nro@ladslb.org` has to actually deliver to Nour.** Every email below goes
there. It is a role address on purpose, so the next NRO inherits it without
anybody editing code, but that only works if it exists. Google Admin console →
Directory → Groups. Either a group with Nour as a member, or a forward.

Test it by sending a message to `nro@ladslb.org` from your phone and checking she
receives it. Do this first. Everything else is pointless if this is wrong.

---

## 1. Update the notify function

The function already exists and already sends the Treasurer's emails. This
replaces it with a version that also handles the club. Nothing about the payment
emails changes.

Supabase → **Edge Functions** → `notify` → **Edit**

- Select all, delete
- Paste all of `supabase/functions/notify/index.ts` from the repository
- **Deploy**

The old version keeps running until the new one finishes building, so nothing
breaks in between.

### Why the function needed changing at all

The database triggers post `{type, table, record, old_record}` to one URL. The
function decides what to do by looking at `table`. Adding the club meant one new
branch, not a second webhook, a second secret and a second place for mail to
break quietly.

---

## 2. Add the WhatsApp link

Supabase → Edge Functions → **Secrets** → Add new secret.

| Name | Value |
|---|---|
| `WHATSAPP_INVITE` | the Journal Club group invite link |

**This does not go in the repository.** The repository is public on GitHub, and
anybody holding that URL can join the group.

If you leave the secret unset, nothing breaks. The welcome email simply tells the
student that Nour will add them by hand. That is the safe default, so an empty
secret is a reasonable state to be in.

If the link ever leaks, reset it in WhatsApp and paste the new one here. No code
changes.

---

## 3. Add the semester's papers

Until there is a row in `journal_papers`, the sessions list is empty and the page
says so. There is no admin screen for this yet, so for now papers are added in
SQL, by you, from Nour's list.

One row per session:

```sql
insert into public.journal_papers
  (session_on, topic, title, journal, pub_year, doi, url, summary, presenter, published)
values
  ('2026-10-04',
   'To start',
   'Can AI spot a cavity?',
   'Journal of Dental Research',
   2025,
   '10.0000/example',
   'https://doi.org/10.0000/example',
   'Two or three sentences in our own words. This is the part that matters: a '
   'student without library access hits a paywall on the link, and the summary '
   'is what lets them take part anyway.',
   'Riad Jawhar',
   true);
```

`published` controls visibility. Leave it `false` while the committee is still
deciding and the row is invisible to everyone but the board. Flip it to `true`
when it is ready.

`session_on` is unique, so one paper per date. Running the same insert twice will
be refused rather than creating a duplicate.

To correct a paper later:

```sql
update public.journal_papers
   set title = 'The corrected title'
 where session_on = '2026-10-04';
```

---

## 4. Test it properly

Use a real account and a real inbox. A test that skips the email is not a test.

1. Sign in at `https://ladslb.org/account.html` with an account that is not
   already a club member.
2. Open the **Journal Club** card, fill the form, tick the WhatsApp box, submit.
3. `nro@ladslb.org` should receive **"Journal Club: your name joined"** with your
   answers in a table.
4. Your own address should receive **"You are in the LADS Journal Club"**, with
   the group button if you set the secret in step 2.
5. The page should now show the sessions. Press **Coming** on one.
6. `nro@ladslb.org` should receive **"Journal Club: your name is coming"**.
7. Press **Cannot make it** on the same session. She should receive one more
   saying so, and there should still be only one row for you in the database,
   not two.

Then clean up:

```sql
delete from public.journal_rsvps  where profile_id = '<your profile id>';
delete from public.journal_members where profile_id = '<your profile id>';
```

---

## If no email arrives

In this order, because this is the order things actually go wrong.

1. **Did anything save?** Check `journal_members` in the table editor. If the row
   is missing, the problem is the page or a policy, not email.
2. **resend.com → Logs.** An attempt with an error means the mail itself failed.
   No attempt at all means the function never ran.
3. **Supabase → Edge Functions → notify → Logs.** `401 Not authorised` means the
   webhook secret in the database and the one in Secrets do not match. Retype
   both rather than pasting from somewhere that might add a space.
4. **`nro@ladslb.org`.** Send it a message by hand. If that does not arrive
   either, the problem was never the code.

---

## How Nour sees who is coming

Right now, from her inbox. One email per RSVP, and one more when somebody changes
their mind, so the count is the thread.

The database can answer it directly too:

```sql
select * from public.journal_session_list(
  (select id from public.journal_papers where session_on = '2026-10-04')
);
```

That returns name, email, phone, university, year and their answer, and it
refuses to return anything to somebody who is not on the board.

**This is a gap, and it should not last.** Nour should not be opening SQL to find
out who is coming to her own session, for the same reason the Treasurer never
opens Supabase. An admin page is the fix and it is not built yet. Until it is,
the inbox is the honest answer, and it works for the numbers a first semester
will produce.

---

## What is deliberately not here

**No attendance register.** These tables record who said they were coming, not
who turned up. Those are different facts and mixing them would make both
untrustworthy.

**No reminder emails.** Adding them means deciding when they fire, and a badly
timed reminder is worse than none. Worth doing once there is a term's worth of
sessions to learn from.

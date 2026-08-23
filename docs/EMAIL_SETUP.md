# Automatic emails

About 20 minutes, all in the browser. No terminal.

Once this is done, three things happen on their own:

| When | Who gets an email |
|---|---|
| Someone registers on the Join form | The Treasurer and the Executive Committee |
| The Treasurer confirms a payment | The member, welcoming them and pointing at the portal |
| The Treasurer cannot verify a payment | The member, asking for a clearer screenshot |

Nobody has to remember to check anything, which is the point. In September, "the
Treasurer will look at the page each evening" is not a process that survives exam
week.

---

## Before you start

You need `noreply@ladslb.org` to exist as a **group** in Google Admin, with
`secretary@` and `info@` as members. Resend can already send from that address
because the domain is verified, but members will reply to these emails regardless
of what the address is called, and right now those replies go nowhere.

Admin console → Directory → Groups → Create group.

---

## 1. Make a webhook secret

This function will sit at a public URL. Without a shared secret, anyone who finds
it could make our domain send email, and our sending reputation would be gone in
an afternoon.

Make up a long random string, 30 characters or so. Any password generator will do.
Keep it somewhere for the next five minutes; you will paste it three times.

---

## 2. Create the function

Supabase → **Edge Functions** → **Deploy a new function** → **Via Editor**

- Name it exactly `notify`
- Delete the sample code
- Paste all of `supabase/functions/notify/index.ts` from the repository
- **Deploy**

It will take a minute or so to build.

---

## 3. Add the secrets

Supabase → Edge Functions → **Secrets** → Add new secret. Two of them:

| Name | Value |
|---|---|
| `RESEND_API_KEY` | your Resend sending key, the one starting `re_` |
| `WEBHOOK_SECRET` | the random string from step 1 |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are already there automatically.
Do not add them, and do not put either of them anywhere else.

---

## 4. Point the database at it

Supabase → **Database** → **Webhooks** → **Create a new hook**.

You are creating **two**, both on the `registrations` table.

### Hook one, new registrations

| Field | Value |
|---|---|
| Name | `notify_new_registration` |
| Table | `registrations` |
| Events | **Insert** only |
| Type | HTTP Request |
| Method | `POST` |
| URL | `https://fazswkdinsbqymgwlebr.supabase.co/functions/v1/notify` |

HTTP Headers, add one:

| Header | Value |
|---|---|
| `x-webhook-secret` | the random string from step 1 |

### Hook two, payment decisions

Same as above, with two changes:

| Field | Value |
|---|---|
| Name | `notify_payment_decision` |
| Events | **Update** only |

Everything else identical, including the header.

---

## 5. Test it

The honest test is a real one.

1. Go to `https://ladslb.org/join.html` and register as yourself, using an email
   address you can actually open. Attach any image as the screenshot.
2. Within a few seconds, the Treasurer address should receive
   **"New registration: your name"**.
3. Sign in, open `admin-dues.html`, and confirm the payment.
4. The address you registered with should receive **"Your LADS membership is
   confirmed"**.
5. Delete the test registration afterwards from the Supabase table editor, or
   leave it and mark it rejected. Do not leave a fake paid membership in the
   count.

### If no email arrives

Check in this order, because this is the order things actually go wrong:

1. **resend.com → Logs.** If the attempt is here with an error, the problem is
   the email itself. If it is not here at all, the function never ran.
2. **Supabase → Edge Functions → notify → Logs.** A `401 Not authorised` means
   the header and the secret do not match. Retype both, do not paste from a
   document that might have added a space.
3. **Supabase → Database → Webhooks → the hook → Logs.** If there is nothing
   here, the hook is on the wrong table or the wrong event.

---

## What members actually receive

Plain, short, and readable on a phone. No heavy template, because Gmail clips
long HTML and half the clients students use render fancy layouts badly.

Every email carries the Association's registration number and replies go to
`info@ladslb.org`, so a member replying reaches a person rather than a void.

---

## When the Treasurer changes

Nothing to do. The function reads the current Treasurer and Executive Committee
out of the database every time it runs, so the day you change Omar's successor's
role on `admin-members.html`, the emails follow.

That is deliberate. A hard-coded address in a file nobody remembers exists is
exactly how these systems quietly stop working a year later.

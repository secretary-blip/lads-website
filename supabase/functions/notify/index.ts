// =============================================================================
// LADS, registration notifications
//
// Called by database triggers on public.memberships:
//   status -> pending    tell the Treasurer a payment is waiting
//   status -> paid       tell the member they are confirmed
//   status -> rejected   tell the member what to send instead
//
// Why this exists: without it the Treasurer has to remember to open the portal,
// and members are left guessing whether their transfer arrived. In September,
// with a hundred registrations in a fortnight, "remember to check" is not a
// process.
//
// DEPLOY FROM THE DASHBOARD. Edge Functions -> Create function -> paste this ->
// Deploy. No terminal, no CLI, nothing to install. Full instructions are in
// docs/EMAIL_SETUP.md.
//
// Secrets required (Edge Functions -> Secrets):
//   RESEND_API_KEY   the sending key from resend.com
//   WEBHOOK_SECRET   any long random string; also set as a webhook header
// =============================================================================

const RESEND_KEY     = Deno.env.get("RESEND_API_KEY")!;
const WEBHOOK_SECRET = Deno.env.get("WEBHOOK_SECRET")!;
const SUPABASE_URL   = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY    = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const FROM      = "LADS <noreply@ladslb.org>";
const REPLY_TO  = "info@ladslb.org";
const PORTAL    = "https://ladslb.org";

/* A membership row. The member's name and email are not on it, so the function
   looks them up. Denormalising them onto the membership would mean two copies
   of an email address that can be changed in one place. */
type Membership = {
  id: string;
  profile_id: string;
  academic_year: string;
  status: "unpaid" | "pending" | "paid" | "rejected";
  method: string | null;
  amount_usd: number;
  notes: string | null;
  reminder_sent_at: string | null;
  reminder_count: number;
};

type Person = {
  full_name: string;
  email: string;
  phone: string | null;
  university: string | null;
  academic_year: string | null;
};

type Payload = {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  record: Membership;
  old_record: Membership | null;
};

/* Who should hear about payments. Read live from the database rather
   than hard-coded, so when the Treasurer changes next year nobody has to
   remember this file exists. */
async function boardEmails(): Promise<string[]> {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/profiles?select=email&role=in.(admin,super_admin)`,
    { headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` } },
  );
  if (!res.ok) {
    console.error("Could not read board emails:", await res.text());
    return ["info@ladslb.org"];
  }
  const rows = (await res.json()) as { email: string }[];
  const list = rows.map((r) => r.email).filter(Boolean);
  return list.length ? list : ["info@ladslb.org"];
}

async function person(profileId: string): Promise<Person | null> {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/profiles?id=eq.${profileId}` +
    `&select=full_name,email,phone,university,academic_year`,
    { headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` } },
  );
  if (!res.ok) { console.error("Could not read profile:", await res.text()); return null; }
  const rows = (await res.json()) as Person[];
  return rows[0] ?? null;
}

async function sendEmail(to: string[], subject: string, html: string) {
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ from: FROM, to, subject, html, reply_to: REPLY_TO }),
  });
  if (!res.ok) console.error("Resend rejected the email:", await res.text());
  return res.ok;
}

/* Deliberately plain HTML. Heavy templates get clipped by Gmail and look
   broken in half the clients students actually use. */
function shell(heading: string, body: string, cta?: { text: string; href: string }) {
  return `<div style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;
    max-width:560px;margin:0 auto;padding:24px;color:#111;line-height:1.6;">
    <p style="font-size:12px;letter-spacing:1.5px;text-transform:uppercase;color:#C00000;
      font-weight:700;margin:0 0 8px;">Lebanese Association of Dental Students</p>
    <h1 style="font-size:22px;margin:0 0 16px;">${heading}</h1>
    ${body}
    ${cta ? `<p style="margin:24px 0;"><a href="${cta.href}"
      style="background:#C00000;color:#fff;text-decoration:none;padding:13px 22px;
      border-radius:4px;display:inline-block;font-weight:700;">${cta.text}</a></p>` : ""}
    <hr style="border:0;border-top:1px solid #e4e4e4;margin:28px 0 12px;">
    <p style="font-size:12px;color:#666;margin:0;">
      LADS is a non-profit NGO registered in Lebanon. Registration number 1658.<br>
      Questions? Reply to this email or write to info@ladslb.org
    </p>
  </div>`;
}

function esc(v: unknown) {
  return String(v ?? "").replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c] as string));
}

Deno.serve(async (req) => {
  /* Anyone can find this URL. Without a shared secret, anyone could also fire
     off emails from our domain, which would end our sending reputation in an
     afternoon. */
  if (req.headers.get("x-webhook-secret") !== WEBHOOK_SECRET) {
    return new Response("Not authorised", { status: 401 });
  }

  let payload: Payload;
  try {
    payload = await req.json();
  } catch {
    return new Response("Bad request", { status: 400 });
  }

  const rec = payload.record;
  const old = payload.old_record;

  // A membership only becomes interesting when it enters or leaves review.
  const nowPending  = rec.status === "pending";
  const wasPending  = old?.status === "pending";
  const becamePaid  = rec.status === "paid"     && old?.status !== "paid";
  const becameNo    = rec.status === "rejected" && old?.status !== "rejected";
  const newlyPending = nowPending && (payload.type === "INSERT" || !wasPending);
  /* The Treasurer pressed "Send reminder". The stamp only moves through
     remind_membership(), so this cannot fire on an ordinary edit. */
  const reminded = payload.type === "UPDATE" &&
    !!rec.reminder_sent_at &&
    rec.reminder_sent_at !== (old?.reminder_sent_at ?? null);

  if (!newlyPending && !becamePaid && !becameNo && !reminded) {
    return new Response("nothing to do");
  }

  const who = await person(rec.profile_id);
  if (!who) return new Response("no profile", { status: 200 });

  // ------------------------------------------------- payment submitted
  if (newlyPending) {
    const to = await boardEmails();
    const rows = [
      ["Name", who.full_name],
      ["Email", who.email],
      ["Phone", who.phone ?? "Not given"],
      ["University", `${who.university ?? ""} ${who.academic_year ?? ""}`.trim()],
      ["Year", rec.academic_year],
      ["Method", rec.method ?? "Not given"],
      ["Amount", `$${Number(rec.amount_usd ?? 10).toFixed(2)}`],
    ];
    await sendEmail(
      to,
      `Payment to verify: ${who.full_name}`,
      shell(
        "A payment is waiting",
        `<table style="width:100%;border-collapse:collapse;font-size:14px;">
          ${rows.map(([k, v]) => `<tr>
            <td style="padding:6px 12px 6px 0;color:#666;vertical-align:top;white-space:nowrap;">${esc(k)}</td>
            <td style="padding:6px 0;"><strong>${esc(v)}</strong></td></tr>`).join("")}
        </table>
        <p style="font-size:14px;color:#666;margin-top:18px;">
          Their screenshot is on the dues page. Confirming it there updates their
          account immediately and sends them a confirmation.
        </p>`,
        { text: "Review this payment", href: `${PORTAL}/admin-dues.html` },
      ),
    );
    return new Response("ok");
  }

  // ------------------------------------------------- payment confirmed
  if (becamePaid) {
    await sendEmail(
      [who.email],
      "Your LADS membership is confirmed",
      shell(
        `Welcome to LADS, ${esc((who.full_name || "").split(" ")[0])}.`,
        `<p style="font-size:15px;">Your payment has been verified and your
           membership is active for ${esc(rec.academic_year)}.</p>
         <p style="font-size:15px;">You can now register for members-only events,
           apply for exchanges and voluntary projects, and put your name forward
           for a committee.</p>`,
        { text: "Open the member portal", href: `${PORTAL}/account.html` },
      ),
    );
    return new Response("ok");
  }

  // ------------------------------------------------- dues reminder
  if (reminded) {
    const first = esc((who.full_name || "").split(" ")[0]);
    const again = (rec.reminder_count ?? 1) > 1;
    await sendEmail(
      [who.email],
      `Your LADS membership for ${rec.academic_year} is still unpaid`,
      shell(
        `${first}, your dues are outstanding`,
        `<p style="font-size:15px;">Our records show your LADS membership for
           ${esc(rec.academic_year)} has not been paid.${again
             ? " This is a second reminder." : ""}</p>
         <p style="font-size:15px;">Membership is
           $${Number(rec.amount_usd ?? 20).toFixed(0)} for the whole academic
           year. Pay by whish to <strong>+961 78 78 20 96</strong>, or in cash
           to a board member at any event, then submit it on the payment page so
           we can verify it.</p>
         <p style="font-size:15px;">If you have already paid, reply to this
           email and we will sort it out.</p>`,
        { text: "Submit your payment", href: `${PORTAL}/pay.html` },
      ),
    );
    return new Response("ok");
  }

  // ------------------------------------------------- could not verify
  if (becameNo) {
    await sendEmail(
      [who.email],
      "We could not confirm your LADS payment",
      shell(
        "We need to check something",
        `<p style="font-size:15px;">${esc(rec.notes ??
            "Our Treasurer could not match your payment to the transfer records. " +
            "That usually means the screenshot was unclear, or the transfer had " +
            "not gone through yet.")}</p>
         <p style="font-size:15px;">Nothing is lost. Upload a clearer screenshot,
           showing the date and reference, and we will sort it out.</p>`,
        { text: "Send a new screenshot", href: `${PORTAL}/pay.html` },
      ),
    );
    return new Response("ok");
  }

  return new Response("nothing to do");
});

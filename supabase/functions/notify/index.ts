// =============================================================================
// LADS, registration notifications
//
// Called by two Supabase Database Webhooks on public.registrations:
//   INSERT  -> tell the Treasurer somebody registered
//   UPDATE  -> tell the member their payment was confirmed, or was not
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

type Registration = {
  id: string;
  full_name: string;
  email: string;
  phone: string | null;
  university: string | null;
  academic_year: string | null;
  payment_method: string;
  payment_verified: boolean;
  rejected: boolean;
  workforce: boolean;
  workforce_committee: string | null;
  interests: string[] | null;
};

type Payload = {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  record: Registration;
  old_record: Registration | null;
};

/* Who should hear about new registrations. Read live from the database rather
   than hard-coded, so when the Treasurer changes next year nobody has to
   remember this file exists. */
async function boardEmails(): Promise<string[]> {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/profiles?select=email&role=in.(treasurer,executive)`,
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

  // ---------------------------------------------------------------- INSERT
  if (payload.type === "INSERT") {
    const to = await boardEmails();
    const rows = [
      ["Name", rec.full_name],
      ["Email", rec.email],
      ["Phone", rec.phone ?? "Not given"],
      ["University", `${rec.university ?? ""} ${rec.academic_year ?? ""}`.trim()],
      ["Payment method", rec.payment_method],
      ["Interests", (rec.interests ?? []).join(", ") || "None selected"],
    ];
    if (rec.workforce) {
      rows.push(["Workforce", `Wants to be a deputy head${
        rec.workforce_committee ? `, ${rec.workforce_committee.replace(/_/g, " ")}` : ""}`]);
    }

    await sendEmail(
      to,
      `New registration: ${rec.full_name}`,
      shell(
        "Someone has registered",
        `<table style="width:100%;border-collapse:collapse;font-size:14px;">
          ${rows.map(([k, v]) => `<tr>
            <td style="padding:6px 12px 6px 0;color:#666;vertical-align:top;white-space:nowrap;">${esc(k)}</td>
            <td style="padding:6px 0;"><strong>${esc(v)}</strong></td></tr>`).join("")}
        </table>
        <p style="font-size:14px;color:#666;margin-top:18px;">
          Their payment screenshot is on the dues page. Confirming it there updates
          their account immediately and sends them a confirmation email.
        </p>`,
        { text: "Review this payment", href: `${PORTAL}/admin-dues.html` },
      ),
    );
    return new Response("ok");
  }

  // ---------------------------------------------------------------- UPDATE
  if (payload.type === "UPDATE" && old) {
    // Confirmed: was not verified, now is.
    if (!old.payment_verified && rec.payment_verified) {
      await sendEmail(
        [rec.email],
        "Your LADS membership is confirmed",
        shell(
          `Welcome to LADS, ${esc(rec.full_name.split(" ")[0])}.`,
          `<p style="font-size:15px;">Your payment has been verified and your membership
             is active for this academic year.</p>
           <p style="font-size:15px;">Create your portal account, or sign in if you already
             have one, to see your membership, register for events, and apply for exchanges
             and voluntary projects. Use <strong>${esc(rec.email)}</strong>, the same address
             you registered with, and everything links up on its own.</p>`,
          { text: "Open the member portal", href: `${PORTAL}/signup.html` },
        ),
      );
      return new Response("ok");
    }

    // Could not verify: newly rejected.
    if (!old.rejected && rec.rejected) {
      await sendEmail(
        [rec.email],
        "We could not confirm your LADS payment",
        shell(
          "We need to check something",
          `<p style="font-size:15px;">Thank you for registering. Our Treasurer could not
             match your payment to the transfer records, which usually means the screenshot
             was unclear or the transfer is still in progress.</p>
           <p style="font-size:15px;">Nothing is lost. Reply to this email with a clear
             screenshot of the confirmation, including the date and reference, and we will
             sort it out.</p>`,
        ),
      );
      return new Response("ok");
    }
  }

  return new Response("nothing to do");
});

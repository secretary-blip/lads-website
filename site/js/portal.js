/* =============================================================================
   LADS Portal, shared client and helpers
   Plain ES module. No build step. Loaded by every portal page.
   ========================================================================== */

export const SUPABASE_URL = "https://fazswkdinsbqymgwlebr.supabase.co";
export const SUPABASE_KEY = "sb_publishable_O36-PFnAMT9-E_tlXtdYBQ_tISXojd6";

// supabase-js is loaded from CDN as a global before this module runs
export const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

/* ---------------------------------------------------------------- session */

export async function getSession() {
  const { data } = await sb.auth.getSession();
  return data.session;
}

/** Redirect to login unless signed in. Returns the session. */
export async function requireAuth() {
  const session = await getSession();
  if (!session) {
    const back = encodeURIComponent(location.pathname.replace(/^\//, "") + location.search);
    location.replace(`login.html?next=${back}`);
    return null;
  }
  return session;
}

export async function signOut() {
  await sb.auth.signOut();
  location.href = "index.html";
}

/* ------------------------------------------------------------------- auth */

/**
 * Passwords, not magic links.
 *
 * Supabase is told to send a confirmation email, so an address cannot be used
 * until the person proves they can read that inbox. Without it anyone could
 * register under someone else's email and the Treasurer would have no way of
 * knowing which registration was genuine.
 */
export async function signUp({ email, password, fullName, university, academicYear, phone }) {
  return sb.auth.signUp({
    email: email.trim(),
    password,
    options: {
      emailRedirectTo: `${location.origin}/auth-callback.html?next=%2Faccount.html`,
      // Read by the handle_new_user trigger to populate the profile row.
      data: {
        full_name: (fullName || "").trim(),
        university: university || null,
        academic_year: academicYear || null,
        phone: (phone || "").trim() || null,
      },
    },
  });
}

export async function signIn(email, password) {
  return sb.auth.signInWithPassword({ email: email.trim(), password });
}

export async function requestPasswordReset(email) {
  return sb.auth.resetPasswordForEmail(email.trim(), {
    redirectTo: `${location.origin}/reset-password.html`,
  });
}

export async function updatePassword(password) {
  return sb.auth.updateUser({ password });
}

export async function resendConfirmation(email) {
  return sb.auth.resend({
    type: "signup",
    email: email.trim(),
    options: { emailRedirectTo: `${location.origin}/auth-callback.html?next=%2Faccount.html` },
  });
}

/**
 * Minimum bar for a password, checked in the browser for a helpful message.
 * Supabase enforces its own minimum server-side, so this cannot be bypassed by
 * editing the page.
 */
export function passwordProblem(pw) {
  if (!pw || pw.length < 8) return "Use at least 8 characters.";
  if (!/[a-zA-Z]/.test(pw)) return "Include at least one letter.";
  if (!/[0-9]/.test(pw)) return "Include at least one number.";
  return null;
}

/** Turn Supabase auth errors into something a person can act on. */
export function authMessage(error) {
  const m = (error && error.message ? error.message : "").toLowerCase();
  if (m.includes("invalid login credentials"))
    return "That email and password do not match. Check both, or reset your password.";
  if (m.includes("email not confirmed"))
    return "Please confirm your email first. Check your inbox for the link we sent.";
  if (m.includes("user already registered") || m.includes("already been registered"))
    return "There is already an account with that email. Try signing in instead.";
  if (m.includes("password should be"))
    return "That password is too short. Use at least 8 characters.";
  if (m.includes("rate limit") || m.includes("too many"))
    return "Too many attempts. Please wait a few minutes and try again.";
  if (m.includes("for security purposes"))
    return "Please wait a moment before trying again.";
  return (error && error.message) || "Something went wrong. Please try again.";
}

/* ---------------------------------------------------------------- profile */

export async function getProfile() {
  const session = await getSession();
  if (!session) return null;
  const { data, error } = await sb
    .from("profiles")
    .select("*")
    .eq("id", session.user.id)
    .single();
  if (error) { console.error(error); return null; }
  return data;
}

export const ROLE_LABEL = {
  member: "Member",
  committee_head: "Committee Head",
  admin: "Administrator",
  super_admin: "Executive Committee",
};

/** Admins and above. Can see payments and every member. */
export function isAdmin(profile) {
  return !!profile && ["admin", "super_admin"].includes(profile.role);
}

/** Anyone with a board responsibility. Committee heads included, and they can
    review applications to their own committee without seeing payments. */
export function isStaff(profile) {
  return !!profile && ["committee_head", "admin", "super_admin"].includes(profile.role);
}

export function isCommitteeHead(profile) {
  return !!profile && profile.role === "committee_head";
}

/* ------------------------------------------------------------- membership */

/** Academic year runs September to August, e.g. "2026/2027". */
export function currentAcademicYear(d = new Date()) {
  const y = d.getFullYear();
  return d.getMonth() >= 8 ? `${y}/${y + 1}` : `${y - 1}/${y}`;
}

/**
 * Which membership year dues are being collected for right now.
 *
 * Not the same question as currentAcademicYear(). The year starts in
 * September, but members pay ahead over the summer. Someone paying in July is
 * paying for the year that starts in September, so from July onward we look at
 * the coming year. Mirrors public.dues_year_of() in the database, and the two
 * must be changed together.
 */
export function duesYear(d = new Date()) {
  const y = d.getFullYear();
  return d.getMonth() >= 6 ? `${y}/${y + 1}` : `${y - 1}/${y}`;
}

export async function getMemberships() {
  const session = await getSession();
  if (!session) return [];
  const { data, error } = await sb
    .from("memberships")
    .select("*")
    .eq("profile_id", session.user.id)
    .order("academic_year", { ascending: false });
  if (error) { console.error(error); return []; }
  return data;
}

export const DUES_LABEL = {
  unpaid:   "Not paid",
  pending:  "Awaiting verification",
  paid:     "Paid",
  rejected: "Payment not verified",
  // Retired, kept so historical rows still render a sensible word.
  pending_verification: "Awaiting verification",
  waived:   "Paid",
};

/** Does this membership grant member privileges? Only a confirmed payment. */
export function isPaidUp(membership) {
  return !!membership && membership.status === "paid";
}

/* ------------------------------------------------------------------ utils */

export function fmtDate(value) {
  if (!value) return "";
  return new Date(value).toLocaleDateString("en-GB", {
    day: "numeric", month: "long", year: "numeric",
  });
}

export function escapeHtml(s) {
  return String(s ?? "").replace(/[&<>"']/g, c => (
    { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]
  ));
}

/** Render a message into an element, styled by kind. */
export function say(el, message, kind = "info") {
  if (!el) return;
  el.textContent = message;
  el.className = "form-msg " + kind;
}

/* -------------------------------------------------------------- membership */

/**
 * The member creates their own membership row and attaches proof.
 *
 * The database will not let them set `paid`, or touch verified_by, verified_at
 * or paid_on: guard_membership refuses. This function only ever asks for what a
 * member is allowed to ask for, but the refusal is what actually protects it.
 */
export async function submitPayment({ academicYear, method, file }) {
  const session = await getSession();
  if (!session) throw new Error("Please sign in first.");

  let proofPath = null;

  if (file) {
    if (file.size > 5 * 1024 * 1024) throw new Error("The file must be under 5MB.");
    const ext = (file.name.split(".").pop() || "png").toLowerCase();
    /* The folder is the permission. Storage policy only lets someone read and
       write inside a folder named after their own user id, so the path itself
       is what stops one member opening another member's receipt. */
    proofPath = `${session.user.id}/${Date.now()}.${ext}`;
    const { error: upErr } = await sb.storage
      .from("payment-proofs")
      .upload(proofPath, file, { upsert: false });
    if (upErr) throw upErr;
  }

  const row = {
    profile_id: session.user.id,
    academic_year: academicYear,
    status: file ? "pending" : "unpaid",
    method: method || null,
    proof_path: proofPath,
  };

  /* One row per person per year, so re-submitting updates rather than
     duplicating. The unique constraint would refuse a second row anyway. */
  const { error } = await sb
    .from("memberships")
    .upsert(row, { onConflict: "profile_id,academic_year" });

  if (error) throw error;
  return proofPath;
}

/** A signed link to a stored proof. Expires, so it cannot be shared onward. */
export async function proofUrl(path, seconds = 300) {
  if (!path) return null;
  const { data, error } = await sb.storage
    .from("payment-proofs")
    .createSignedUrl(path, seconds);
  if (error) { console.error(error); return null; }
  return data.signedUrl;
}

export const METHODS = ["whish", "Bank transfer", "OMT", "Cash"];

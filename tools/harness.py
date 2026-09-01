#!/usr/bin/env python3
"""
Build a signed-out-proof preview of the member portal.

The portal pages talk to Supabase, so they cannot be opened or screenshotted
without a real login. This generates site/_harness/, a throwaway copy of the
portal pages wired to fixtures instead, so the layout can be looked at and
iterated on offline. Fixtures are chosen with ?state=paid|unpaid|board.

    python3 tools/harness.py && cd site && python3 -m http.server 8899
    open http://localhost:8899/_harness/account.html?state=paid

It regenerates from the real pages every run, so it cannot drift. Nothing here
is served in production: site/_harness/ is git-ignored.
"""
import os, re, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = os.path.join(ROOT, "site")
OUT = os.path.join(SITE, "_harness")
PAGES = ["account.html", "profile.html", "admin-dues.html"]

FIXTURES = r"""
const STATE = new URLSearchParams(location.search).get("state") || "paid";

const PROFILES = {
  paid:   { id:"u1", full_name:"Riad Jawhar", email:"member@example.org", phone:"76 123 456",
            student_id:"BAU-2201", university:"BAU", academic_year:"4th year", role:"member" },
  unpaid: { id:"u2", full_name:"Lea Haddad", email:"lea@example.org", phone:"",
            student_id:"", university:"LU", academic_year:"2nd year", role:"member" },
  board:  { id:"u3", full_name:"Omar Nasr", email:"treasurer@example.org", phone:"71 998 244",
            student_id:"USJ-1904", university:"USJ", academic_year:"5th year", role:"super_admin" },
};

const MEMBERSHIPS = {
  paid:   [{ academic_year:"2026/2027", status:"paid", method:"whish", paid_on:"2026-09-14", verified_at:"2026-09-15T08:30:00Z" },
           { academic_year:"2025/2026", status:"paid", method:"Cash",  paid_on:"2025-09-20", verified_at:"2025-09-22T09:00:00Z" }],
  unpaid: [],
  board:  [{ academic_year:"2026/2027", status:"pending", method:"whish", created_at:"2026-09-14T10:00:00Z", verified_at:null }],
};

const COUNTS = { paid:[4,2,1], unpaid:[0,0,0], board:[7,3,5] };

/* Rows for the admin pages, which read tables directly rather than going
   through the helpers in portal.js. Deliberately includes one of every status,
   so the Treasurer's view can be judged with a confirmed payment on screen. */
const PEOPLE = [
  { id:"m1", full_name:"Lea Haddad",   email:"lea@example.org",   university:"LU",  academic_year:"2nd year", phone:"70 111 222" },
  { id:"m2", full_name:"Karim Chidiac",email:"karim@example.org", university:"USJ", academic_year:"3rd year", phone:"03 445 118" },
  { id:"m3", full_name:"Nour Fakih",   email:"nour@example.org",  university:"BAU", academic_year:"5th year", phone:"76 902 331" },
  { id:"m4", full_name:"Jad Semaan",   email:"jad@example.org",   university:"BAU", academic_year:"1st year", phone:"" },
];

window.membershipRows = function (year) {
  return [
    { id:"x2", profile_id:"m2", academic_year:year, status:"paid", amount_usd:10,
      method:"OMT", proof_path:"payment-proofs/m2/omt.png", paid_on:"2026-09-12", notes:null,
      created_at:"2026-09-15T14:03:00Z" },
    { id:"x1", profile_id:"m1", academic_year:year, status:"pending", amount_usd:10,
      method:"whish", proof_path:"payment-proofs/m1/whish.png", paid_on:null, notes:null,
      created_at:"2026-09-11T09:12:00Z" },
    { id:"x3", profile_id:"m3", academic_year:year, status:"rejected", amount_usd:10,
      method:"Bank transfer", proof_path:null, paid_on:null,
      notes:"The screenshot did not show the transfer reference. Please send one that does.",
      created_at:"2026-09-10T18:40:00Z" },
    { id:"x4", profile_id:"m4", academic_year:year, status:"unpaid", amount_usd:10,
      method:null, proof_path:null, paid_on:null, notes:null,
      created_at:"2026-09-09T11:25:00Z" },
  ];
};

window.__FIXTURE = {
  session: { user: { id: PROFILES[STATE].id, email: PROFILES[STATE].email } },
  profile: PROFILES[STATE],
  memberships: MEMBERSHIPS[STATE],
  adminMemberships: [],   // filled by the stub once duesYear() is known
};

/* A stand-in for the supabase-js client. It answers the handful of chains the
   portal pages actually use and resolves to canned counts. */
const counts = COUNTS[STATE];
let served = 0;
function thenable(result) {
  const chain = new Proxy(function () {}, {
    get(_, prop) {
      if (prop === "then") return (res) => res(result);
      return () => chain;
    },
    apply() { return chain; },
  });
  return chain;
}
window.supabase = {
  createClient() {
    return {
      auth: {
        getSession: async () => ({ data: { session: window.__FIXTURE.session } }),
        signOut:    async () => ({ error: null }),
        updateUser: async () => ({ error: null }),
        onAuthStateChange: () => ({ data: { subscription: { unsubscribe(){} } } }),
      },
      from(table) {
        if (table === "profiles")    return thenable({ data: PEOPLE, error: null, count: PEOPLE.length });
        if (table === "memberships") return thenable({ data: window.__FIXTURE.adminMemberships, error: null, count: 4 });
        return thenable({ data: [], error: null, count: counts[served++ % counts.length] });
      },
      rpc: async () => ({ data: null, error: null }),
      storage: { from: () => thenable({ data: { path: "x" }, error: null }) },
    };
  },
};
"""

STUB = """/* Generated by tools/harness.py. Do not edit. */
import * as real from "../js/portal.js";

export const { sb, signOut, signIn, signUp, getSession, requestPasswordReset,
  updatePassword, resendConfirmation, passwordProblem, authMessage, ROLE_LABEL,
  isAdmin, isStaff, isCommitteeHead, currentAcademicYear, duesYear, DUES_LABEL,
  isPaidUp, fmtDate, escapeHtml, say, submitPayment, proofUrl, METHODS,
  SUPABASE_URL, SUPABASE_KEY } = real;

export async function requireAuth()   { return window.__FIXTURE.session; }
export async function getProfile()    { return window.__FIXTURE.profile; }
/* The fixture's newest row is stamped with whatever duesYear() says today, so
   the "paid" state stays paid as the academic year rolls over. */
/* admin-dues.html filters on the current academic year, so the fixture rows are
   stamped with whatever duesYear() says today rather than a hardcoded string. */
window.__FIXTURE.adminMemberships = window.membershipRows
  ? window.membershipRows(real.duesYear()) : [];

export async function getMemberships(){
  const rows = window.__FIXTURE.memberships;
  return rows.length ? [{ ...rows[0], academic_year: real.duesYear() }, ...rows.slice(1)] : rows;
}
"""


def build():
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT)
    open(os.path.join(OUT, "portal-stub.js"), "w", encoding="utf-8").write(STUB)

    for page in PAGES:
        html = open(os.path.join(SITE, page), encoding="utf-8").read()
        # the real client never loads here; the fixture script installs a stand-in
        html = html.replace('<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>',
                            "<script>\n" + FIXTURES + "\n</script>")
        html = html.replace('from "./js/portal.js"', 'from "./portal-stub.js"')
        html = re.sub(r'(href|src)="(css|assets|js)/', r'\1="../\2/', html)
        html = html.replace('href="/favicon.ico"', 'href="../favicon.ico"')
        html = html.replace('<meta charset="UTF-8">',
                            '<meta charset="UTF-8">\n<!-- PREVIEW HARNESS. Generated file, not served in production. -->')
        open(os.path.join(OUT, page), "w", encoding="utf-8").write(html)
        print(f"  {page}")

    print(f"Built {len(PAGES)} page(s) into site/_harness/. "
          f"Try ?state=paid, ?state=unpaid, ?state=board")


if __name__ == "__main__":
    build()

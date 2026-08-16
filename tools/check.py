#!/usr/bin/env python3
"""
Pre-flight checks for the LADS site.

Run it before pushing:   python3 tools/check.py

It catches the mistakes that are easy to make and hard to notice:
a typo in a script that stops a whole page working, a link to a page that was
renamed, a secret pasted into a file, or a database file left where the public
web server would serve it.

Exits non-zero on failure, so GitHub Actions fails the build too.
"""
import re, os, sys, glob, subprocess, json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SITE = os.path.join(ROOT, "site")
problems = []
checked = {"pages": 0, "modules": 0, "links": 0}


def rel(p):
    return os.path.relpath(p, ROOT)


# --- 1. Every module script must actually parse -----------------------------
# A syntax error here is silent: the page loads, looks fine, and does nothing.
def check_js():
    have_node = subprocess.run(["which", "node"], capture_output=True).returncode == 0
    if not have_node:
        print("  node not found, skipping JavaScript syntax check")
        return
    for f in sorted(glob.glob(os.path.join(SITE, "*.html"))):
        html = open(f, encoding="utf-8").read()
        for i, code in enumerate(re.findall(r'<script type="module">(.*?)</script>', html, re.S)):
            tmp = "/tmp/_lads_check.mjs"
            open(tmp, "w", encoding="utf-8").write(code)
            r = subprocess.run(["node", "--check", tmp], capture_output=True, text=True)
            checked["modules"] += 1
            if r.returncode:
                problems.append(f"{rel(f)}: script {i} does not parse\n{r.stderr.strip()}")
    for f in sorted(glob.glob(os.path.join(SITE, "js", "*.js"))):
        r = subprocess.run(["node", "--check", f], capture_output=True, text=True)
        checked["modules"] += 1
        if r.returncode:
            problems.append(f"{rel(f)}: does not parse\n{r.stderr.strip()}")


# --- 2. Everything imported from portal.js must exist -----------------------
def check_imports():
    portal = os.path.join(SITE, "js", "portal.js")
    if not os.path.exists(portal):
        problems.append("site/js/portal.js is missing")
        return
    src = open(portal, encoding="utf-8").read()
    exports = set(re.findall(r"export (?:async )?function (\w+)", src))
    exports |= set(re.findall(r"export const (\w+)", src))
    for f in sorted(glob.glob(os.path.join(SITE, "*.html"))):
        html = open(f, encoding="utf-8").read()
        for block in re.findall(r'import\s*\{([^}]*)\}\s*from\s*"\./js/portal\.js"', html, re.S):
            for sym in [s.strip() for s in block.split(",") if s.strip()]:
                if sym not in exports:
                    problems.append(f"{rel(f)}: imports '{sym}', which portal.js does not export")


# --- 3. Internal links must point at pages that exist -----------------------
def check_links():
    pages = {os.path.basename(p) for p in glob.glob(os.path.join(SITE, "*.html"))}
    for f in sorted(glob.glob(os.path.join(SITE, "*.html"))):
        checked["pages"] += 1
        html = open(f, encoding="utf-8").read()
        for href in set(re.findall(r'href="([^"#?:]+\.html)[^"]*"', html)):
            checked["links"] += 1
            if href.lstrip("/") not in pages:
                problems.append(f"{rel(f)}: links to {href}, which does not exist")


# --- 4. Nothing sensitive in anything we publish ----------------------------
# The Supabase publishable key is fine and expected. These are not.
# Patterns match the shape of a real key, not the word for it, so that
# documentation can talk about service_role keys without failing the build.
SECRETS = [
    (r"\bre_[A-Za-z0-9_]{20,}", "a Resend API key"),
    (r"service_role[\"'\s:=]+[A-Za-z0-9_.-]{20,}", "a Supabase service_role key"),
    (r"\bsb_secret_[A-Za-z0-9_-]{10,}", "a Supabase secret key"),
    (r"eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.", "a JWT, possibly a service key"),
]


def check_secrets():
    for f in sorted(glob.glob(os.path.join(ROOT, "**", "*"), recursive=True)):
        if not os.path.isfile(f) or "/.git/" in f:
            continue
        if os.path.splitext(f)[1].lower() not in {".html", ".js", ".css", ".json", ".sql", ".md", ".toml", ".txt"}:
            continue
        try:
            text = open(f, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        for pattern, label in SECRETS:
            if re.search(pattern, text):
                problems.append(f"{rel(f)}: looks like it contains {label}. Remove it before pushing.")


# --- 5. Nothing in site/ that should not be served --------------------------
def check_public_surface():
    for f in glob.glob(os.path.join(SITE, "*.sql")):
        problems.append(f"{rel(f)}: SQL files must not be inside site/. "
                        "Anything in there is downloadable from the website. Move it to db/.")
    robots = os.path.join(SITE, "robots.txt")
    if os.path.exists(robots):
        text = open(robots, encoding="utf-8").read()
        for private in ["account.html", "login.html", "signup.html", "admin-"]:
            if private not in text:
                problems.append(f"site/robots.txt does not disallow {private}")
    else:
        problems.append("site/robots.txt is missing")


for fn in (check_js, check_imports, check_links, check_secrets, check_public_surface):
    fn()

print(f"Checked {checked['pages']} pages, {checked['modules']} scripts, {checked['links']} links.")
if problems:
    print(f"\n{len(problems)} problem(s):\n")
    for p in problems:
        print("  - " + p)
    sys.exit(1)
print("All checks passed.")

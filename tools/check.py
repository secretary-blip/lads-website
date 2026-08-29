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


# --- 6. Every page carries the shared chrome --------------------------------
# join.html once shipped without its </main>, its whole footer, and the theme
# script. Every other page had all three. Nothing here caught it: links and
# scripts were valid, so the page passed while ending in a void and leaving the
# theme toggle dead on that page only. Structure is not visible to a link check,
# so check it directly.
CHROME = [
    (r"<header[\s>]",          "a <header>"),
    (r"<main[\s>]",            "an opening <main>"),
    (r"</main>",               "its closing </main>"),
    (r"<footer[\s>]",          "a <footer>"),
    (r"</footer>",             "its closing </footer>"),
]


def check_page_chrome():
    for f in sorted(glob.glob(os.path.join(SITE, "*.html"))):
        html = open(f, encoding="utf-8").read()
        for pattern, label in CHROME:
            n = len(re.findall(pattern, html))
            if n == 0:
                problems.append(f"{rel(f)}: is missing {label}. "
                                "Copy the block from index.html so the page matches the others.")
            elif n > 1 and label != "a <footer>":
                problems.append(f"{rel(f)}: has {n} of {label}, expected one.")

        # The toggle button and the code that drives it have to travel together.
        has_button = 'id="themeBtn"' in html
        has_script = "getElementById('themeBtn')" in html or 'getElementById("themeBtn")' in html
        if has_button and not has_script:
            problems.append(f"{rel(f)}: has the theme toggle button but not the script that "
                            "runs it, so the button does nothing on this page. "
                            "Copy the <script> from the bottom of index.html.")
        if has_script and not has_button:
            problems.append(f"{rel(f)}: has the theme script but no #themeBtn for it to bind to.")


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


for fn in (check_js, check_imports, check_links, check_secrets,
           check_public_surface, check_page_chrome):
    fn()


# --- 7. const arrow helpers used before they exist --------------------------
# `function f(){}` hoists. `const f = () => {}` does not: until that line runs,
# touching f throws "Cannot access 'f' before initialization". These pages use
# top-level await, so a lot of code runs before the bottom of the file is
# reached, and the failure looks like a blank page rather than an error.
def check_tdz():
    for f in sorted(glob.glob(os.path.join(SITE, "*.html"))):
        html = open(f, encoding="utf-8").read()
        m = re.search(r'<script type="module">(.*?)</script>', html, re.S)
        if not m:
            continue
        js = m.group(1)
        awaits = [x.start() for x in re.finditer(r"\bawait\b", js)]
        if not awaits:
            continue
        last_await = max(awaits)
        for d in re.finditer(r"^const (\w+)\s*=\s*(?:\([^)]*\)|\w+)\s*=>", js, re.M):
            name = d.group(1)
            if d.start() > last_await and re.search(r"\b" + name + r"\s*\(", js[:last_await]):
                problems.append(
                    f"{rel(f)}: '{name}' is a const arrow declared after top-level await, "
                    "but is called before it. Use a function declaration.")


check_tdz()


print(f"Checked {checked['pages']} pages, {checked['modules']} scripts, {checked['links']} links.")
if problems:
    print(f"\n{len(problems)} problem(s):\n")
    for p in problems:
        print("  - " + p)
    sys.exit(1)
print("All checks passed.")

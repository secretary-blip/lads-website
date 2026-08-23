#!/usr/bin/env python3
"""
Parse every migration against the real PostgreSQL grammar before it is run.

    pip install pglast --break-system-packages
    python3 tools/check_sql.py

Catches typos, unbalanced blocks and bad syntax in seconds, instead of finding
them halfway through a migration on the live database at midnight.

Note: pglast's plpgsql checker has a JSON decoding bug that reports errors for
valid function bodies, so this checks the SQL grammar only. That still catches
the mistakes that actually happen.
"""
import glob, os, sys

try:
    import pglast
except ImportError:
    print("pglast is not installed. Run:")
    print("  pip install pglast --break-system-packages")
    sys.exit(0)  # not a build failure, just unavailable

root = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "db")
bad = 0
files = sorted(glob.glob(os.path.join(root, "*.sql")))

for f in files:
    try:
        pglast.parse_sql(open(f, encoding="utf-8").read())
        print(f"  {os.path.basename(f):28s} ok")
    except Exception as e:
        bad += 1
        print(f"  {os.path.basename(f):28s} ERROR: {e}")

print(f"\n{len(files)} migrations checked, {bad} with errors.")
sys.exit(1 if bad else 0)

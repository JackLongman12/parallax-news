#!/usr/bin/env python3
"""List crash reports from the Parallax News worker.

    python tool/crashes.py          # all crash groups, newest first
    python tool/crashes.py <id>     # one group with its full stack trace

Reads the admin token from secrets/worker_admin_token.txt (git-ignored).
"""
import datetime
import json
import pathlib
import sys
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORKER = "https://parallax-news.lp-reports.workers.dev"


def main():
    token = (ROOT / "secrets/worker_admin_token.txt").read_text().strip()
    q = {"id": sys.argv[1]} if len(sys.argv) > 1 else {}
    req = urllib.request.Request(f"{WORKER}/crashes?{urllib.parse.urlencode(q)}",
                                 headers={"User-Agent": "parallax-crash-reader/1.0", "Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=20) as r:
        data = json.load(r)
    if "id" in q:
        print(json.dumps(data, indent=2))
        return
    print(f"{data['count']} crash groups")
    for c in data["crashes"]:
        when = datetime.datetime.fromtimestamp(c.get("last", 0)).strftime("%Y-%m-%d %H:%M")
        print(f"{c['id']}  x{c.get('count', 1):<4} {when}  v{c.get('version', '?'):<12} {c.get('error', '')[:90]}")


if __name__ == "__main__":
    main()

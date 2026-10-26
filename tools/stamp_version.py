#!/usr/bin/env python3
"""Stamp game/version.json with the build's version, commit and time.

The version comes from `config/version` in game/project.godot (the single
source of truth); the commit is the short git SHA of HEAD (or "dev" outside a
git checkout); built_at is an ISO-8601 UTC timestamp. Re-running is safe: the
file is rewritten in full each time.

The committed default is {"version": "0.1.0", "commit": "dev", "built_at": ""}.
Restore it after a local stamp with:
    python3 tools/stamp_version.py --reset

Usage (from anywhere):
    python3 tools/stamp_version.py [--commit SHA] [--built-at ISO] [--reset]
"""
import argparse
import datetime
import json
import os
import re
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.join(ROOT, "game", "project.godot")
OUT = os.path.join(ROOT, "game", "version.json")
DEFAULT_VERSION = "0.1.0"


def project_version() -> str:
    try:
        with open(PROJECT, encoding="utf-8") as handle:
            for line in handle:
                match = re.match(r'^config/version="([^"]*)"', line.strip())
                if match:
                    return match.group(1)
    except OSError:
        pass
    return DEFAULT_VERSION


def git_short_sha() -> str:
    try:
        out = subprocess.run(
            ["git", "-C", ROOT, "rev-parse", "--short=7", "HEAD"],
            check=True, capture_output=True, text=True,
        )
        sha = out.stdout.strip()
        return sha if sha else "dev"
    except (OSError, subprocess.CalledProcessError):
        return "dev"


def write(data: dict) -> None:
    with open(OUT, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--commit", help="override the commit (default: git short SHA)")
    parser.add_argument("--built-at", help="override the timestamp (default: now, UTC)")
    parser.add_argument("--reset", action="store_true",
                        help="write the committed dev default instead")
    args = parser.parse_args()
    if args.reset:
        data = {"version": project_version(), "commit": "dev", "built_at": ""}
    else:
        built_at = args.built_at or datetime.datetime.now(datetime.timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ")
        data = {
            "version": project_version(),
            "commit": args.commit or git_short_sha(),
            "built_at": built_at,
        }
    write(data)
    print(f"stamped {os.path.relpath(OUT, ROOT)}: {json.dumps(data)}")


if __name__ == "__main__":
    main()

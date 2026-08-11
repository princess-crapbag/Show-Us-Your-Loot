#!/usr/bin/env python3
"""Show Us Your Loot — uploader.

Watches the addon's SavedVariables file and pushes it to Supabase whenever it
changes. WoW writes that file on /reload and at logout, so "live" means
"within a reload" — never mid-pull.

Setup once:

    python syl_upload.py --configure

Then leave it running:

    python syl_upload.py

Nothing is sent until it is configured, and the only destination is the URL
you give it. Standard library only: no pip install.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

CONFIG_PATH = Path.home() / ".syl-upload.json"
POLL_SECONDS = 10
DEFAULT_SAVEDVARS = (
    r"C:\Program Files (x86)\World of Warcraft\_retail_\WTF"
    r"\Account\<ACCOUNT>\SavedVariables\ShowUsYourLoot.lua"
)

NUMBER_CHARS = set("-+0123456789.eExXaAbBcCdDfF")


# ---------------------------------------------------------------------------
# Lua SavedVariables parser
# ---------------------------------------------------------------------------

class LuaParser:
    """Parses the subset of Lua that WoW writes: nested tables of scalars.

    Not a general Lua parser, and deliberately so — it only has to read one
    known file shape.
    """

    def __init__(self, text: str) -> None:
        self.text = text
        self.i = 0
        self.n = len(text)

    def skip(self) -> None:
        while self.i < self.n:
            c = self.text[self.i]
            if c in " \t\r\n":
                self.i += 1
                continue
            if c == "-" and self.text.startswith("--", self.i):
                nl = self.text.find("\n", self.i)
                self.i = self.n if nl == -1 else nl
                continue
            break

    def string(self) -> str:
        quote = self.text[self.i]
        self.i += 1
        out: list[str] = []
        while self.i < self.n:
            c = self.text[self.i]
            if c == "\\":
                nxt = self.text[self.i + 1]
                out.append({"n": "\n", "t": "\t", "r": "\r"}.get(nxt, nxt))
                self.i += 2
                continue
            if c == quote:
                self.i += 1
                break
            out.append(c)
            self.i += 1
        return "".join(out)

    def value(self):
        self.skip()
        c = self.text[self.i]
        if c in "\"'":
            return self.string()
        if c == "{":
            return self.table()
        for word, result in (("true", True), ("false", False), ("nil", None)):
            if self.text.startswith(word, self.i):
                self.i += len(word)
                return result
        j = self.i
        while j < self.n and self.text[j] in NUMBER_CHARS:
            j += 1
        raw = self.text[self.i:j]
        self.i = j
        try:
            return float(raw) if any(ch in raw for ch in ".eE") else int(raw)
        except ValueError:
            return raw

    def table(self):
        self.i += 1
        obj: dict = {}
        arr: list = []
        is_array = True

        while True:
            self.skip()
            if self.i >= self.n:
                break
            c = self.text[self.i]
            if c == "}":
                self.i += 1
                break
            if c == ",":
                self.i += 1
                continue

            if c == "[":
                self.i += 1
                self.skip()
                key = self.value()
                self.skip()
                if self.text[self.i] == "]":
                    self.i += 1
                self.skip()
                if self.text[self.i] == "=":
                    self.i += 1
                val = self.value()
                if isinstance(key, int):
                    while len(arr) < key:
                        arr.append(None)
                    arr[key - 1] = val
                else:
                    is_array = False
                    obj[key] = val
                continue

            j = self.i
            while j < self.n and re.match(r"[A-Za-z0-9_]", self.text[j]):
                j += 1
            if j > self.i and re.match(r"\s*=", self.text[j:j + 3]):
                key = self.text[self.i:j]
                self.i = j
                self.skip()
                if self.text[self.i] == "=":
                    self.i += 1
                obj[key] = self.value()
                is_array = False
                continue

            arr.append(self.value())

        if is_array and not obj:
            return [v for v in arr if v is not None]
        for index, val in enumerate(arr):
            if val is not None:
                obj[index + 1] = val
        return obj


def parse_savedvariables(text: str) -> dict:
    marker = text.find("ShowUsYourLootDB")
    if marker == -1:
        raise ValueError("ShowUsYourLootDB not found — is this the right file?")
    brace = text.find("{", marker)
    if brace == -1:
        raise ValueError("ShowUsYourLootDB has no table body.")
    parser = LuaParser(text)
    parser.i = brace
    return parser.table()


# ---------------------------------------------------------------------------
# Shaping
# ---------------------------------------------------------------------------

def as_list(value) -> list:
    """WoW arrays come back as lists, or dicts with integer keys when sparse."""
    if not value:
        return []
    if isinstance(value, list):
        return [v for v in value if v is not None]
    if isinstance(value, dict):
        keys = [k for k in value if isinstance(k, int)]
        return [value[k] for k in sorted(keys) if value[k] is not None]
    return []


def roster_as_list(roster) -> list:
    """Sessions store the roster keyed by GUID; the API wants a list."""
    if isinstance(roster, dict):
        return [v for v in roster.values() if isinstance(v, dict)]
    return as_list(roster)


def build_payload(db: dict) -> dict:
    seasons = []

    def convert(season: dict, active: bool) -> dict:
        raids = []
        for session in as_list(season.get("raids")):
            session = dict(session)
            session["roster"] = roster_as_list(session.get("roster"))
            session["encounters"] = as_list(session.get("encounters"))
            raids.append(session)

        drops = []
        for drop in as_list(season.get("drops")):
            drop = dict(drop)
            drop["rolls"] = as_list(drop.get("rolls"))
            drops.append(drop)

        return {
            "id": season.get("id"),
            "name": season.get("name") or "Unnamed season",
            "active": active,
            "startedAt": season.get("startedAt"),
            "archivedAt": season.get("archivedAt"),
            "drops": drops,
            "raids": raids,
            "loot": [],
        }

    active = db.get("activeSeason")
    if isinstance(active, dict):
        seasons.append(convert(active, True))

    for season in as_list(db.get("archives")):
        if isinstance(season, dict):
            seasons.append(convert(season, False))

    return {
        "schemaVersion": 1,
        "exportedAt": int(time.time()),
        "exportedBy": "uploader",
        "seasons": seasons,
    }


# ---------------------------------------------------------------------------
# Config and transport
# ---------------------------------------------------------------------------

def normalize_url(raw: str) -> str:
    """Reduce whatever was pasted to scheme://host.

    Two things people paste that are not the API root: the Data API URL,
    which already ends in /rest/v1, and the dashboard URL, which looks like
    supabase.com/dashboard/project/<ref>. Appending our own path to either
    produces a 404 from PostgREST, so both are handled here rather than
    left as a puzzle.
    """
    raw = (raw or "").strip().rstrip("/")
    if not raw:
        return raw

    if "://" not in raw:
        raw = "https://" + raw

    parts = urllib.parse.urlparse(raw)

    # Dashboard link: pull the project ref out of the path.
    if parts.netloc.endswith("supabase.com") and "/project/" in parts.path:
        segments = [s for s in parts.path.split("/") if s]
        if "project" in segments:
            ref = segments[segments.index("project") + 1]
            return f"https://{ref}.supabase.co"

    # Anything else: keep scheme and host, discard the path.
    return f"{parts.scheme}://{parts.netloc}"


def load_config() -> dict:
    if CONFIG_PATH.exists():
        return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    return {}


def configure() -> dict:
    print("Show Us Your Loot uploader setup")
    print("Values are stored in", CONFIG_PATH)
    print()

    existing = load_config()

    def ask(label: str, key: str, default: str = "") -> str:
        current = existing.get(key, default)
        shown = f" [{current}]" if current else ""
        answer = input(f"{label}{shown}: ").strip()
        return answer or current

    config = {
        "savedvariables": ask(
            "Path to ShowUsYourLoot.lua", "savedvariables", DEFAULT_SAVEDVARS
        ),
        "supabase_url": normalize_url(ask(
            "Supabase project URL (https://xxxx.supabase.co)", "supabase_url"
        )),
        "anon_key": ask("Supabase anon key", "anon_key"),
        "guild_key": ask("Your guild key (the shared secret)", "guild_key"),
    }

    CONFIG_PATH.write_text(json.dumps(config, indent=2), encoding="utf-8")

    # The anon key is public by design, but the guild key is not.
    try:
        os.chmod(CONFIG_PATH, 0o600)
    except OSError:
        pass

    print("\nSaved. Run without --configure to start watching.")
    return config


def endpoint(config: dict) -> str:
    return normalize_url(config["supabase_url"]) + "/rest/v1/rpc/syl_upload"


def upload(config: dict, payload: dict) -> dict:
    url = endpoint(config)

    body = json.dumps({
        "p_key": config["guild_key"],
        "p_payload": payload,
    }).encode("utf-8")

    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "apikey": config["anon_key"],
            "Authorization": "Bearer " + config["anon_key"],
        },
    )

    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8") or "{}")


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

def push_once(config: dict, path: Path) -> bool:
    text = path.read_text(encoding="utf-8", errors="replace")
    payload = build_payload(parse_savedvariables(text))

    counts = sum(len(s["drops"]) for s in payload["seasons"])
    nights = sum(len(s["raids"]) for s in payload["seasons"])

    try:
        result = upload(config, payload)
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:300]
        print(f"  upload failed ({error.code}): {detail}")
        return False
    except urllib.error.URLError as error:
        print(f"  upload failed: {error.reason}")
        return False

    print(f"  sent {counts} drops and {nights} raid nights -> {result}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configure", action="store_true")
    parser.add_argument("--once", action="store_true",
                        help="upload once and exit")
    parser.add_argument("--check", action="store_true",
                        help="show what it will do, send nothing")
    args = parser.parse_args()

    config = configure() if args.configure else load_config()

    missing = [k for k in ("savedvariables", "supabase_url", "anon_key",
                           "guild_key") if not config.get(k)]
    if missing:
        print("Not configured yet. Run with --configure.")
        print("Missing:", ", ".join(missing))
        return 1

    if args.check:
        print("SavedVariables :", config["savedvariables"])
        print("Project URL    :", normalize_url(config["supabase_url"]))
        print("Will POST to   :", endpoint(config))
        print("API key        :", config["anon_key"][:14] + "…")
        print("Guild key      :", "*" * len(config["guild_key"]))
        if config["anon_key"].startswith("sb_secret"):
            print()
            print("  WARNING: that is a secret key. It bypasses row "
                  "level security. Use the publishable or anon key.")
        return 0

    path = Path(config["savedvariables"])
    if not path.exists():
        print("SavedVariables file not found:", path)
        print("Log into the character once so WoW writes it.")
        return 1

    if args.once:
        return 0 if push_once(config, path) else 1

    print("Watching", path)
    print("WoW writes this on /reload and at logout. Ctrl+C to stop.\n")

    last_stamp = None

    try:
        while True:
            stamp = path.stat().st_mtime
            if stamp != last_stamp:
                # A moment's grace: WoW may still be mid-write.
                time.sleep(1.5)
                print(time.strftime("%H:%M:%S"), "file changed")
                if push_once(config, path):
                    last_stamp = stamp
            time.sleep(POLL_SECONDS)
    except KeyboardInterrupt:
        print("\nStopped.")

    return 0


if __name__ == "__main__":
    sys.exit(main())

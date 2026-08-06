#!/usr/bin/env python3
"""Build the installable addon zip, locally, without CurseForge.

CurseForge is for strangers. Handing the addon to one officer is a zip and a
sentence, and waiting on an approval queue to do that would be silly.

The zip is laid out the way WoW expects — a single top level folder named
after the addon, with the .toc inside it — so it drops straight into
Interface/AddOns.

Ignore rules come from .pkgmeta, the same file the CI packager reads, so the
local zip and the published one contain the same thing. That matters more
than it looks: the repository root *is* the addon folder, so anything not
excluded ships, including the Supabase credentials file sitting in the
working directory.

Run: python tools/syl_package.py
"""

from __future__ import annotations

import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PKGMETA = ROOT / ".pkgmeta"
DIST = ROOT / "dist"

# Never shipped regardless of .pkgmeta. These are either build output or
# things no ignore list should have to remember.
ALWAYS_IGNORE = {".git", "dist", "__pycache__"}


def read_ignores() -> set:
    """Pull the ignore list out of .pkgmeta.

    Deliberately not a YAML parser: the file has one list in it, and adding a
    dependency to read four lines would be worse than reading them.
    """
    ignores = set(ALWAYS_IGNORE)

    if not PKGMETA.exists():
        raise SystemExit(".pkgmeta is missing — refusing to guess what ships.")

    in_ignore = False

    for line in PKGMETA.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()

        if stripped.startswith("#") or not stripped:
            continue

        if stripped.startswith("ignore:"):
            in_ignore = True
            continue

        # Any other top level key ends the ignore block.
        if in_ignore and not line.startswith((" ", "\t", "-")):
            in_ignore = False

        if in_ignore and stripped.startswith("- "):
            ignores.add(stripped[2:].strip())

    return ignores


def addon_name() -> str:
    for line in PKGMETA.read_text(encoding="utf-8").splitlines():
        if line.strip().startswith("package-as:"):
            return line.split(":", 1)[1].strip()

    return "ShowUsYourLoot"


def version(name: str) -> str:
    toc = ROOT / f"{name}.toc"
    match = re.search(r"^##\s*Version:\s*(.+)$", toc.read_text(encoding="utf-8"),
                      re.MULTILINE)

    return match.group(1).strip() if match else "0.0.0"


def is_ignored(relative: Path, ignores: set) -> bool:
    # Match a whole path segment, so "web" excludes web/ and everything under
    # it without also catching a file that merely starts with those letters.
    parts = relative.parts

    for index in range(len(parts)):
        if "/".join(parts[: index + 1]) in ignores:
            return True

    return relative.name in ignores


def main() -> int:
    name = addon_name()
    ignores = read_ignores()
    tag = version(name)

    DIST.mkdir(exist_ok=True)
    target = DIST / f"{name}-{tag}.zip"

    shipped, skipped = [], []

    for path in sorted(ROOT.rglob("*")):
        if path.is_dir():
            continue

        relative = path.relative_to(ROOT)

        if is_ignored(relative, ignores):
            skipped.append(relative)
            continue

        shipped.append(relative)

    # A zip with no .toc installs as nothing at all, silently.
    if Path(f"{name}.toc") not in shipped:
        raise SystemExit(f"{name}.toc is not in the ship list — aborting.")

    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for relative in shipped:
            archive.write(ROOT / relative, Path(name) / relative)

    print(f"Built {target.relative_to(ROOT)}")
    print(f"  {len(shipped)} files in, {len(skipped)} left out")
    print()
    print("Shipping:")

    tops = sorted({r.parts[0] for r in shipped})
    for top in tops:
        count = sum(1 for r in shipped if r.parts[0] == top)
        print(f"  {top}" + (f"  ({count} files)" if count > 1 else ""))

    print()
    print("Left out:")
    for relative in sorted({r.parts[0] for r in skipped}):
        print(f"  {relative}")

    return 0


if __name__ == "__main__":
    sys.exit(main())

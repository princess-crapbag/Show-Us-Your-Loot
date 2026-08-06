#!/usr/bin/env python3
"""Static checks for the addon, in place of a Lua interpreter.

There is no Lua on the machine this is developed on, and a mistake here costs
a wipe rather than a stack trace, so these are the checks worth having:

  1. Structural balance   — do/if/for/while/function against end, and brackets,
                            aware of comments, strings and long brackets.
  2. Load order           — every SYL.Module referenced at file scope must be
                            defined by a file the .toc loads earlier.
  3. Missing members      — SYL.Module.Member used but never assigned anywhere.
  4. .toc against disk    — files listed but absent, or present but unlisted.
  5. Size limit           — the project's own 400 line rule.

Run: python tools/syl_check.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOC = ROOT / "ShowUsYourLoot.toc"
MAX_LINES = 400

OPENERS = ("do", "if", "for", "while", "function")
# `end` closes these; `elseif`/`else` do not open or close.
BLOCK_RE = re.compile(r"\b(function|if|do|for|while|end|repeat|until|then|else|elseif)\b")


def strip_code(text: str):
    """Yield the source with comments and string literals blanked out.

    Blanked rather than removed so line numbers stay honest.
    """
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]

        # Long bracket, comment or string: [[ ... ]] or [=[ ... ]=]
        m = re.match(r"(--)?\[(=*)\[", text[i:])
        if m:
            level = m.group(2)
            close = "]" + level + "]"
            end = text.find(close, i + m.end())
            end = n if end == -1 else end + len(close)
            out.append("".join(ch if ch == "\n" else " " for ch in text[i:end]))
            i = end
            continue

        if text.startswith("--", i):
            end = text.find("\n", i)
            end = n if end == -1 else end
            out.append(" " * (end - i))
            i = end
            continue

        if c in "\"'":
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == c or text[j] == "\n":
                    j += 1
                    break
                j += 1
            out.append("".join(ch if ch == "\n" else " " for ch in text[i:j]))
            i = j
            continue

        out.append(c)
        i += 1
    return "".join(out)


def check_structure(path: Path, code: str, problems: list):
    depth = 0
    for lineno, line in enumerate(code.splitlines(), 1):
        for tok in BLOCK_RE.findall(line):
            if tok in ("function", "if", "do", "for", "while"):
                # `for`/`while` are followed by `do`, which would double count.
                if tok in ("for", "while"):
                    continue
                depth += 1
            elif tok == "repeat":
                depth += 1
            elif tok in ("end", "until"):
                depth -= 1
                if depth < 0:
                    problems.append(f"{path.name}:{lineno}: one `end` too many")
                    depth = 0
    if depth:
        problems.append(f"{path.name}: {depth} block(s) never closed by `end`")

    for open_ch, close_ch, name in (("(", ")", "paren"), ("{", "}", "brace"),):
        if code.count(open_ch) != code.count(close_ch):
            problems.append(
                f"{path.name}: unbalanced {name} "
                f"({code.count(open_ch)} open, {code.count(close_ch)} close)"
            )


# Rows are anchored TOPLEFT 16 and TOPRIGHT -34 inside their window, so the
# space a row actually has is the window width less this.
ROW_INSET = 16 + 34

# The main window's list sits inside a scroll frame rather than being anchored
# to the window, so its budget is fixed rather than derived.
SCROLL_USABLE = 748

COLUMN_RE = re.compile(
    r'key\s*=\s*"(\w+)"\s*,\s*label\s*=\s*"[^"]*"\s*,\s*'
    r'width\s*=\s*(\d+)\s*,\s*gap\s*=\s*(\d+)'
)


def check_columns(name: str, code: str, problems: list):
    """Column widths must fit the space they are drawn in.

    Getting this wrong is invisible in review and nearly invisible in game:
    the text just ends in an ellipsis, which reads as a styling choice rather
    than as a column that was never given room. Both list windows shipped
    overflowing because nobody added up the numbers.
    """
    columns = COLUMN_RE.findall(code)

    if not columns:
        return

    width_match = re.search(r"WINDOW_WIDTH\s*=\s*(\d+)", code)

    if width_match:
        budget = int(width_match.group(1)) - ROW_INSET
        needed = sum(int(w) + int(g) for _, w, g in columns)

        if needed > budget:
            problems.append(
                f"{name}: columns need {needed}px but the row has "
                f"{budget}px (window {width_match.group(1)} less "
                f"{ROW_INSET} inset) — over by {needed - budget}"
            )
        return

    # No window of its own: the sets belong to the scrolling main list, and
    # each one is measured separately. Scoped to COLUMN_SETS so the module
    # table itself is not read as a set and every column counted twice.
    sets_match = re.search(r"COLUMN_SETS\s*=\s*\{(.*?)\n\}", code, re.DOTALL)

    if not sets_match:
        return

    for set_name, body in re.findall(
        r"(\w+)\s*=\s*\{(.*?)\n    \},", sets_match.group(1), re.DOTALL
    ):
        entries = COLUMN_RE.findall(body)

        if not entries:
            continue

        needed = sum(int(w) + int(g) for _, w, g in entries)

        if needed > SCROLL_USABLE:
            problems.append(
                f"{name}: column set '{set_name}' needs {needed}px "
                f"but the scroll frame has {SCROLL_USABLE}px — over by "
                f"{needed - SCROLL_USABLE}"
            )


def toc_order() -> list:
    files = []
    for raw in TOC.read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if not raw or raw.startswith("#"):
            continue
        files.append(raw.replace("\\", "/"))
    return files


def main() -> int:
    problems, warnings = [], []
    listed = toc_order()

    on_disk = {
        str(p.relative_to(ROOT)).replace("\\", "/")
        for p in ROOT.rglob("*.lua")
        if ".claude" not in p.parts
    }

    for name in listed:
        if name not in on_disk:
            problems.append(f".toc lists {name}, which is not on disk")
    for name in sorted(on_disk - set(listed)):
        problems.append(f"{name} is on disk but not loaded by the .toc")

    # Members assigned anywhere: SYL.X = / SYL.X.Y = / function SYL.X:Y / .X.Y(
    assigned = set()
    bodies = {}
    for name in listed:
        path = ROOT / name
        if not path.exists():
            continue
        raw = path.read_text(encoding="utf-8", errors="replace")
        code = strip_code(raw)
        bodies[name] = code

        lines = len(code.splitlines())
        if lines > MAX_LINES:
            warnings.append(f"{name}: {lines} lines, over the {MAX_LINES} limit")

        check_structure(path, code, problems)

        # Raw source, not the stripped copy: strip_code blanks the inside of
        # string literals, and the column definitions are mostly strings.
        check_columns(name, raw, problems)

        for m in re.finditer(r"SYL\.([A-Za-z_]\w*)\s*=", code):
            assigned.add(m.group(1))
        for m in re.finditer(r"SYL\.([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*=", code):
            assigned.add(f"{m.group(1)}.{m.group(2)}")
        for m in re.finditer(r"function\s+SYL\.([A-Za-z_]\w*)[.:]([A-Za-z_]\w*)", code):
            assigned.add(m.group(1))
            assigned.add(f"{m.group(1)}.{m.group(2)}")
        for m in re.finditer(r"function\s+SYL[.:]([A-Za-z_]\w*)", code):
            assigned.add(m.group(1))

        # The usual idiom is a local table published onto SYL:
        #     local Guild = {}          SYL.Guild = Guild
        #     function Guild.GetRank()  Guild.CONSTANT = ...
        # so members are attached to the local name, never to SYL.Guild. Map
        # the alias back, or every one of those reads as undefined.
        for m in re.finditer(r"SYL\.([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*$",
                             code, re.MULTILINE):
            module, alias = m.group(1), m.group(2)
            if alias == "nil":
                continue
            for pat in (rf"function\s+{alias}[.:]([A-Za-z_]\w*)",
                        rf"^\s*{alias}\.([A-Za-z_]\w*)\s*="):
                for hit in re.finditer(pat, code, re.MULTILINE):
                    assigned.add(f"{module}.{hit.group(1)}")

        # Members can also arrive as an inline table, `SYL.colors = { addon =
        # ..., reset = ... }`, so read the keys straight out of the literal.
        for m in re.finditer(r"SYL\.([A-Za-z_]\w*)\s*=\s*\{", code):
            depth, j = 0, m.end() - 1
            while j < len(code):
                if code[j] == "{":
                    depth += 1
                elif code[j] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            for key in re.finditer(r"([A-Za-z_]\w*)\s*=", code[m.end():j]):
                assigned.add(f"{m.group(1)}.{key.group(1)}")

    # Referenced members
    for name in listed:
        code = bodies.get(name, "")
        for m in re.finditer(r"SYL\.([A-Za-z_]\w*)[.:]([A-Za-z_]\w*)", code):
            mod, mem = m.group(1), m.group(2)
            if mod not in assigned:
                line = code[:m.start()].count("\n") + 1
                problems.append(f"{name}:{line}: SYL.{mod} is never defined")
            elif f"{mod}.{mem}" not in assigned:
                line = code[:m.start()].count("\n") + 1
                warnings.append(f"{name}:{line}: SYL.{mod}.{mem} never assigned")

    print(f"Checked {len(listed)} files listed in the .toc.\n")
    if problems:
        print(f"PROBLEMS ({len(problems)})")
        for p in problems:
            print("  ", p)
        print()
    if warnings:
        print(f"WARNINGS ({len(warnings)})")
        for w in sorted(set(warnings)):
            print("  ", w)
        print()
    if not problems and not warnings:
        print("Nothing found.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

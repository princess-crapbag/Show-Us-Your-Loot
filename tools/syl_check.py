#!/usr/bin/env python3
"""Static checks for the addon, in place of a Lua interpreter.

There is no Lua on the machine this is developed on, and a mistake here costs
a wipe rather than a stack trace, so these are the checks worth having:

  1. Structural balance   — do/if/for/while/function against end, and brackets,
                            aware of comments, strings and long brackets.
  2. Load order           — every SYL.Module referenced at file scope must be
                            defined by a file the .toc loads earlier.
  3. Missing members      — SYL.Module.Member used but never assigned anywhere.
  4. Bare module globals  — Module.Member where that file never made Module a
                            local. Reads as a nil global at runtime.
  5. .toc against disk    — files listed but absent, or present but unlisted.
  6. Size limit           — the project's own 400 line rule, which a file may
                            opt out of by saying why.

The size rule is a question, not a verdict: "is this file doing more than one
job?". Usually the answer is yes and the fix is to split it. Sometimes it is
no, and then the file should simply be allowed to be long.

What it must never do is cost a comment. Deleting reasoning to get under a
line count makes the code worse to satisfy a number, and that happened twice
before this escape hatch existed. A file opts out with a line in its header:

    -- syl-check: size-exempt — one long table, splitting it would hide it

The reason is required and is printed on every run, so an exemption is a
claim somebody made and can be argued with, rather than a way to go quiet.
An exemption on a file that has since come back under the limit is reported
too, so they do not accumulate.

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


# Read from the raw source, not the stripped copy: strip_code blanks comments
# and the marker lives in one. Header only, so a mention further down — in a
# note about the rule, say — cannot exempt a file by accident.
SIZE_EXEMPT_RE = re.compile(r"--\s*syl-check:\s*size-exempt\b[\s\-—:]*(.*)")
HEADER_LINES = 40


def size_exemption(raw: str):
    """Return (exempt, reason). reason is None when none was given."""
    for line in raw.splitlines()[:HEADER_LINES]:
        match = SIZE_EXEMPT_RE.search(line)
        if match:
            return True, (match.group(1).strip() or None)
    return False, None


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
# to the window. Its budget is the scroll child, created in MainWindow as
# WINDOW_WIDTH - 70, with rows laid out from that child's left edge.
SCROLL_USABLE = 900 - 70

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


# Every way a name becomes local to a file: declarations, function parameters
# and loop variables. Deliberately generous — a name missed here is reported
# as a nil global that is not one, and a checker that cries wolf gets ignored,
# which is worse than the gap it was closing.
LOCAL_RE = re.compile(
    r"\blocal\s+(?:function\s+)?([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)"
)
PARAM_RE = re.compile(r"\bfunction\b[^(\n]*\(([^)]*)\)")
FOR_IN_RE = re.compile(r"\bfor\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s+in\b")
FOR_NUM_RE = re.compile(r"\bfor\s+([A-Za-z_]\w*)\s*=")


def local_names(code: str) -> set:
    names = set()

    for pattern in (LOCAL_RE, FOR_IN_RE, FOR_NUM_RE):
        for m in pattern.finditer(code):
            for part in m.group(1).split(","):
                names.add(part.strip())

    for m in PARAM_RE.finditer(code):
        for part in m.group(1).split(","):
            part = part.strip()
            if part and part != "...":
                names.add(part)

    return names


# A name followed by a dot, not already qualified by one and not a method call
# on something else.
BARE_RE = re.compile(r"(?<![\w.:])([A-Za-z_]\w*)\s*\.")


LOCAL_MEMBER_RE = re.compile(r"(?<![\w.:])([A-Za-z_]\w*)\.([A-Za-z_]\w*)")


def check_local_module_members(
    name: str, code: str, modules: set, assigned: set, problems: list
):
    """`Module.Member` on a file's own local table, where Member is never set.

    `FilterDropdown.ResetSearch(...)` was called and never defined, and every
    filter dropdown threw on click for weeks. Nothing here saw it: check 3
    reads `SYL.Module.Member`, and the bare-globals check above passes it
    because FilterDropdown *is* a local in that file — which is exactly what
    made it look correct.

    So the qualified form is checked against the same member set, which
    already knows what `function Module.Member` and `Module.Member =` assign
    anywhere in the addon.

    Only names published onto SYL are considered. A local table that is not a
    module is nobody's contract and may have members set in ways this cannot
    see.
    """
    locals_here = local_names(code)

    for m in LOCAL_MEMBER_RE.finditer(code):
        module, member = m.group(1), m.group(2)

        if module not in modules or module not in locals_here:
            continue

        # Assignment, not use: `Module.Member = ...` is what defines it.
        after = code[m.end():m.end() + 40].lstrip()

        if after.startswith("=") and not after.startswith("=="):
            continue

        if f"{module}.{member}" not in assigned:
            line = code[:m.start()].count("\n") + 1
            problems.append(
                f"{name}:{line}: {module}.{member} is called but never "
                f"assigned anywhere"
            )


def check_module_globals(name: str, code: str, modules: set, problems: list):
    """Module.Member in a file that never made Module a local.

    Lua resolves that to a global, which is nil, and the failure lands at the
    point of use rather than where the mistake is. Three of these have shipped
    into the working tree: `RaidSession.RaidsOnly(...)` missing its `SYL.`
    prefix, and twice more when a file was split and a function moved away
    from the `local` that named its module.

    The ones that arrive from splitting are the dangerous kind, because they
    sit at file scope and run at load — so the addon does not misbehave, it
    fails to start, and every window goes with it.

    Checks 1-3 could not see any of this: they read `SYL.Module.Member`, and a
    bare `Module.Member` is neither an SYL reference nor an unbalanced block.
    """
    locals_here = local_names(code)

    for m in BARE_RE.finditer(code):
        candidate = m.group(1)

        if candidate in modules and candidate not in locals_here:
            line = code[:m.start()].count("\n") + 1
            problems.append(
                f"{name}:{line}: bare `{candidate}.` — this file never makes "
                f"{candidate} a local, so it is a nil global "
                f"(did you mean SYL.{candidate}?)"
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
    problems, warnings, exemptions = [], [], []
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
    # Just the bare module names, for the bare-global check below.
    modules = set()
    bodies = {}
    for name in listed:
        path = ROOT / name
        if not path.exists():
            continue
        raw = path.read_text(encoding="utf-8", errors="replace")
        code = strip_code(raw)
        bodies[name] = code

        lines = len(code.splitlines())
        exempt, reason = size_exemption(raw)

        if lines > MAX_LINES and not exempt:
            warnings.append(f"{name}: {lines} lines, over the {MAX_LINES} limit")
        elif lines > MAX_LINES and not reason:
            # Opting out without saying why is how the rule quietly stops
            # meaning anything.
            warnings.append(
                f"{name}: claims a size exemption but gives no reason"
            )
        elif exempt and lines > MAX_LINES:
            # ASCII only in this file's own output: the console here is not
            # UTF-8 and an em dash arrives as a replacement character, which
            # reads as a bug in the checker.
            exemptions.append(f"{name}: {lines} lines - {reason}")
        elif exempt:
            warnings.append(
                f"{name}: claims a size exemption but is {lines} lines, "
                f"under the {MAX_LINES} limit, so drop the marker"
            )

        check_structure(path, code, problems)

        # Raw source, not the stripped copy: strip_code blanks the inside of
        # string literals, and the column definitions are mostly strings.
        check_columns(name, raw, problems)

        for m in re.finditer(r"SYL\.([A-Za-z_]\w*)\s*=", code):
            assigned.add(m.group(1))
            modules.add(m.group(1))
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

        check_module_globals(name, code, modules, problems)
        check_local_module_members(name, code, modules, assigned, problems)

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
    # Printed every run rather than only when something is wrong. An
    # exemption nobody sees is an exemption nobody revisits.
    if exemptions:
        print(f"SIZE EXEMPTIONS ({len(exemptions)})")
        for e in sorted(set(exemptions)):
            print("  ", e)
        print()
    if not problems and not warnings:
        print("Nothing found.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

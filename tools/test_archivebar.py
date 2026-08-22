"""Two controls must never be anchored to the same edge.

THE BUG THIS EXISTS FOR, and it is the fourth of its shape in this codebase.
Aimee, on a screenshot: "there seems to b overlapping text". A new "Make
active" button was anchored to the right edge of Merge — and so was "Untick
all", which had been there all along. Both drew in the same place and the label
read as one word of nonsense, "Malbenlotoisvle", because two centered font
strings were interleaved.

HANDOFF already records three of these: a filter strip placed at -170 in one
file with the list top at 210 in another, overlapping by 4px; a drag handle
over the title bar eating the settings cog; a band crossing the tab strip.
Every one is two absolute positions written in two places with nothing
comparing them.

So the rule this file enforces is structural rather than pixel-perfect: in a
row of controls, each one anchors to the one before it, and nothing anchors
twice to the same reference. A chain cannot collide with itself, and adding a
fourth button to a row of three then cannot break the row.

Reads the shipped file rather than a copy of the layout. No `lupa` — this is a
question about the source, not about behavior.

Not shipped: tools/ is excluded in .pkgmeta.
"""
import re
import sys
from pathlib import Path

UI = Path(__file__).resolve().parent.parent / "UI"

failures = []


def check(label, ok, detail=None):
    print(("ok   " if ok else "FAIL ") + label)

    if not ok:
        if detail is not None:
            print("       " + str(detail))

        failures.append(label)


# file, the frame whose children form one horizontal row, and how much room
# that row has across its window.
ROWS = [
    ("ArchiveControls.lua", "bar", 900 - 32),
    ("RosterControls.lua", "frame", 900 - 32),
]

ANCHOR = re.compile(
    r"(\w+)\.(\w+):SetPoint\(\s*\"(LEFT|RIGHT)\"\s*,\s*(\w+)\.(\w+)\s*,"
    r"\s*\"(LEFT|RIGHT)\"\s*,\s*(-?\d+)"
)

for filename, frame, room in ROWS:
    source = (UI / filename).read_text(encoding="utf-8")

    print(filename)

    seen = {}
    chain = []
    clash = None

    for m in ANCHOR.finditer(source):
        owner, child, side, ref_owner, ref_child, ref_side, gap = m.groups()

        if owner != frame or ref_owner != frame:
            continue

        target = (ref_child, ref_side)

        # THE ASSERTION. Two controls anchored to the same edge of the same
        # control are drawn on top of each other, every time.
        if target in seen:
            clash = (seen[target], child, ref_child, ref_side)

        seen[target] = child
        chain.append((child, ref_child, int(gap)))

    check("  a row of controls was found", len(chain) > 0, chain)

    check("  NOTHING IS ANCHORED TWICE TO THE SAME EDGE",
          clash is None,
          clash and "%s and %s both sit at %s's %s edge"
          % (clash[0], clash[1], clash[2], clash[3]))

    # Each link must point at something already placed. A file can hold more
    # than one row — RosterControls has a filter row and a footer row — and
    # the first control of a row anchors to the window corner rather than to a
    # sibling, so anything never seen as a LEFT-anchored child is a row head
    # and is allowed. What is not allowed is pointing forward at something
    # placed later, which leaves the order on screen to the engine.
    children = [child for child, _ref, _gap in chain]
    placed = set()
    broken = []

    for child, ref, _gap in chain:
        if ref in children and ref not in placed:
            broken.append((child, ref))

        placed.add(child)

    check("  each control hangs off one placed before it",
          not broken, broken)

    # And the row has to fit. Widths are declared at creation.
    widths = {}

    for m in re.finditer(
        r"(\w+)\.(\w+)\s*=\s*\n?\s*(?:Theme\.CreateButton\(\w+,\s*(\d+)"
        r"|SYL\.SearchBox\.Create\(\s*\n?\s*\w+,\s*(\w+))", source
    ):
        _owner, child, button_width, box_width = m.groups()

        if button_width:
            widths[child] = int(button_width)
        elif box_width:
            constant = re.search(
                r"local %s = (\d+)" % re.escape(box_width), source
            )
            widths[child] = int(constant.group(1)) if constant else 0

    text_widths = re.findall(r"(\w+)\.(\w+):SetWidth\((\d+)\)", source)

    for _owner, child, width in text_widths:
        widths.setdefault(child, int(width))

    # Per row, not across the file: two rows in one window each get the width.
    rows, current = [], []

    for child, ref, gap in chain:
        if ref not in children:
            if current:
                rows.append(current)

            current = [(ref, 0)]

        current.append((child, gap))

    if current:
        rows.append(current)

    widest = 0

    for row in rows:
        used = sum(widths.get(name, 0) + gap for name, gap in row)
        widest = max(widest, used)

    check("  every row fits across the window",
          widest <= room, "%d used of %d" % (widest, room))

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)

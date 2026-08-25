# -*- coding: utf-8 -*-
"""How wide a string renders in the game's own font, on a machine that has it
and on one that does not.

WHY THIS IS NOT JUST AN IMPORT. tools/mockup_settings_tabs.py measures with
Pillow against frizqt__.ttf at an absolute path inside a Windows WoW install.
That is exactly right for the drawing scripts, which only ever run on Aimee's
machine. It is fatal for a TEST, because the release workflow runs every
tools/test_*.py on a Linux runner before it uploads to CurseForge -- no
Pillow, no WoW, no font. A suite that imports it there does not fail a check;
it crashes at import and takes the release with it.

THREE THINGS I WILL NOT DO ABOUT THAT:

  Ship the font. frizqt__.ttf is Blizzard's, and this repository is public.

  Install Pillow in CI. It would not help -- the font path still does not
  exist on the runner.

  Let the test skip its measurements when the font is missing. Every number
  in tools/test_layout.py comes from a measurement; skip those and the suite
  still prints "ok" while checking nothing. The workflow already says that
  about luaparser, and it is the same trap.

SO THE WIDTHS ARE RECORDED. Run this file with --record on a machine that has
the font; it measures every string the suites ask for and writes them to
font_widths.json, which is committed. Off that machine, measure() reads the
table. A string that is not in the table is an error and not a guess -- so
adding a label without re-recording fails loudly, which is the only safe way
for a table like this to go stale.

    python tools/font_metrics.py --record
"""
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TABLE = os.path.join(HERE, "font_widths.json")

_real = None
_recording = False
_recorded = {}


def _measurer():
    """Pillow and the game font, or None if this machine has neither."""
    global _real

    if _real is not None:
        return _real or None

    try:
        from mockup_settings_tabs import measure
    except Exception:
        _real = False
        return None

    try:
        measure("probe", 10)
    except Exception:
        # Pillow imported but the font is not where it is expected to be.
        _real = False
        return None

    _real = measure

    return _real


def _load():
    if not os.path.exists(TABLE):
        return {}

    return json.load(io.open(TABLE, encoding="utf-8"))


_table = None


def measure(text, size):
    """The rendered width of `text` at `size`, in the addon's own pixels."""
    global _table

    text = str(text)
    key = "%d|%s" % (size, text)

    real = _measurer()

    if real is not None:
        width = real(text, size)

        if _recording:
            _recorded[key] = round(width, 4)

        return width

    if _table is None:
        _table = _load()

    if key not in _table:
        raise KeyError(
            "no recorded width for %r at size %d. This machine has no game "
            "font, so widths come from tools/font_widths.json -- re-record it "
            "on a machine that does:\n\n    python tools/font_metrics.py "
            "--record\n" % (text, size))

    return _table[key]


def available():
    """Whether this machine can measure for real."""
    return _measurer() is not None


def _record():


    # RECORDING HAPPENS ON THE IMPORTED COPY, not on this one. Run as a
    # script this file is `__main__`, and a suite that says `from font_metrics
    # import measure` gets a SECOND module object with its own flag -- so
    # setting it here recorded nothing at all, quietly, and wrote an empty
    # table over a good one.
    sys.path.insert(0, HERE)

    import font_metrics as shared

    if not shared.available():
        print("This machine has no game font, so there is nothing to record.")
        print("Run this on the machine the drawing scripts run on.")

        return 1, {}

    shared._recording = True

    code = 0

    # Importing a suite runs it, and every measurement it takes on the way
    # through is what gets written down. Suites are listed rather than
    # globbed so that adding one is a deliberate decision to record it.
    for name in ("test_layout",):
        print("--- recording " + name)

        try:
            exec(compile(
                io.open(os.path.join(HERE, name + ".py"),
                        encoding="utf-8").read(),
                name + ".py", "exec"), {"__name__": name})
        except SystemExit as stop:
            # The suite's own verdict, not ours.
            code = code or (stop.code or 0)

    return code, shared._recorded


if __name__ == "__main__":
    if "--record" not in sys.argv:
        print(__doc__)
        sys.exit(0)

    result, widths = _record()

    # Never overwrite a good table with an empty one.
    if not widths:
        print("Nothing was recorded, so the table is left alone.")
        sys.exit(1)

    json.dump(dict(sorted(widths.items())),
              io.open(TABLE, "w", encoding="utf-8"),
              indent=0, sort_keys=True, ensure_ascii=False)

    print("wrote %d widths to %s" % (len(widths), TABLE))

    sys.exit(result)

# -*- coding: utf-8 -*-
"""Every width the suite measures is in the recorded table.

WHY THIS FILE EXISTS. This machine has the game font, so tools/font_metrics.py
measures for real and any string works. The GitHub runner does not, so it
answers from tools/font_widths.json and raises KeyError for anything that was
never recorded.

That difference is invisible locally and fatal in CI, and it is not a test
failure that says something is wrong with the addon -- it is the release
stopping at the test step with the packaging never reached. v0.4.5 was tagged
that way: a new boss-loot assertion measured "x12", the table had no entry for
it, and nothing shipped.

Re-record with:

    python tools/font_metrics.py --record

This runs every other suite in a subprocess with SYL_NO_GAME_FONT set, which
is exactly what the runner sees. It is the slowest file in the suite by a
distance -- it runs all the others -- and that is the price of the release not
failing at the last step.

Not shipped: tools/ is excluded in .pkgmeta.
"""
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
failures = []


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        if detail:
            print("       " + str(detail))
        failures.append(label)


# The recursion guard. A child runs with the variable set, so it must not go
# on to spawn every suite again -- including itself.
if os.environ.get("SYL_NO_GAME_FONT"):
    print("ok   (child run, nothing to do)")
    print("")
    print("FAILURES: none")
    sys.exit(0)

environment = dict(os.environ, SYL_NO_GAME_FONT="1")

for suite in sorted(HERE.glob("test_*.py")):
    if suite.name == Path(__file__).name:
        continue

    result = subprocess.run(
        [sys.executable, str(suite)],
        capture_output=True, text=True, env=environment, cwd=str(HERE.parent),
    )

    missing = "no recorded width" in (result.stdout + result.stderr)

    check("%s measures nothing the table is missing" % suite.name,
          not missing,
          "re-record: python tools/font_metrics.py --record")

    # A suite that fails for its own reasons is not this file's business --
    # it runs on its own and reports there. Only the width table is judged
    # here, so a real failure is not counted twice.

print("")
print("FAILURES: " + (str(failures) if failures else "none"))

sys.exit(1 if failures else 0)

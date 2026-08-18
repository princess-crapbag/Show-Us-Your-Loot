"""Ending a season, and the button that did nothing.

THE BUG THIS EXISTS FOR. The Archive Season dialog opened, took a name, and
did nothing at all when Archive was pressed — on two separate clients, on the
last night of a pre-season, which is the one night of the tier when the button
matters. SYL.ArchiveCurrentSeason was never at fault: driven directly it seals
the season and starts the next one correctly. The break was between the button
and the handler, inside Blizzard's StaticPopup.

WHY IT WAS INVISIBLE. A StaticPopup's OnAccept cannot be called from this
harness by any route — there is no frame, no popup system, and nothing to
click. So the single action that ends a tier had no coverage at all while
every suite stayed green, and the only way to find out was for two people to
try it on the night.

So the dialog is an ordinary addon window now, and the part that matters is a
function with no frame in it. Confirm is what the button calls and what this
file calls, which is the whole point: they cannot drift.

WHAT IS ASSERTED BEYOND "IT ARCHIVES". Naming is the other half. `/syl archive
<name>` names the season being *started*, not the one being closed, and it has
caught Aimee twice — once leaving the active season called "Season 1 tail".
The dialog says which is which, so the wording is asserted here too: a message
that stops saying it is a message that stops preventing the mistake.

Needs `lupa` — see tools/test_lootmessages.py for the setup.

Not shipped: tools/ is excluded in .pkgmeta.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    from lupa import LuaRuntime  # noqa: F401  (imported for the error message)
except ImportError:
    sys.exit(
        "lupa is not installed — see tools/test_lootmessages.py. "
        "It is a dev dependency and the addon does not use it."
    )

import test_load  # noqa: E402  — reuses its stubbed client and loaded addon

lua = test_load.lua
SYL = lua.globals().ShowUsYourLoot
failures = []


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label)
    if not ok:
        if detail:
            print("       " + str(detail))
        failures.append(label)


def reset(season_name="Pre-Season 2", drops=3):
    lua.execute("ShowUsYourLootDB = nil")
    SYL.DatabaseInitialize()
    lua.execute(
        """
        local SYL = ShowUsYourLoot
        local season = SYL.GetActiveSeason()

        season.name = '%s'
        season.drops = season.drops or {}

        for index = 1, %d do
            table.insert(season.drops, {
                id = 'drop' .. index, itemID = index, winnerName = 'Aimee',
            })
        end
        """
        % (season_name, drops)
    )


def archives():
    return list(SYL.GetArchives().values())


# --- THE ONE THIS FILE EXISTS FOR -----------------------------------------
#
# Press Archive with a name in the box. Everything must actually happen.
reset()

archived, new = SYL.ArchivePopup.Confirm("Season 2")

check("PRESSING ARCHIVE ACTUALLY ARCHIVES", archived is not None,
      "Confirm returned nothing — the button would do nothing again")
check("the season that was open is the one sealed",
      archived is not None and archived.name == "Pre-Season 2",
      archived and archived.name)
check("and it kept its drops", len(list(archived.drops.values())) == 3,
      archived and len(list(archived.drops.values())))
check("it is on the archives list", len(archives()) == 1, len(archives()))

# --- the name goes on the NEW season, and only there ----------------------
#
# The trap. Typing "Season 2" means the season starting now is Season 2; the
# one being closed keeps the name it already had.
check("THE TYPED NAME NAMES THE NEW SEASON",
      new is not None and new.name == "Season 2", new and new.name)
check("and the archived one keeps its own name",
      archives()[0].name == "Pre-Season 2", archives()[0].name)
check("which is now the active season",
      SYL.GetActiveSeason().name == "Season 2", SYL.GetActiveSeason().name)
check("and it starts empty, which is the whole reason to archive",
      len(list(SYL.GetActiveSeason().drops.values())) == 0,
      len(list(SYL.GetActiveSeason().drops.values())))

# --- an empty box is a name, not a refusal --------------------------------
#
# Clearing the box and pressing Archive still meant archive. Refusing would be
# the second way this button did nothing.
reset("Tier 1")

archived, new = SYL.ArchivePopup.Confirm("")

check("AN EMPTY NAME STILL ARCHIVES", archived is not None)
check("and the new season gets a default name",
      new is not None and new.name == "New Season", new and new.name)

reset("Tier 1")
archived, new = SYL.ArchivePopup.Confirm("   ")

check("whitespace is empty too", archived is not None and new.name == "New Season",
      new and new.name)

reset("Tier 1")
archived, new = SYL.ArchivePopup.Confirm(None)

check("and so is nothing at all", archived is not None and new.name == "New Season",
      new and new.name)

# --- a typed name is trimmed rather than kept ragged ----------------------
reset("Tier 1")

_, new = SYL.ArchivePopup.Confirm("  Season 2  ")

check("a padded name is trimmed", new.name == "Season 2", repr(new.name))

# --- archiving twice in a row ---------------------------------------------
#
# The season id was unique only to the second once, and archiving then
# starting a new season is one keystroke. Two archives must stay two.
reset("Tier 1")

SYL.ArchivePopup.Confirm("Tier 2")
SYL.ArchivePopup.Confirm("Tier 3")

names = sorted(season.name for season in archives())

check("ARCHIVING TWICE KEEPS BOTH", len(archives()) == 2, len(archives()))
check("and they are the two that were closed, in order",
      names == ["Tier 1", "Tier 2"], names)
check("with the third now active",
      SYL.GetActiveSeason().name == "Tier 3", SYL.GetActiveSeason().name)

ids = [season.id for season in archives()]

check("and the two archives do not share an id", ids[0] != ids[1], ids)

# --- what the dialog says -------------------------------------------------
#
# The wording is the fix for the naming trap, so it is asserted like behaviour.
# A dialog that stops saying which season it is naming stops preventing the
# mistake that has already been made twice.
reset("Pre-Season 2", drops=7)

described = SYL.ArchivePopup.Describe()

check("THE DIALOG NAMES THE SEASON BEING CLOSED",
      "Pre-Season 2" in described, described)
check("and says the box names the NEW one",
      "NEW season" in described, described)
check("and says the archived one is kept rather than lost",
      "kept" in described, described)
check("and counts what is being sealed", "7 drops" in described, described)

reset("Solo", drops=1)

check("one drop is not '1 drops'", "1 drop." in SYL.ArchivePopup.Describe(),
      SYL.ArchivePopup.Describe())

# --- the wiring -----------------------------------------------------------
#
# No behavioural test can see a button that was never connected, and that is
# precisely how this shipped: the handler existed and nothing reached it.
source = (Path(__file__).resolve().parent.parent
          / "UI" / "ArchivePopup.lua").read_text(encoding="utf-8")

check("THE BUTTON CALLS THE SAME FUNCTION THIS FILE DOES",
      "ArchivePopup.Confirm(" in source and "Theme.CreateButton" in source,
      "the dialog's Archive button does not route through Confirm")
# Comments stripped first. The header explains at length what this file used
# to be built on, and a check that could not tell an explanation from a call
# would forbid the file from recording its own history.
code = "\n".join(
    line for line in source.splitlines()
    if not line.lstrip().startswith("--")
)

check("and the dialog no longer depends on the popup system",
      "StaticPopup" not in code,
      "still built on StaticPopupDialogs, which is what could not be tested")

nav = (Path(__file__).resolve().parent.parent
       / "UI" / "MainNav.lua").read_text(encoding="utf-8")

check("and there is still a button on screen to reach it",
      "Archive Season" in nav,
      "UI/MainNav.lua no longer offers a way to archive")

# --- renaming the season that is running ----------------------------------
#
# An archive could be renamed from the Archives tab since v0.3.2. The active
# season could only be renamed with /syl rename — a command nobody has been
# told about, guarding the one name that is typed in a hurry, once, at the
# moment a tier ends.
reset("Seson 2")

renamed, message = SYL.SeasonRenameDialog.Confirm("Season 2")

check("RENAMING THE ACTIVE SEASON WORKS", renamed == "Season 2",
      renamed or message)
check("and the active season carries the new name",
      SYL.GetActiveSeason().name == "Season 2", SYL.GetActiveSeason().name)

# A rename is a label, not a boundary. Nothing recorded may move.
check("and its drops are untouched",
      len(list(SYL.GetActiveSeason().drops.values())) == 3,
      len(list(SYL.GetActiveSeason().drops.values())))

# --- an empty name is refused, not defaulted ------------------------------
#
# The archive dialog fills a blank in, because somebody there is starting a
# season and has to end up with one. This is a correction, and quietly
# substituting "New Season" would be a second wrong name rather than a fix.
for empty in ("", "   ", None):
    renamed, message = SYL.SeasonRenameDialog.Confirm(empty)

    check("an empty rename is refused: " + repr(empty),
          renamed is None and bool(message), (renamed, message))

check("and the name is left alone after a refusal",
      SYL.GetActiveSeason().name == "Season 2", SYL.GetActiveSeason().name)

renamed, _ = SYL.SeasonRenameDialog.Confirm("  Season Two  ")

check("a padded rename is trimmed", renamed == "Season Two", repr(renamed))

# --- renaming the active season leaves the archives alone -----------------
reset("Tier 1")

SYL.ArchivePopup.Confirm("Tier 2")
SYL.SeasonRenameDialog.Confirm("Tier Two")

check("RENAMING THE ACTIVE ONE DOES NOT TOUCH AN ARCHIVE",
      archives()[0].name == "Tier 1", archives()[0].name)
check("and the active season is the one renamed",
      SYL.GetActiveSeason().name == "Tier Two", SYL.GetActiveSeason().name)

# --- the wiring -----------------------------------------------------------
rename_source = (Path(__file__).resolve().parent.parent
                 / "UI" / "SeasonRenameDialog.lua").read_text(encoding="utf-8")

check("the rename dialog routes through the same function this file calls",
      "SeasonRenameDialog.Confirm(" in rename_source
      and "Theme.CreateButton" in rename_source,
      "the Rename button does not go through Confirm")

check("THERE IS A BUTTON ON SCREEN TO REACH IT",
      "Rename Season" in nav,
      "UI/MainNav.lua offers no way to rename the active season")

window = (Path(__file__).resolve().parent.parent
          / "UI" / "MainWindow.lua").read_text(encoding="utf-8")

check("and the window wires that button to the dialog",
      "SeasonRenameDialog.Show" in window,
      "the Rename Season button is not connected to anything")

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)

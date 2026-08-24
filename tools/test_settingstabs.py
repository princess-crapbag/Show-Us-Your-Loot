# -*- coding: utf-8 -*-
"""The five settings tabs, now that all five have their content.

WHAT THIS IS FOR. Three of these tabs were empty or half-drawn when 0.4.0
shipped, and the faults that kind of screen produces do not look like crashes:
a section draws at an offset meant for a layout that no longer exists, a row
runs a command that opens the wrong window, a destructive act ends up one
click from a browsable list. Every one of those reads as normal on screen.

The assertions are grouped by what they are actually protecting:

  THE STRAY NOTE. BuildToggleSection drew its closing paragraph at an offset
  computed for the old single scrolling column and ignored the `top` it was
  given -- so all four tabs that build a toggle section drew that sentence
  244px down their own page, through whatever was there. It shipped in 7efaad7
  with the tabs themselves. Counted rather than eyeballed, because it is
  invisible to any test that only asks whether the section built.

  THE FOUR COMMAND TRAPS. /syl bosses opens the standalone BossWindow, not the
  Bosses tab. /syl roster opens RosterWindow, not the Raiders board. /syl due
  prints unless you append `window`. /syl scope has no click door at all. A
  Tools tab wired naively to the command strings rebuilds three of those and
  fixes none. Driven by running every row and recording where it went.

  /syl clear. It destroys a season, it cannot be undone, and it was once a
  plain row in the minimap menu -- one click, no confirm. The assertion that
  it is absent from the Tools list is the one that must never be deleted to
  make a refactor pass.

Needs `lupa` -- see tools/test_lootmessages.py for the setup.
"""
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, __file__.rsplit("\\", 1)[0])

import test_load  # noqa: E402

lua = test_load.lua
SYL = lua.globals().ShowUsYourLoot

failures = []


def check(name, condition, detail=""):
    if condition:
        print("ok   %s" % name)
    else:
        print("FAIL %s  %s" % (name, detail))
        failures.append(name)


lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()


# --------------------------------------------------------------------------
# Every tab builds, and every one has a height
# --------------------------------------------------------------------------
#
# Called through Create, which is what the window calls, so a builder that
# throws names itself instead of arriving as "settings did not open".

lua.execute("TAB_PARENT = StubFrame()")

try:
    tabs = SYL.SettingsTabs.Create(lua.globals().TAB_PARENT, 560, 110)
    check("the five tabs build", True)
except Exception as error:  # noqa: BLE001
    tabs = None
    check("the five tabs build", False, str(error).split("\n")[0])

if tabs:
    for definition in SYL.SettingsTabs.DEFINITIONS.values():
        key = definition.key

        check("the %s tab exists" % key, tabs.pages[key] is not None)

        # A tab that reported zero would size the window to its chrome alone
        # and read as a screen that failed to load.
        height = tabs.HeightOf(tabs, key)
        check("and reports a real height", height and height > 40,
              "got %r" % height)


# --------------------------------------------------------------------------
# The stray note
# --------------------------------------------------------------------------
#
# Theme.CreateText is wrapped so every string the section draws is recorded.
# Nothing else can see this: the note is a font string on the page, it is not
# a row, and the section returns the same height either way.

# WRAPPED ONCE PER OBJECT, WITH rawget.
#
# The test client hands back the parent frame itself for CreateFontString --
# `frame.CreateFontString` falls through the stub's __index, which rawsets a
# function returning self. So every font string in the suite is the SAME
# table, and a recorder that wrapped SetText on each one nested: after five
# sections the innermost call fired five inserts and every count was a
# multiple of the truth. rawget is needed for the guard because a plain field
# read on that stub answers a function, which is truthy.
lua.execute("""
    DRAWN = {}

    local realCreateText = ShowUsYourLoot.Theme.CreateText

    ShowUsYourLoot.Theme.CreateText = function(parent, size, color, layer)
        local fontString = realCreateText(parent, size, color, layer)

        if not rawget(fontString, "sylRecorded") then
            local realSetText = fontString.SetText

            rawset(fontString, "sylRecorded", true)

            rawset(fontString, "SetText", function(self, text)
                table.insert(DRAWN, tostring(text))
                return realSetText(self, text)
            end)
        end

        return fontString
    end

    function COUNT_DRAWN(needle)
        local found = 0
        for _, text in ipairs(DRAWN) do
            if text:find(needle, 1, true) then found = found + 1 end
        end
        return found
    end
""")

Rows = SYL.SettingsRows
COUNT = lua.globals().COUNT_DRAWN

NEEDLE = "only sees other people's loot"

lua.execute("DRAWN = {}")
Rows.BuildToggleSection(lua.globals().TAB_PARENT, -6, "display", "APPEARANCE")

check("a tabbed toggle section draws no stray paragraph",
      int(COUNT(NEEDLE)) == 0,
      "drew it %d time(s)" % int(COUNT(NEEDLE)))

lua.execute("DRAWN = {}")
Rows.BuildToggleSection(lua.globals().TAB_PARENT)

check("the untabbed one still draws it exactly once",
      int(COUNT(NEEDLE)) == 1,
      "drew it %d time(s)" % int(COUNT(NEEDLE)))

# The sentence is not lost -- the Recording tab says it under CAPTURE.
lua.execute("DRAWN = {}")
lua.execute("RECORDING = StubFrame()")
SYL.SettingsTabs.Create(lua.globals().RECORDING, 560, 110)

check("and the Recording tab says it where it belongs",
      int(COUNT(NEEDLE)) == 1,
      "drew it %d time(s)" % int(COUNT(NEEDLE)))

check("the item-type grid is on that tab too",
      int(COUNT("RECORD THESE ITEM TYPES")) == 1)

check("with the caution on the Scoring tab rather than in a tooltip",
      int(COUNT("re-scores every night already raided")) >= 1)


# --------------------------------------------------------------------------
# The Tools list
# --------------------------------------------------------------------------

GROUPS = SYL.SettingsToolsList.GROUPS


def entries():
    for group in GROUPS.values():
        for entry in group.entries.values():
            yield group.title, entry


allEntries = list(entries())

check("the Tools tab lists something", len(allEntries) > 15,
      "%d rows" % len(allEntries))

check("every row does something",
      all(entry.run is not None for _, entry in allEntries))

# Two words on a row cannot say what pressing it does, and this list is
# somewhere people browse.
check("and every row explains itself on hover",
      all(entry.note for _, entry in allEntries))


# Every row is run with the dispatcher and the tab-opener replaced, so where
# it went is recorded rather than guessed.
lua.execute("""
    RAN_COMMANDS = {}
    OPENED_TABS = {}
    SHOWN_DIALOGS = {}

    SlashCmdList["SHOWUSYOURLOOT"] = function(text)
        table.insert(RAN_COMMANDS, tostring(text))
    end

    ShowUsYourLoot.OpenMainWindowAt = function(_, mode)
        table.insert(OPENED_TABS, tostring(mode))
    end

    for _, name in ipairs({
        "SeasonRenameDialog", "ArchivePopup", "NamePromptDialog",
        "ClearSeasonDialog",
    }) do
        local module = ShowUsYourLoot[name]

        if module then
            module.Show = function()
                table.insert(SHOWN_DIALOGS, name)
            end
        end
    end
""")

G = lua.globals()


def press(label):
    """Runs the row with that label and returns what it reached."""
    lua.execute("RAN_COMMANDS = {}; OPENED_TABS = {}; SHOWN_DIALOGS = {}")

    for _, entry in allEntries:
        text = entry.label() if callable(entry.label) else entry.label

        if str(text).startswith(label):
            entry.run()

            return (list(G.RAN_COMMANDS.values()),
                    list(G.OPENED_TABS.values()),
                    list(G.SHOWN_DIALOGS.values()))

    return None


# TRAP ONE. /syl bosses opens UI/BossWindow.lua, not the tab.
check("Bosses opens the Bosses TAB, not the legacy window",
      press("Bosses") == ([], ["bosses"], []),
      "%r" % (press("Bosses"),))

# TRAP TWO. /syl due prints unless you append `window`.
check("Who is due opens a window rather than printing",
      press("Who is due") == (["due window"], [], []),
      "%r" % (press("Who is due"),))

# TRAP THREE. The Raiders board is the headline screen and had no door of its
# own anywhere in the addon.
check("the Raiders board has a door",
      press("Raiders board") == ([], ["raiders"], []),
      "%r" % (press("Raiders board"),))

# The full roster window is a DIFFERENT screen and keeps its own row, so
# neither one is quietly replaced by the other.
check("and the full roster window keeps its own",
      press("Full roster") == (["roster"], [], []),
      "%r" % (press("Full roster"),))

# TRAP FOUR. /syl scope had no click door anywhere, and it is the setting the
# due and players windows both read.
scoped = press("Who the boards show")
check("scope has a click door at last", scoped == (["scope"], [], []),
      "%r" % (scoped,))

check("and the row says which scope is in force",
      any("Who the boards show:" in str(
              entry.label() if callable(entry.label) else entry.label)
          for _, entry in allEntries))

# Export's only button lived inside a window reachable only by typing
# /syl players, so a feature with a button had no door.
check("export has a door", press("Export for Discord") == (["export"], [], []),
      "%r" % (press("Export for Discord"),))

check("renaming a season opens its dialog",
      press("Rename season") == ([], [], ["SeasonRenameDialog"]),
      "%r" % (press("Rename season"),))

check("archiving opens its dialog",
      press("Archive and start new") == ([], [], ["ArchivePopup"]),
      "%r" % (press("Archive and start new"),))

# The one the RaidersPanel tooltip claimed lived in the roster window.
# IncomingRoster.Add had no caller in UI/ at all.
check("adding a recruit opens a real box rather than prefilling chat",
      press("Add a recruit") == ([], [], ["NamePromptDialog"]),
      "%r" % (press("Add a recruit"),))

check("and so does removing one",
      press("Remove a recruit") == ([], [], ["NamePromptDialog"]),
      "%r" % (press("Remove a recruit"),))


# EVERY COMMAND A ROW DISPATCHES HAS TO EXIST.
#
# A typo here does not throw. The dispatcher hands an unknown word to
# CommandList.UnknownCommand, which prints "There is no /syl expot" into chat
# -- so a misspelled row looks like a working button that quietly does nothing
# but scold you. Read out of the source because COMMANDS is a local in
# Core/SlashCommands.lua and running the real dispatcher would open windows.

sources = "".join(
    test_load.ROOT.joinpath(path).read_text(encoding="utf-8")
    for path in ("Core/SlashCommands.lua", "Core/CommandReports.lua",
                 "Core/AltCommands.lua", "Core/ScheduleCommands.lua")
)

lua.execute("RAN_COMMANDS = {}")

for _, entry in allEntries:
    entry.run()

dispatched = sorted({str(text).split(" ")[0]
                     for text in G.RAN_COMMANDS.values()})

missing = [word for word in dispatched
           if ("COMMANDS." + word) not in sources
           and ('COMMANDS["' + word + '"]') not in sources]

check("every command a Tools row runs actually exists",
      not missing, "missing: %r" % missing)

check("and the rows between them reach a real spread of them",
      len(dispatched) > 10, "%r" % dispatched)


# --------------------------------------------------------------------------
# /syl clear is not in the list
# --------------------------------------------------------------------------
#
# THIS IS THE ASSERTION NOT TO DELETE. Core/CommandList.lua:155-165 records
# what happened the last time this command was a plain row somebody could
# reach while browsing: it emptied a season on one click.

labels = [str(entry.label() if callable(entry.label) else entry.label).lower()
          for _, entry in allEntries]

check("no Tools row clears a season",
      not any("clear" in text or "erase" in text for text in labels),
      "found: %r" % [t for t in labels if "clear" in t or "erase" in t])

lua.execute("RAN_COMMANDS = {}")

for _, entry in allEntries:
    entry.run()

ran = [str(text) for text in G.RAN_COMMANDS.values()]

check("and no Tools row runs it by any other name",
      not any(text.startswith("clear") for text in ran),
      "ran: %r" % [t for t in ran if t.startswith("clear")])


# --------------------------------------------------------------------------
# The guard on the way in
# --------------------------------------------------------------------------

Clear = SYL.ClearSeasonDialog

lua.execute("""
    ShowUsYourLoot.GetActiveSeason = function()
        return { name = "Midnight Season 2", drops = { 1, 2, 3 }, loot = { 1 } }
    end
""")

check("the exact name unlocks it", Clear.Matches("Midnight Season 2"))
check("case is forgiven", Clear.Matches("midnight season 2"))
check("so is stray whitespace", Clear.Matches("  Midnight Season 2  "))

# "confirm" is the word the COMMAND takes, and the reason the dialog does not
# take it is that it can be typed without reading. The name cannot.
check("the word confirm does not", not Clear.Matches("confirm"))
check("nor does a near miss", not Clear.Matches("Midnight Season"))
check("nor does nothing at all", not Clear.Matches(""))
check("nor does the wrong type", not Clear.Matches(None))

lua.execute("RAN_COMMANDS = {}")

ok, message = Clear.Confirm("nonsense")
check("confirming with the wrong name refuses", not ok)
check("and says what to type", message and "name" in message.lower(),
      repr(message))
check("and runs nothing at all", len(list(G.RAN_COMMANDS.values())) == 0)

lua.execute("RAN_COMMANDS = {}")

ok = Clear.Confirm("Midnight Season 2")
check("confirming with the right name goes through", ok)

# IT RUNS THE REAL COMMAND rather than emptying the tables itself. COMMANDS.
# clear also rebuilds the drop index and calls Recovery.NoteDeliberateClear,
# which is account-wide -- a second copy here that forgot the recovery stamp
# would look completely fine until somebody logged in on an alt.
check("by running the real command, guard word and all",
      list(G.RAN_COMMANDS.values()) == ["clear confirm"],
      "%r" % list(G.RAN_COMMANDS.values()))

check("it describes what goes, with the real counts",
      "3 group-loot drops" in Clear.Describe(),
      Clear.Describe()[:80])

check("and says it cannot be undone",
      "cannot be undone" in Clear.Describe())

# The safe path has to be offered, because nearly everybody who reaches this
# screen wanted it and not the other.
check("and points at archiving instead",
      "Archive" in Clear.Describe())


# --------------------------------------------------------------------------
# The name prompt
# --------------------------------------------------------------------------

Prompt = SYL.NamePromptDialog

lua.execute("""
    ACCEPTED = {}

    PROMPT_CONFIG = {
        onAccept = function(typed)
            table.insert(ACCEPTED, typed)
            return true, "took it"
        end,
    }
""")

config = G.PROMPT_CONFIG

ok, message = Prompt.Accept(config, "   Arcangela-Area52 MAGE  ")
check("the name prompt accepts a name", ok)
check("and trims it", list(G.ACCEPTED.values()) == ["Arcangela-Area52 MAGE"],
      "%r" % list(G.ACCEPTED.values()))

lua.execute("ACCEPTED = {}")
ok, message = Prompt.Accept(config, "   ")
check("an empty name is refused", not ok)
check("and nothing is run", len(list(G.ACCEPTED.values())) == 0)


# --------------------------------------------------------------------------
# The number rows
# --------------------------------------------------------------------------
#
# The widget is a frame, so what is tested here is the contract behind it --
# that refusing is a real path and not a clamp, which is the whole reason
# SetWeight returns a boolean.

Score = SYL.LootScore
STATE = SYL.LootHistoryAPI.ROLL_STATE

lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

check("a weight refuses a negative rather than clamping it",
      Score.SetWeight(STATE.NeedMainSpec, -5) is False)

check("and the old value survives the refusal",
      int(Score.WeightOf(STATE.NeedMainSpec)) == 100)

check("the guild threshold refuses over 100",
      SYL.RaidSession.SetGuildThreshold(140) is False)

check("and under 0", SYL.RaidSession.SetGuildThreshold(-1) is False)

check("three weight rows are shown by default",
      len(list(Score.EditableStates().values())) == 3)

Score.SetOffspecSplit(True)

check("and four once offspec is unlinked",
      len(list(Score.EditableStates().values())) == 4)

Score.SetOffspecSplit(False)

print()
print("FAILURES: " + (", ".join(failures) if failures else "none"))
sys.exit(1 if failures else 0)

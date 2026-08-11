"""The settings window builds every section, and fits on a screen.

WHY THIS EXISTS. `AddSection` set `container.heading` one line above the
`local container` that declares it, so `container` was a nil global and the
function threw on its first call. The window drew its title, its subtitle and
one section heading, then nothing — no qualities, no toggles, no features, no
widget list. On screen that read as "the settings screen is empty", not as a
crash, and it survived a clean `syl_check` run because the rule that catches a
local used before its declaration does not exist here. luacheck is the tool for
that class and is still the open tooling item.

Nothing in the suite opened this window, so nothing noticed. This does.

The second half is the size. Every feature added is another 38px of content,
and the window was sized to fit all of it — so it grew past the bottom of the
screen and the last sections became unreachable. It is capped now and the
content scrolls, which is the arrangement that does not need revisiting each
time a feature lands.

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
            print("       " + str(detail).split("\n")[0])
        failures.append(label)


lua.execute("ShowUsYourLootDB = nil")
SYL.DatabaseInitialize()

# --- the sections build ----------------------------------------------------
#
# Called directly rather than through the window, so a failure names the
# section that broke instead of "settings did not open".
lua.execute("SECTION_PARENT = StubFrame()")

parent = lua.globals().SECTION_PARENT

for label, builder in (
    ("the quality section", SYL.SettingsRows.BuildQualitySection),
    ("the behavior section", SYL.SettingsRows.BuildToggleSection),
    ("the feature section", SYL.SettingsRows.BuildFeatureSection),
):
    try:
        builder(parent)
        check(f"{label} builds", True)
    except Exception as err:  # noqa: BLE001 — any Lua error is the finding
        check(f"{label} builds", False, err)

# AddSection hands back the heading as well as the container, and callers that
# rebuild a section need it — the heading is a font string on the parent, not a
# child of the container, so hiding the container alone leaves it behind and
# every rebuild stacks another one in the same place. This is also the exact
# field whose assignment was throwing.
try:
    container, heading = SYL.SettingsRows.AddSection(parent, "TEST", -8)

    check("a section hands back its container", container is not None)
    check("and its heading", heading is not None)
except Exception as err:  # noqa: BLE001
    check("a section hands back its container", False, err)
    check("and its heading", False, err)

# --- the whole window ------------------------------------------------------
try:
    SYL.OpenSettingsWindow(SYL)
    check("the window opens", True)
except Exception as err:  # noqa: BLE001
    check("the window opens", False, err)

# --- it fits ---------------------------------------------------------------
#
# The stubbed UIParent reports 100, so the cap is the floor rather than the
# screen — which is the branch worth checking anyway: a tiny screen must not
# produce a window shorter than its own chrome.
content = SYL.SettingsRows.ContentHeight()
window = SYL.SettingsRows.WindowHeight()

check("the content is taller than one screenful", content > 400, content)
check("the window is not", window <= content, f"{window} vs {content}")
check("and is still usable rather than collapsed", window >= 320, window)
check("so it has to scroll", SYL.SettingsRows.NeedsScrolling() is True)

# --- and on a real screen it does not ---------------------------------------
#
# THE PHANTOM SCROLL. ContentHeight used to include the footer, which is drawn
# on the window rather than inside the scroll frame — so the scroll child was
# 60px taller than anything in it and the window scrolled past the end of its
# own content, with no bar to explain why.
#
# The assertion that catches it: given room, the viewport is exactly the
# content and there is nothing to scroll to.
lua.execute("UIParent.GetHeight = function() return 900 end")

content = SYL.SettingsRows.ContentHeight()
window = SYL.SettingsRows.WindowHeight()

check(
    "given a real screen, the window fits its content exactly",
    window == content + 124,
    f"{window} vs {content} + 124",
)
check(
    "and there is nothing to scroll",
    SYL.SettingsRows.NeedsScrolling() is False,
)
check("without being taller than the screen", window <= 900 - 80, window)

lua.execute("UIParent.GetHeight = function() return 100 end")

# --- the guild links -------------------------------------------------------
#
# The defaults point at this guild's own page rather than at a site's front
# door, built from region, realm and guild name — all three of which the client
# knows, so it works for anybody who installs the addon rather than only for
# whoever pasted their URLs in.
check(
    "a slug is lowercase and hyphenated",
    SYL.Links.Slug("Twisting Nether") == "twisting-nether",
    SYL.Links.Slug("Twisting Nether"),
)
check(
    "and drops apostrophes",
    SYL.Links.Slug("Cho'gall") == "chogall",
    SYL.Links.Slug("Cho'gall"),
)
check("an empty name has no slug", SYL.Links.Slug("") is None)

# The guild name is NOT slugified — it keeps its spaces and capitals and is
# percent-encoded. Hyphenating it the way a realm is hyphenated produced a URL
# that 404s, which is how this was found.
check(
    "a guild name keeps its capitals and encodes its spaces",
    SYL.Links.Encode("Show Us Your Kitties") == "Show%20Us%20Your%20Kitties",
    SYL.Links.Encode("Show Us Your Kitties"),
)

# The stubbed client is in no guild, so there is no path and the links stay on
# the front pages — which is the fallback that must not break anybody.
lua.execute("ShowUsYourLootDB.links = nil")

urls = [link["url"] for link in SYL.Links.List().values()]

check(
    "with no guild, the links are still valid front pages",
    "https://www.warcraftlogs.com/" in urls and "https://raider.io/" in urls,
    urls,
)

# With a guild, an untouched front page is upgraded and an edited one is not.
lua.execute(
    """
    ShowUsYourLoot.Guild.GetGuildName = function() return 'Show Us Your Kitties' end
    GetRealmName = function() return 'Area 52' end
    GetCurrentRegion = function() return 1 end

    ShowUsYourLootDB.links = {
        { label = 'Warcraft Logs', url = 'https://www.warcraftlogs.com/' },
        { label = 'Raider.IO', url = 'https://raider.io/mine' },
    }
    """
)

moved = SYL.Links.RefreshDefaults()
links = {link["label"]: link["url"] for link in SYL.Links.List().values()}

check("one untouched default was upgraded", moved == 1, moved)

# A link already holding the DERIVED url — which shipped once — is upgraded to
# the known one too. Without this, somebody who reloaded before the guild was
# known would keep the derived link forever while a fresh install got the right
# one: the worst of both.
lua.execute(
    """
    ShowUsYourLootDB.links = {
        {
            label = 'Warcraft Logs',
            url = 'https://www.warcraftlogs.com/guild/us/area-52/Show%20Us%20Your%20Kitties',
        },
    }
    """
)

check("a stale derived link is upgraded as well", SYL.Links.RefreshDefaults() == 1)
check(
    "to the one that cannot be derived",
    SYL.Links.List()[1]["url"]
    == "https://www.warcraftlogs.com/guild/reports-list/733227",
    SYL.Links.List()[1]["url"],
)

lua.execute(
    """
    ShowUsYourLootDB.links = {
        { label = 'Warcraft Logs', url = 'https://www.warcraftlogs.com/' },
        { label = 'Raider.IO', url = 'https://raider.io/mine' },
    }
    """
)

SYL.Links.RefreshDefaults()
links = {link["label"]: link["url"] for link in SYL.Links.List().values()}
# Aimee's guild is in the known table, because Warcraft Logs keys a guild on a
# numeric id nothing in the client exposes. Everybody in that guild gets it
# without doing anything, which is the point — a link she sets on her own
# client never reaches the guildies she hands the addon to.
check(
    "a known guild gets the link that cannot be derived",
    links["Warcraft Logs"]
    == "https://www.warcraftlogs.com/guild/reports-list/733227",
    links["Warcraft Logs"],
)

# And a guild that is NOT in the table gets the derived link rather than
# somebody else's logs. This addon is on CurseForge; a hardcoded URL would
# point every stranger who installs it at Aimee's guild.
lua.execute(
    """
    ShowUsYourLoot.Guild.GetGuildName = function() return 'Some Other Guild' end
    GetRealmName = function() return 'Stormrage' end

    ShowUsYourLootDB.links = nil
    """
)

other = {link["label"]: link["url"] for link in SYL.Links.List().values()}

check(
    "an unknown guild gets its own derived link, not Aimee's",
    other["Warcraft Logs"]
    == "https://www.warcraftlogs.com/guild/us/stormrage/Some%20Other%20Guild",
    other["Warcraft Logs"],
)
check(
    "and raider.io is derived for them too",
    other["Raider.IO"]
    == "https://raider.io/guilds/us/stormrage/Some%20Other%20Guild",
    other["Raider.IO"],
)
check(
    "a link somebody edited is left alone",
    links["Raider.IO"] == "https://raider.io/mine",
    links["Raider.IO"],
)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)

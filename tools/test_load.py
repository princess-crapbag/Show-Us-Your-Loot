"""Every file in the .toc loads, in .toc order, against a stubbed client.

test_syntax proves each file parses. This proves each file *runs* its top
level: a `local Theme = SYL.Theme` where Theme has not been assigned yet, a
module reaching for another module that loads after it, a typo'd global at
file scope. None of those are syntax errors and none of them show up until
the game loads the addon, at which point the error names the line rather than
the ordering mistake that caused it.

WHAT THIS CANNOT DO. The stubs below are the shape of the WoW API, not its
behaviour — frames do nothing, textures record nothing, and no event ever
fires. So this catches load-order and nil-at-load faults and nothing else. A
clean run means the addon will load, not that it will work.

Needs `lupa` — see tools/test_lootmessages.py for the setup.

Not shipped: tools/ is excluded in .pkgmeta.
"""
import sys
from pathlib import Path

try:
    from lupa import LuaRuntime
except ImportError:
    sys.exit(
        "lupa is not installed — see tools/test_lootmessages.py. "
        "It is a dev dependency and the addon does not use it."
    )

ROOT = Path(__file__).resolve().parent.parent

lua = LuaRuntime(unpack_returned_tuples=True)

# A frame that answers any method with another frame, so a chain like
# CreateFrame(...):SetPoint(...):Show() never stops on a nil. Numbers come
# back from the getters that layout code divides by.
lua.execute(
    """
    local function Stub()
        local frame = {}

        setmetatable(frame, {
            __index = function(self, key)
                if key == 'GetWidth' or key == 'GetHeight' then
                    return function() return 100 end
                end

                if key == 'GetRegions' or key == 'GetChildren' then
                    return function() return end
                end

                if key == 'GetStringWidth' then
                    return function() return 40 end
                end

                if key == 'IsShown' or key == 'IsVisible' then
                    return function() return false end
                end

                local value = function(...) return self end

                rawset(self, key, value)

                return value
            end,
        })

        return frame
    end

    _G.StubFrame = Stub

    function CreateFrame() return Stub() end
    function UIParent() end
    UIParent = Stub()

    function GetTime() return 0 end
    function time(t) return 1700000000 end
    date = os.date
    function GetLocale() return 'enUS' end
    function UnitName() return 'Tester' end
    function UnitFullName() return 'Tester', 'Realm' end
    function UnitClass() return 'Mage', 'MAGE' end
    function UnitGUID() return 'Player-1-00000001' end
    function GetRealmName() return 'Realm' end
    function IsInGuild() return false end
    function IsInRaid() return false end
    function IsInGroup() return false end
    function IsInInstance() return false, 'none' end
    function GetInstanceInfo()
        return 'Nowhere', 'none', 0, 'None', 0, 0, false, 0, 0
    end
    function GetRealZoneText() return 'Nowhere' end
    function GetZoneText() return 'Nowhere' end
    function GetNumGuildMembers() return 0 end
    function GetGuildRosterInfo() return nil end
    function GetGuildRosterLastOnline() return 0, 0, 0, 0 end
    function GetGuildInfo() return nil end
    function IsShiftKeyDown() return false end
    function GetChatWindowInfo() return 'General' end
    function UnitGroupRolesAssigned() return 'NONE' end
    function GetNumGroupMembers() return 0 end
    function print() end
    function unpack(t, i, j) return table.unpack(t, i, j) end
    function select(n, ...)
        if n == '#' then return #({...}) end
        return ({...})[n]
    end

    NUM_CHAT_WINDOWS = 10
    DEFAULT_CHAT_FRAME = Stub()
    ChatFrame1 = DEFAULT_CHAT_FRAME
    UISpecialFrames = {}
    SlashCmdList = {}
    LOCALIZED_CLASS_NAMES_MALE = { MAGE = 'Mage' }
    RAID_CLASS_COLORS = {}
    ITEM_QUALITY_COLORS = {}

    C_Item = {
        GetItemInfo = function() return nil end,
        GetItemInfoInstant = function() return nil end,
        GetDetailedItemLevelInfo = function() return nil end,
        GetItemIconByID = function() return nil end,
    }
    C_Timer = { After = function() end, NewTicker = function() return Stub() end }
    C_ChatInfo = {
        SendAddonMessage = function() end,
        RegisterAddonMessagePrefix = function() return true end,
    }
    C_MythicPlus = {
        GetOwnedKeystoneChallengeMapID = function() return nil end,
        GetOwnedKeystoneLevel = function() return nil end,
    }
    C_ChallengeMode = { GetMapUIInfo = function() return 'Somewhere' end }
    C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 86400 end }
    C_GuildInfo = { GuildRoster = function() end }
    C_LootHistory = {}
    C_AddOns = { GetAddOnMetadata = function() return '0.0.0-test' end }
    C_EncounterJournal = {}
    C_WeeklyRewards = {}
    Enum = {}

    -- Font objects. Theme reads GameFontNormal's font at load to find the
    -- path it then reuses everywhere.
    GameFontNormal = Stub()
    GameFontNormal.GetFont = function()
        return 'Fonts/FRIZQT__.TTF', 12, ''
    end

    GameFontHighlightSmall = GameFontNormal
    GameFontNormalSmall = GameFontNormal

    -- The popup registry ArchivePopup adds an entry to at load.
    StaticPopupDialogs = {}
    function StaticPopup_Show() end
    function StaticPopup_Hide() end
    function ChatFrame_OpenChat() end
    """
)

listed = [
    line.strip()
    for line in (ROOT / "ShowUsYourLoot.toc").read_text(encoding="utf-8").splitlines()
    if line.strip().lower().endswith(".lua")
]

failures = []

for entry in listed:
    path = ROOT / entry.replace("\\", "/")
    source = path.read_text(encoding="utf-8")

    # Main.lua takes the addon name and table the way the client passes them.
    wrapped = (
        "local __chunk = ...\n"
        "return function(...) " + source + " end"
    )

    try:
        fn = lua.execute("return function(src, name) return load(src, name) end")(
            "return function(...)\n" + source + "\nend", entry
        )

        if fn is None:
            print(f"FAIL {entry} — did not compile")
            failures.append(entry)
            continue

        fn()("ShowUsYourLoot", lua.globals().ShowUsYourLoot or lua.table())
    except Exception as err:  # noqa: BLE001 — any Lua error is a real finding
        message = str(err).split("\n")[0]
        print(f"FAIL {entry}\n       {message}")
        failures.append(entry)

print()
print(f"loaded {len(listed)} files in .toc order")
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)

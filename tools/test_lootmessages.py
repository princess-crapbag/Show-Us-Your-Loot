"""Locale tests for the loot-line parser in Core/LootMessages.lua.

The first real tests in this project, and they earned their keep immediately:
they caught two bugs that reading the code did not. Blizzard's |4item:items;
directive has one terminator rather than two, so the pattern built from it
matched nothing; and the Korean "you receive" string opens with the item
rather than a literal, so checking the self-phrasings first credited every
raider's loot to whoever was running the addon.

Neither is visible on an English client, which is the point. There is no Lua
interpreter on the dev machine, so this embeds one.

    python -m venv .venv
    .venv/Scripts/python -m pip install lupa
    .venv/Scripts/python tools/test_lootmessages.py

The parsing block is read verbatim out of the addon rather than copied here,
so the test cannot drift away from the code it is testing. Only Utilities is
stubbed. Exits non-zero on failure.

Not shipped: tools/ is excluded in .pkgmeta.
"""
import sys
from pathlib import Path

try:
    from lupa import LuaRuntime
except ImportError:
    sys.exit(
        "lupa is not installed — see the header of this file. "
        "It is a dev dependency and the addon does not use it."
    )

ADDON = Path(__file__).resolve().parent.parent / "Core" / "LootMessages.lua"
source = ADDON.read_text(encoding="utf-8")

START = 'local STRING_SPECIFIER = "\\1"'
END = "-- Exposed for the locale tests"

block = source[source.index(START):source.rindex(END)]
# Drop the trailing comment banner that precedes the end marker.

# The module table is created by the file header, which is outside the block.
block = "local LootMessages = {}\n" + block
block += """
_G.DetermineRecipient = LootMessages.DetermineRecipient
_G.WasCreated = LootMessages.WasCreated
_G.ResetPatterns = function() selfPatterns = nil end
"""

PLAYER = "Aimee-Draenor"

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(f"""
Utilities = {{
    GetPlayerFullName = function() return "{PLAYER}" end,
    NormalizePlayerName = function(name)
        if not name or name == "" then return "Unknown" end
        name = name:gsub("|c%x%x%x%x%x%x%x%x", "")
        name = name:gsub("|r", "")
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        name = name:gsub("[%.,:]+$", "")
        return name
    end,
}}
""")
lua.execute(block)

reset = lua.globals().ResetPatterns
determine = lua.globals().DetermineRecipient
was_created = lua.globals().WasCreated

LINK = "|cffa335ee|Hitem:225578::::::::80:::::|h[Dawn Crystal]|h|r"

# Each locale supplies the globals the client would define, plus the lines the
# client would actually print (directives already resolved).
LOCALES = {
    "enUS": dict(
        LOOT_ITEM_SELF="You receive loot: %s.",
        LOOT_ITEM_SELF_MULTIPLE="You receive loot: %sx%d.",
        LOOT_ITEM="%s receives loot: %s.",
        LOOT_ITEM_MULTIPLE="%s receives loot: %sx%d.",
        LOOT_ITEM_PUSHED_SELF="You receive item: %s.",
        LOOT_ITEM_PUSHED="%s receives item: %s.",
        LOOT_ITEM_CREATED_SELF="You create: %s.",
        _self=f"You receive loot: {LINK}.",
        _other=f"Thrall receives loot: {LINK}.",
        _pushed=f"You receive item: {LINK}.",
        _multiple=f"Thrall receives loot: {LINK}x3.",
        _created=f"You create: {LINK}.",
    ),
    "deDE": dict(
        LOOT_ITEM_SELF="Ihr erhaltet Beute: %s.",
        LOOT_ITEM_SELF_MULTIPLE="Ihr erhaltet Beute: %sx%d.",
        LOOT_ITEM="%s erhält Beute: %s.",
        LOOT_ITEM_MULTIPLE="%s erhält Beute: %sx%d.",
        LOOT_ITEM_PUSHED_SELF="Ihr erhaltet Gegenstand: %s.",
        LOOT_ITEM_PUSHED="%s erhält Gegenstand: %s.",
        LOOT_ITEM_CREATED_SELF="Ihr stellt her: %s.",
        _self=f"Ihr erhaltet Beute: {LINK}.",
        _other=f"Thrall erhält Beute: {LINK}.",
        _pushed=f"Ihr erhaltet Gegenstand: {LINK}.",
        _multiple=f"Thrall erhält Beute: {LINK}x3.",
        _created=f"Ihr stellt her: {LINK}.",
    ),
    "frFR": dict(
        LOOT_ITEM_SELF="Vous recevez le butin : %s.",
        LOOT_ITEM_SELF_MULTIPLE="Vous recevez le butin : %sx%d.",
        LOOT_ITEM="%s reçoit le butin : %s.",
        LOOT_ITEM_MULTIPLE="%s reçoit le butin : %sx%d.",
        LOOT_ITEM_PUSHED_SELF="Vous recevez l'objet : %s.",
        LOOT_ITEM_PUSHED="%s reçoit l'objet : %s.",
        LOOT_ITEM_CREATED_SELF="Vous créez : %s.",
        _self=f"Vous recevez le butin : {LINK}.",
        _other=f"Thrall reçoit le butin : {LINK}.",
        _pushed=f"Vous recevez l'objet : {LINK}.",
        _multiple=f"Thrall reçoit le butin : {LINK}x3.",
        _created=f"Vous créez : {LINK}.",
    ),
    "ruRU": dict(
        LOOT_ITEM_SELF="Ваша добыча: %s.",
        LOOT_ITEM_SELF_MULTIPLE="Ваша добыча: %sx%d.",
        LOOT_ITEM="%s получает добычу: %s.",
        LOOT_ITEM_MULTIPLE="%s получает добычу: %sx%d.",
        LOOT_ITEM_PUSHED_SELF="Вы получаете предмет: %s.",
        LOOT_ITEM_PUSHED="%s получает предмет: %s.",
        LOOT_ITEM_CREATED_SELF="Вы создаете: %s.",
        _self=f"Ваша добыча: {LINK}.",
        _other=f"Thrall получает добычу: {LINK}.",
        _pushed=f"Вы получаете предмет: {LINK}.",
        _multiple=f"Thrall получает добычу: {LINK}x3.",
        _created=f"Вы создаете: {LINK}.",
    ),
    # The one that breaks naive ordering: the self string starts with the item,
    # so its pattern begins with a wildcard.
    "koKR": dict(
        LOOT_ITEM_SELF="%s|1을;를; 획득했습니다.",
        LOOT_ITEM_SELF_MULTIPLE="%s|1을;를; %d개 획득했습니다.",
        LOOT_ITEM="%s님이 %s|1을;를; 획득했습니다.",
        LOOT_ITEM_MULTIPLE="%s님이 %s|1을;를; %d개 획득했습니다.",
        LOOT_ITEM_PUSHED_SELF="%s|1을;를; 받았습니다.",
        LOOT_ITEM_PUSHED="%s님이 %s|1을;를; 받았습니다.",
        LOOT_ITEM_CREATED_SELF="%s|1을;를; 만들었습니다.",
        _self=f"{LINK}을 획득했습니다.",
        _other=f"Thrall님이 {LINK}를 획득했습니다.",
        _pushed=f"{LINK}을 받았습니다.",
        _multiple=f"Thrall님이 {LINK}를 3개 획득했습니다.",
        _created=f"{LINK}을 만들었습니다.",
    ),
    # English plural directive, one terminator and a colon separator.
    "plural directive": dict(
        LOOT_ITEM_SELF="You receive |4item:items; %s.",
        LOOT_ITEM="%s receives |4item:items; %s.",
        LOOT_ITEM_PUSHED_SELF="You receive |4item:items; %s.",
        LOOT_ITEM_PUSHED="%s receives |4item:items; %s.",
        LOOT_ITEM_CREATED_SELF="You create |4item:items; %s.",
        _self=f"You receive items {LINK}.",
        _other=f"Thrall receives item {LINK}.",
        _pushed=f"You receive item {LINK}.",
        _multiple=None,
        _created=f"You create item {LINK}.",
    ),
}

GLOBALS = [
    "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
    "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
    "LOOT_ITEM_BONUS_ROLL_SELF", "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE",
    "LOOT_ITEM", "LOOT_ITEM_MULTIPLE",
    "LOOT_ITEM_PUSHED", "LOOT_ITEM_PUSHED_MULTIPLE",
    "LOOT_ITEM_BONUS_ROLL", "LOOT_ITEM_BONUS_ROLL_MULTIPLE",
    "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_CREATED_SELF_MULTIPLE",
]

failures = []

for locale, data in LOCALES.items():
    g = lua.globals()
    for name in GLOBALS:
        g[name] = data.get(name)
    reset()

    checks = []

    checks.append(("own loot -> own name",
                   determine(data["_self"]), PLAYER))
    checks.append(("another raider's loot -> their name",
                   determine(data["_other"]), "Thrall"))
    checks.append(("pushed item -> own name",
                   determine(data["_pushed"]), PLAYER))
    if data.get("_multiple"):
        checks.append(("stacked loot -> their name",
                       determine(data["_multiple"]), "Thrall"))
    checks.append(("crafted -> own name",
                   determine(data["_created"]), PLAYER))
    checks.append(("crafted is flagged as created",
                   bool(was_created(data["_created"])), True))
    checks.append(("plain loot is not flagged as created",
                   bool(was_created(data["_other"])), False))
    checks.append(("unreadable line -> nil",
                   determine("Something unrelated entirely."), None))

    ok = all(got == want for _, got, want in checks)
    print(("ok   " if ok else "FAIL ") + locale)
    for label, got, want in checks:
        if got != want:
            print(f"       ** {label}: got {got!r}, wanted {want!r}")
    if not ok:
        failures.append(locale)

print()
print("FAILURES:", failures if failures else "none")
sys.exit(1 if failures else 0)

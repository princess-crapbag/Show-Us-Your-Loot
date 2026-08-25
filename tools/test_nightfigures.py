# -*- coding: utf-8 -*-
"""The figures on the raid-night pane, four of which were wrong.

Aimee read the eight figures on the night pane one at a time and doubted four.
An audit agreed with her on all four and found more. None of them were
covered: tools/test_nightspanel.py asserts `pulls` and `kills` and has never
once looked at `drops` or `upgrades`, which is exactly how they stayed wrong.

THE FOUR, with her own night as the fixture - 2026-08-18, two sessions, one
evening:

  "5/10 BOSSES KILLED" was kills over PULLS. Six bosses were engaged and five
  died, in ten pulls. She settled the denominator too: "there are 8 bosses in
  the venomous abyss but i realize we only pulled 6, 5 of which we killed. i
  think it probably makes the most sense to say 5 of 8" - so what is counted
  here is DISTINCT BOSSES KILLED, and the total comes from the instance.

  "22 DROPS" counted every drop with that calendar date. Eleven of the 22 came
  from a Looking For Raid run this same index had already thrown away for
  being 2% guild - discarded in one loop and counted in the next, eleven lines
  apart. Her question: "its not including boes or warbound/personal loot
  right? it should not count those." It was, and now it does not.

  "14 UPGRADES" read the raw roll state, so it never asked DropRules and never
  saw one of her sixteen hand-made credit corrections. On a master-looted
  night that is the master looter's roll counted fourteen times.

  "0 WENT HOME WITH NOTHING" was max(0, raiders - upgrades): a count of items
  subtracted from a count of people, clamped so the negative never showed.

MOG DOES NOT COUNT as going home with gear. Hers: "i dont want to say someone
went home with loot if all they got was a mog item." Need, offspec and greed
do.

Needs `lupa` - see tools/test_lootmessages.py for the setup.
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

STATE = SYL.LootHistoryAPI.ROLL_STATE
NEED, OFFSPEC, MOG, GREED = (STATE.NeedMainSpec, STATE.NeedOffSpec,
                             STATE.Transmog, STATE.Greed)

# Her real evening, in seconds. The LFR run first, the guild raid after.
LFR_AT, RAID_AT = 1000, 7000
DAY = "1970-01-01"


def member(name, rank=None):
    fields = {"name": name, "fullName": name, "guid": name}

    if rank is not None:
        fields["guildRank"] = rank

    return lua.table_from(fields)


def session(sid, at, guilded, pugs, difficulty, encounters):
    """A raid session shaped like one of hers."""
    roster = {
        "Arcangila": member("Arcangila", "Kennel Master"),
    }

    for index in range(guilded):
        roster["G%d" % index] = member("Guildie%d" % index, "Good Kitty")

    for index in range(pugs):
        roster["P%d" % index] = member("Pug%d" % index)

    # An encounter id per boss, because that is the only bridge between a
    # night's records and the Encounter Journal's boss count.
    def withID(pull):
        row = dict(pull)
        row.setdefault("encounterID", abs(hash(row["name"])) % 9000 + 100)
        return lua.table_from(row)

    pulls = lua.table_from([withID(pull) for pull in encounters])

    return lua.table_from({
        "id": sid,
        "instanceType": "raid",
        "instanceName": "The Venomous Abyss",
        "instanceID": 3004,
        "difficultyID": difficulty,
        "recordedBy": "Arcangila-Area52",
        "startedAt": at,
        "endedAt": at + 3000,
        "dateText": DAY,
        "encounters": pulls,
        "roster": lua.table_from(roster),
    })


# The 5:05 LFR run: 49 people, one of them in the guild. 2% guild, so
# RaidSession.CountsAsNight throws it away.
LFR = session("lfr", LFR_AT, 0, 48, 17, [
    {"name": "The Twin Fangs", "difficultyID": 17, "at": LFR_AT + 300,
     "killed": True},
    {"name": "Nek'zali the Soulcoiler", "difficultyID": 17,
     "at": LFR_AT + 1600, "killed": True},
])

# The 6:42 guild raid: twelve people, all guilded. Six bosses engaged, five
# killed, ten pulls - her real 08-18.
GUILD = session("guild", RAID_AT, 11, 0, 14, [
    {"name": "Nek'zali the Soulcoiler", "difficultyID": 14,
     "at": RAID_AT + 400, "killed": True},
    {"name": "Entombed Sentinels", "difficultyID": 14, "at": RAID_AT + 1700,
     "killed": True},
    {"name": "The Lost Explorers", "difficultyID": 14, "at": RAID_AT + 3000,
     "killed": True},
    {"name": "Sszorak", "difficultyID": 14, "at": RAID_AT + 4000},
    {"name": "Sszorak", "difficultyID": 14, "at": RAID_AT + 4600,
     "killed": True},
    {"name": "Vashnik the Malignant", "difficultyID": 14, "at": RAID_AT + 5000},
    {"name": "Vashnik the Malignant", "difficultyID": 14, "at": RAID_AT + 5400},
    {"name": "Vashnik the Malignant", "difficultyID": 14, "at": RAID_AT + 5800,
     "killed": True},
    {"name": "The Twin Fangs", "difficultyID": 14, "at": RAID_AT + 6200},
    {"name": "The Twin Fangs", "difficultyID": 14, "at": RAID_AT + 6600},
    # KILLED TWICE, ONCE ON EACH DIFFICULTY. This is what separates a count
    # of kill EVENTS from a count of BOSSES, and without it the old
    # kills-based figure and the new one agree by accident.
    {"name": "Nek'zali the Soulcoiler", "difficultyID": 15,
     "at": RAID_AT + 7000, "killed": True},
])

SESSIONS = lua.table_from([LFR, GUILD])


def drop(at, winner, state, credited=None, creditedState=None, link=None):
    fields = {
        "timestamp": at,
        "winnerName": winner,
        "winnerGUID": winner,
        "winnerState": state,
        "itemLink": link or "|Hitem:1::::::::80:::::|h[Thing]|h",
        "rolls": lua.table_from([]),
    }

    if credited:
        override = {"name": credited, "guid": credited}

        if creditedState is not None:
            override["state"] = creditedState

        fields["creditOverride"] = lua.table_from(override)

    return lua.table_from(fields)


# Eleven from the LFR run, eleven from the guild raid - her real 22.
DROPS = [drop(LFR_AT + 100 + n * 10, "Pug%d" % n, NEED) for n in range(11)]

# The guild raid. Every one records Arcangila as winner because she master
# loots; nine carry a correction, two do not - which is her real shape.
DROPS += [
    drop(RAID_AT + 100, "Arcangila", MOG, "Guildie0", GREED),
    drop(RAID_AT + 200, "Arcangila", MOG, "Guildie1", NEED),
    drop(RAID_AT + 300, "Arcangila", MOG, "Guildie2", NEED),
    drop(RAID_AT + 400, "Arcangila", GREED, "Guildie3", NEED),
    drop(RAID_AT + 500, "Arcangila", NEED, "Guildie4", NEED),
    drop(RAID_AT + 600, "Arcangila", NEED),
    drop(RAID_AT + 700, "Arcangila", MOG),
    drop(RAID_AT + 800, "Arcangila", GREED, "Guildie3", NEED),
    drop(RAID_AT + 900, "Arcangila", GREED, "Guildie1", GREED),
    drop(RAID_AT + 1000, "Arcangila", MOG, "Guildie2", GREED),
    # THE MOG-ONLY PERSON. Guildie5 gets exactly one thing all night and it
    # is a transmog, so they must NOT read as having gone home with gear.
    drop(RAID_AT + 1100, "Arcangila", MOG, "Guildie5", MOG),
]

# A BIND-ON-EQUIP DROP, which the fairness rule excludes and the loot count
# therefore must not include. Her question: "its not including boes or
# warbound/personal loot right? it should not count those."
#
# The client is stubbed to answer a bind type for this one item, because
# Utilities.IsBindOnEquip reads it live at the moment it is asked -- nothing
# about bind is ever stored, so there is no other way to exercise this.
lua.execute('''
    BOE_LINK = "|Hitem:9999::::::::80:::::|h[Something Tradeable]|h"

    C_Item.GetItemInfo = function(link)
        if tostring(link):find("9999", 1, true) then
            -- select(14) is the bind type. 2 is bind-on-equip.
            return "BoE", link, 4, 0, 0, "", "", 1, "", 0, 0, 0, 0, 2
        end

        return nil
    end
''')

DROPS.append(drop(RAID_AT + 1200, "Arcangila", NEED, "Guildie6", NEED,
                  link=str(lua.globals().BOE_LINK)))

# AN ALT, because folding is the difference between a person and a character.
#
# Guildie7 raided on Guildie7alt and won on it. The roster carries the alt;
# the main is what every fairness figure counts. Without the fold the night
# reports one more person than turned up, and reports them as having gone home
# with gear under a name nobody recognizes.
lua.execute("""
    ShowUsYourLoot.Players.Ensure({
        guid = "Guildie7", name = "Guildie7", class = "MAGE",
    })

    ShowUsYourLoot.Players.Ensure({
        guid = "Guildie7alt", name = "Guildie7alt", class = "ROGUE",
    })

    ShowUsYourLoot.Players.SetMain("Guildie7alt", "Guildie7", "test")
""")

DROPS.append(drop(RAID_AT + 1300, "Arcangila", NEED, "Guildie7alt", NEED))

order, byDay = SYL.NightIndex.Build(SESSIONS, lua.table_from(DROPS))

day = None
for entry in order.values():
    day = entry

check("the evening is one night", day is not None and len(list(order.values())) == 1)


# --------------------------------------------------------------------------
# The LFR run is not a raid night
# --------------------------------------------------------------------------

check("only the guild session counts as the night",
      len(list(day.sessions.values())) == 1,
      "%d sessions" % len(list(day.sessions.values())))

check("and the roster is the guild raid's, not both added together",
      int(day.rosterCount) == 12, "got %r" % day.rosterCount)


# --------------------------------------------------------------------------
# Bosses, over bosses
# --------------------------------------------------------------------------

check("distinct bosses killed, not kill events",
      int(day.bossCount) == 5, "got %r" % day.bossCount)

check("pulls are still counted separately",
      int(day.pulls) == 11, "got %r" % day.pulls)

# The old figure was kills/pulls, so this is the pair that used to read 5/10.
check("and the two are different numbers",
      int(day.bossCount) != int(day.pulls))

# THE ONE THAT SEPARATES BOSSES FROM KILLS. Nek'zali died on Normal and again
# on Heroic: six kill events, five bosses down. A figure counting events
# reports six, and "6 of 8 bosses down" on a night that killed five is a
# wrong fact stated confidently.
check("a boss killed on two difficulties is one boss, not two",
      int(day.kills) == 6 and int(day.bossCount) == 5,
      "%r kill events, %r bosses" % (day.kills, day.bossCount))

fights = list(day.fights.values())

check("every boss engaged is a fight, killed or not",
      len(fights) == 7, "%d fights" % len(fights))

hardest = None
for fight in fights:
    if hardest is None or int(fight.pulls) > int(hardest.pulls):
        hardest = fight

check("the hardest fight is the one that ate the most pulls",
      str(hardest.name) == "Vashnik the Malignant" and int(hardest.pulls) == 3,
      "got %s x%d" % (hardest.name, hardest.pulls))

unkilled = [f for f in fights if f.killedAt is None]

# WHERE THE NIGHT WENT, in one line. Aimee: "longest fight maybe should read
# as 'most pull attempts' but i like how it says the name and the number of
# pulls."
story = SYL.NightFigures.MostPulls(day)

check("the story line names the fight that ate the pulls",
      story and "Vashnik the Malignant" in str(story) and "3" in str(story),
      "got %s" % story)

check("and says how many of the night's pulls it was",
      story and "of the night's 11" in str(story), "got %s" % story)

# A CLEAN NIGHT HAS NO STORY. Every boss dying first try is not a thing that
# needs a sentence, and one would read as though something had gone wrong.
CLEAN, _ = SYL.NightIndex.Build(
    lua.table_from([session("clean", RAID_AT, 11, 0, 14, [
        {"name": "Nek'zali the Soulcoiler", "difficultyID": 14,
         "at": RAID_AT + 100, "killed": True},
    ])]),
    lua.table_from([]),
)

cleanDay = None
for entry in CLEAN.values():
    cleanDay = entry

check("a night where nothing needed a second pull has no story",
      SYL.NightFigures.MostPulls(cleanDay) is None)

check("and the boss that never died is recorded as engaged",
      len(unkilled) == 1 and str(unkilled[0].name) == "The Twin Fangs",
      "%r" % [str(f.name) for f in unkilled])


# --------------------------------------------------------------------------
# Drops that count
# --------------------------------------------------------------------------
#
# THE LEAK. Eleven of the twenty-two came from a session this index had
# already discarded, and it counted them anyway.

# Eleven from the guild raid plus the alt's win. The eleven LFR drops and the
# bind-on-equip one are both out.
check("the LFR run's drops are not on the night",
      int(day.drops) == 12, "got %r - the LFR drops leaked back in"
      % day.drops)

# THE SECOND GUARD, which the first one hides. A drop in a qualifying session
# still has to pass DropRules, and a bind-on-equip item does not.
check("and a bind-on-equip drop is not a piece of loot that counts",
      int(day.drops) == 12,
      "got %r - the BoE was counted" % day.drops)

check("nor does its recipient read as having gone home with gear",
      not day.gotGear["Guildie6"])


# --------------------------------------------------------------------------
# Who went home with gear, and who did not
# --------------------------------------------------------------------------

# Guildie0 greed, Guildie1 need+greed, Guildie2 need+greed, Guildie3 need x2,
# Guildie4 need, Arcangila need (uncorrected). Guildie5 got a mog and nothing
# else. Six people.
check("upgrades is a count of PEOPLE, through the corrections",
      int(day.upgrades) == 7, "got %r" % day.upgrades)

# THE FOLD. A win on an alt is credited to the person, not to the character,
# so it lands under the main's key and never under the alt's.
check("a win on an alt is credited to the main",
      day.gotGear["Guildie7"] is True and not day.gotGear["Guildie7alt"],
      "main %r, alt %r"
      % (day.gotGear["Guildie7"], day.gotGear["Guildie7alt"]))

check("the mog-only raider did not go home with gear",
      not day.gotGear["Guildie5"])

check("but the raider whose only item was a need did",
      day.gotGear["Guildie4"] is True)

check("and the master looter's own uncorrected win counts for her",
      day.gotGear["Arcangila"] is True)

# THE ARITHMETIC THAT USED TO BE ITEMS MINUS PEOPLE.
check("went home with nothing is people minus people",
      int(day.gotNothing) == 12 - 7, "got %r" % day.gotNothing)

check("and it can no longer be zero on a night six of twelve got nothing",
      int(day.gotNothing) > 0)


# --------------------------------------------------------------------------
# The boss total, and what a partly-read journal must not do
# --------------------------------------------------------------------------
#
# "5 of 8" needs a denominator the addon does not store; it comes from the
# Encounter Journal, which is read lazily and may know one raid and not
# another. A night in two instances where only one is known must answer
# NOTHING - adding up the known ones gives a total smaller than the truth,
# and "5 of 1" is a worse answer than "5".

lua.execute("""
    KNOWN = {}

    ShowUsYourLoot.EncounterJournal.BossCountFor = function(encounterID)
        return KNOWN[encounterID]
    end
""")

known = lua.globals().KNOWN

check("with nothing read, there is no denominator",
      SYL.NightFigures.BossTotal(day) is None)

value, label, body = SYL.NightFigures.Bosses(day)

check("and the figure says the bare count",
      str(value) == "5", "got %r" % value)

# Obvious, on screen, for a stranger on CurseForge - not silent.
check("and says out loud that the total is not known yet",
      "not known yet" in str(body))

# NAMES THE REAL BUTTON. Telling somebody to press a control that does not
# exist under that name is the fault the Raiders board tooltip had for months.
check("and names the button that fixes it, in the words it actually uses",
      "Read the Adventure Guide" in str(body))

panel_src = test_load.ROOT.joinpath("UI/BossesPanel.lua").read_text(
    encoding="utf-8")

check("and pressing it actually walks the journal",
      "EncounterJournal.IsAvailable()" in panel_src)

boss_src = test_load.ROOT.joinpath("UI/BossesPanel.lua").read_text(
    encoding="utf-8")

check("with that exact label on the button",
      '"Read the Adventure Guide"' in boss_src)

# Now the journal knows this raid.
lua.execute("KNOWN = {}")
known = lua.globals().KNOWN

for fight in day.fights.values():
    if fight.encounterID:
        known[fight.encounterID] = 8

check("once the journal is read, the denominator appears",
      int(SYL.NightFigures.BossTotal(day)) == 8,
      "got %r" % SYL.NightFigures.BossTotal(day))

value, label, body = SYL.NightFigures.Bosses(day)

check("and the figure reads five of eight", str(value) == "5 of 8",
      "got %s" % value)

check("and the hover no longer says the total is unknown",
      "not known yet" not in str(body))

# TWO INSTANCES, ONE OF THEM UNKNOWN. Her 08-20 is exactly this shape.
GROTTO = session("grotto", RAID_AT + 20000, 11, 0, 14, [
    {"name": "Nymrissa Wavecaller", "difficultyID": 14,
     "at": RAID_AT + 20100, "killed": True, "encounterID": 555},
])

# A DIFFERENT INSTANCE, which is the whole point: the total is one number per
# raid, and a night in two raids has to know both.
GROTTO["instanceName"] = "The Tidebound Grotto"

TWO, _twoByDay = SYL.NightIndex.Build(
    lua.table_from([GUILD, GROTTO]), lua.table_from([])
)

twoDay = None
for entry in TWO.values():
    twoDay = entry

# The second instance's boss is not in KNOWN.
check("a night in two raids, one unknown, has no denominator at all",
      SYL.NightFigures.BossTotal(twoDay) is None,
      "got %r - a short total is worse than none"
      % SYL.NightFigures.BossTotal(twoDay))

lua.execute("KNOWN = {}")


# --------------------------------------------------------------------------
# The evening the calendar used to throw away
# --------------------------------------------------------------------------
#
# Her 2026-08-22 is seven wipes on Ula'tek with 33 people in the group, and
# clicking that day answered "Pick a shaded day". Now it is indexed apart --
# visible, and out of every fairness figure.

others = SYL.NightIndex.OtherNights(SESSIONS)
off = others[DAY]

check("the LFR run is indexed as an off-raid", off is not None)

check("with its pulls", off is not None and int(off.pulls) == 2,
      "got %r" % (off and off.pulls))

check("and how much of it was the guild",
      off is not None and int(off.guilded) == 1 and int(off.groupSize) == 49,
      "got %r of %r" % (off and off.guilded, off and off.groupSize))

# THE RULE SHE SET: "nothing ever counts to fairness or raid night stuff on
# those off raids." An off-raid must never appear as a night.
check("and it is NOT one of the nights",
      len(list(order.values())) == 1)

check("nor are its drops on the night",
      int(day.drops) == 12)

# A dungeon is not an "off raid" - it is not a raid at all.
DUNGEON = session("dungeon", RAID_AT + 90000, 4, 0, 8, [
    {"name": "Crawth", "difficultyID": 8, "at": RAID_AT + 90100,
     "killed": True},
])

DUNGEON["instanceType"] = "party"

check("a dungeon is not an off-raid either",
      not SYL.NightIndex.OtherNights(lua.table_from([DUNGEON]))[DAY])


# --------------------------------------------------------------------------
# The pane draws, for both kinds of day
# --------------------------------------------------------------------------

lua.execute("STATS = StubFrame()")
lua.execute("STATS.figures = {}")

panel = SYL.NightStats.Create(lua.globals().STATS, 152)

for label, args in (
    ("a guild night", (panel, day, DAY, None)),
    ("an off-raid", (panel, None, DAY, off)),
    ("a day with nothing on it", (panel, None, "2099-01-01", None)),
):
    try:
        SYL.NightStats.Render(*args)
        check("the pane renders %s" % label, True)
    except Exception as error:  # noqa: BLE001
        check("the pane renders %s" % label, False,
              str(error).splitlines()[0])


# --------------------------------------------------------------------------
# The wiring
# --------------------------------------------------------------------------

def source(name):
    return test_load.ROOT.joinpath(name).read_text(encoding="utf-8")

stats_src = source("UI/NightStats.lua")

# THE SAME LINE WHOSE ABSENCE KILLED ALL SEVEN DASHBOARD WIDGET TOOLTIPS.
# Every figure now carries a hover naming the people behind it, and a Frame
# that does not take the mouse never fires OnEnter.
check("the figures take the mouse, so their hovers can fire",
      "holder:EnableMouse(true)" in stats_src)

check("and every figure has a hover attached",
      "Tooltips.Attach" in stats_src)

check("the subheading carries the guild share",
      "NightStats.GuildShare" in stats_src)

check("and the time, which used to be a figure that lied",
      "NightStats.DescribeSpan" in stats_src)

panel_src = source("UI/NightsPanel.lua")

# The calendar cell drew the same kills/pulls ratio the pane did, so fixing
# one and not the other would put two answers to one question on one screen.
check("the calendar cell says bosses over bosses too",
      "NightFigures.BossTotal" in panel_src
      and 'night.kills .. "/" .. night.pulls' not in panel_src)

check("and off-raids reach the calendar",
      "NightIndex.OtherNights" in panel_src)


# --------------------------------------------------------------------------
# The two figures that were cut
# --------------------------------------------------------------------------

stats = test_load.ROOT.joinpath("UI/NightStats.lua").read_text(
    encoding="utf-8")

check("nothing draws \"of pulls killed\" any more",
      "of pulls killed" not in stats)

check("nor \"drops per raider\"", "drops per raider" not in stats)

print()
print("FAILURES: " + (", ".join(failures) if failures else "none"))
sys.exit(1 if failures else 0)

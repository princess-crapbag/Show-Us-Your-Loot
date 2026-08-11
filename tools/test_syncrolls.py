"""Roll lists survive the wire, and a fuller list is never traded for an emptier one.

Officer sync sent a drop header and no roll list, so a received drop was marked
`partial`: Analytics skipped it, the trade advisor could not say who lost, and
the pass data this addon's pitch rests on was missing for every drop the
officer did not personally witness. Wins still counted through the header
fallback, so the gap was never a wrong number — it was a missing answer.

THE RULE THAT MATTERS IS THAT LOCAL WINS. A record captured here has the real
roll list; one arriving over the wire may have been captured by somebody who
saw less. So an incoming list is only ever applied when it is strictly bigger
than what is already held, and applying one clears `partial` — leaving the flag
set on a record that now has everything would keep Analytics skipping it
forever, which is the failure that would look exactly like the fix not working.

Round-tripping is checked field by field rather than by length, because the
separators are control characters and a mistake in one of them produces a list
of the right size full of nils.

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

lua.execute(
    """
    SENT = {}

    ShowUsYourLoot.SyncTransport.Send = function(payload, id)
        table.insert(SENT, { payload = payload, id = id })

        return true
    end

    function FullRecord(id)
        return {
            id = id,
            timestamp = 1700000000,
            itemID = 1,
            itemName = 'Robes of the Voidbound',
            winnerName = 'Aimee',
            winnerGUID = 'P1',
            winnerState = 0,
            rolls = {
                {
                    name = 'Aimee', guid = 'P1', class = 'MAGE',
                    state = 0, roll = 91, isWinner = true,
                },
                { name = 'Selunne', guid = 'P2', class = 'PRIEST', state = 0, roll = 44 },
                { name = 'Dravok', guid = 'P3', class = 'WARRIOR', state = 5 },
            },
        }
    end

    -- A drop that arrived as a header: no rolls, marked partial.
    function PlantPartial(id)
        local season = ShowUsYourLootDB.activeSeason

        season.drops = season.drops or {}

        table.insert(season.drops, {
            id = id,
            timestamp = 1700000000,
            itemID = 1,
            winnerName = 'Aimee',
            winnerGUID = 'P1',
            winnerState = 0,
            source = 'SYNC',
            partial = true,
            rolls = {},
        })

        ShowUsYourLoot.LootHistoryStore.RebuildIndex()
    end

    function Reset()
        SENT = {}
        ShowUsYourLootDB.activeSeason.drops = {}
        ShowUsYourLoot.LootHistoryStore.RebuildIndex()
    end

    function RecordState(id)
        local record = ShowUsYourLoot.LootHistoryStore.GetRecord(id)

        if not record then
            return nil
        end

        return #(record.rolls or {}), record.partial and true or false
    end

    function DescribeDecoded(payload)
        local decoded = ShowUsYourLoot.SyncRolls.Decode(payload)

        if not decoded then
            return 'nil'
        end

        local parts = {}

        for _, roll in ipairs(decoded.rolls) do
            table.insert(parts, table.concat({
                roll.name,
                tostring(roll.guid),
                tostring(roll.class),
                tostring(roll.state),
                tostring(roll.roll),
                roll.isWinner and 'W' or '-',
            }, '/'))
        end

        return decoded.id .. ' ' .. table.concat(parts, ' ~ ')
    end
    """
)

g = lua.globals()
Rolls = SYL.SyncRolls

# --- round trip ------------------------------------------------------------
payload = Rolls.Encode(g.FullRecord("d1"))

check(
    "every field survives the round trip",
    g.DescribeDecoded(payload)
    == "d1 Aimee/P1/MAGE/0/91/W ~ Selunne/P2/PRIEST/0/44/- ~ Dravok/P3/WARRIOR/5/nil/-",
    g.DescribeDecoded(payload),
)

check(
    "a header is not mistaken for a roll list",
    Rolls.Decode("SYLSYNC1\tsomething") is None,
)

# --- applying --------------------------------------------------------------
g.Reset()
g.PlantPartial("d1")

count, partial = g.RecordState("d1")

check("a synced header starts with no rolls", count == 0, count)
check("and is marked partial", partial is True)

check("applying a roll list works", Rolls.Apply(Rolls.Decode(payload)) is True)

count, partial = g.RecordState("d1")

check("the rolls land", count == 3, count)

# The half that makes Analytics start counting it.
check("and it stops being partial", partial is False)

# --- local always wins -----------------------------------------------------
#
# A record captured here has the real list. One arriving from somebody who saw
# less must never replace it.
smaller = Rolls.Encode(
    lua.eval(
        "{ id = 'd1', rolls = { { name = 'Aimee', guid = 'P1', state = 0, isWinner = true } } }"
    )
)

check(
    "a shorter list is refused",
    Rolls.Apply(Rolls.Decode(smaller)) is False,
)

count = g.RecordState("d1")[0]

check("and the fuller one is still there", count == 3, count)

check(
    "rolls for a drop this client has never seen are dropped",
    Rolls.Apply(Rolls.Decode(Rolls.Encode(g.FullRecord("unknown")))) is False,
)

# --- the backfill request --------------------------------------------------
g.Reset()

check("nothing to ask about on an empty season", Rolls.RequestBackfill() == 0)

g.PlantPartial("p1")
g.PlantPartial("p2")

missing = Rolls.MissingIDs(40)

check("both partials are missing rolls", len(list(missing.values())) == 2, missing)

g.Reset()
g.PlantPartial("p1")
g.PlantPartial("p2")

check("asking covers both", Rolls.RequestBackfill() == 2)

request = g.SENT[len(list(g.SENT.values()))]["payload"]
ids = Rolls.DecodeRequest(request)

check("the request names them", len(list(ids.values())) == 2, ids)

# A record that already has its rolls is not asked about again.
g.Reset()
g.PlantPartial("p1")
Rolls.Apply(Rolls.Decode(Rolls.Encode(g.FullRecord("p1"))))

check("a filled record is not asked about", Rolls.RequestBackfill() == 0)

# --- answering a request ---------------------------------------------------
g.Reset()

lua.execute(
    """
    local season = ShowUsYourLootDB.activeSeason

    season.drops = { FullRecord('full1') }

    ShowUsYourLoot.LootHistoryStore.RebuildIndex()
    """
)

answered = Rolls.AnswerBackfill(lua.table("full1", "never-seen"))

check("a full record is answered", answered == 1, answered)
check("and an unknown id is silently skipped", answered == 1)

# --- routing ---------------------------------------------------------------
check("a roll payload is claimed by this module", Rolls.OnPayload(payload, "Someone") is True)
check("so is a request", Rolls.OnPayload(request, "Someone") is True)
check(
    "a drop header is left for Sync to handle",
    Rolls.OnPayload("SYLSYNC1\tid\tstuff", "Someone") is False,
)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)

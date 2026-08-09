"""Sync chunking: split, envelope, and reassembly (F8).

Addon messages cap at 255 bytes, so anything larger has to be cut up and put
back together. The failure modes are all silent — a payload that reassembles
one byte short, a chunk counted twice, pieces from two senders mixing — so
they are checked rather than reasoned about.

The Lua is lifted out of Core/SyncTransport.lua.

Needs `lupa`; see tools/test_lootmessages.py for the setup.

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

ADDON = Path(__file__).resolve().parent.parent / "Core" / "SyncTransport.lua"
source = ADDON.read_text(encoding="utf-8")

start = source.index("local CHUNK_PROTOCOL")
end = source.index("-- Sending, one at a time")
block = source[start:end].rstrip().rstrip("-").rstrip()

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(f'''
local SEPARATOR = "\\t"
SYL = {{ DebugPrint = function() end }}
time = function() return _G.NOW or 1000 end

{block}

_G.SplitIntoChunks = SplitIntoChunks
_G.ChunkEnvelope = ChunkEnvelope
_G.ParseChunk = ParseChunk
_G.Reassemble = Reassemble
''')

g = lua.globals()
CHUNK_SIZE = 200
MAX_MESSAGE = 255

failures = []


def check(label, ok, detail=""):
    print(("ok   " if ok else "FAIL ") + label + ("" if ok else "  " + detail))
    if not ok:
        failures.append(label)


def send(payload, message_id="1", sender="Aimee"):
    """Split, envelope, parse and reassemble, as the wire would."""
    chunks = g.SplitIntoChunks(payload)
    count = len(chunks)
    result = None
    sizes = []

    for index in range(1, count + 1):
        wire = g.ChunkEnvelope(message_id, index, count, chunks[index])
        sizes.append(len(wire.encode("utf-8")))

        parsed_id, parsed_index, parsed_count, data = g.ParseChunk(wire)
        assert parsed_id == message_id, "message id survived"

        result = g.Reassemble(sender, parsed_id, parsed_index,
                              parsed_count, data)

    return result, count, sizes


# A short payload is one chunk and comes back unchanged.
payload = "1\tabc\t42\tThrall"
out, count, sizes = send(payload)
check("a short payload is one chunk", count == 1, f"got {count}")
check("and survives the round trip", out == payload, f"got {out!r}")

# Exactly one chunk's worth, then one byte over: the off-by-one boundary.
exact = "x" * CHUNK_SIZE
out, count, _ = send(exact, "2")
check("exactly one chunk stays one chunk", count == 1, f"got {count}")
check("and round trips", out == exact)

over = "y" * (CHUNK_SIZE + 1)
out, count, _ = send(over, "3")
check("one byte over becomes two chunks", count == 2, f"got {count}")
check("and round trips", out == over, f"len {len(out) if out else None}")

# A realistic 25-player roll list, which is what the cap was blocking.
big = "\t".join(f"Player{n}:0:{90 + n}" for n in range(1, 26))
out, count, sizes = send(big, "4")
check("a 25-player roll list reassembles", out == big,
      f"len {len(out) if out else None} vs {len(big)}")
check("across several chunks", count > 1, f"got {count}")
check("and every message fits the 255-byte cap",
      all(size <= MAX_MESSAGE for size in sizes), f"sizes {sizes}")

# A duplicate piece must not count twice, or the set completes early and
# short.
chunks = g.SplitIntoChunks("z" * (CHUNK_SIZE * 3))
first = g.ChunkEnvelope("5", 1, 3, chunks[1])
_id, _i, _c, data = g.ParseChunk(first)
g.Reassemble("Bob", _id, _i, _c, data)
early = g.Reassemble("Bob", _id, _i, _c, data)
check("a repeated chunk does not complete the set early", early is None)

# Two senders sending different things at once must not mix.
a_chunks = g.SplitIntoChunks("A" * (CHUNK_SIZE + 10))
b_chunks = g.SplitIntoChunks("B" * (CHUNK_SIZE + 10))

g.Reassemble("Aimee", "9", 1, 2, a_chunks[1])
g.Reassemble("Thrall", "9", 1, 2, b_chunks[1])
a_out = g.Reassemble("Aimee", "9", 2, 2, a_chunks[2])
b_out = g.Reassemble("Thrall", "9", 2, 2, b_chunks[2])

check("two senders using the same message id do not mix",
      a_out == "A" * (CHUNK_SIZE + 10) and b_out == "B" * (CHUNK_SIZE + 10))

# Anything that is not an envelope is refused rather than guessed at.
check("a non-envelope message is refused",
      g.ParseChunk("1\tabc\tdef") is None)
check("an out-of-range index is refused",
      g.ParseChunk("C1\t1\t5\t2\tdata") is None)

print()
print("FAILURES:", failures or "none")
sys.exit(1 if failures else 0)

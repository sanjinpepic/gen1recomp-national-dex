-- Repairing move slots an earlier version of this mod already wrote.
--
-- src/moves.lua stops NEW learnset rows naming an unresolvable move. It does
-- nothing for a Pokemon that already learned one, because a move slot is save
-- data -- id, pp and maxPp are written when the move is learned and nothing
-- re-derives them. A real Silver save had a ROLYCOLY holding RAPIDSPIN 0/0 and
-- a boxed TOGEPI holding SWEETKISS 0/0, and both would have stayed that way
-- for the life of the playthrough.
--
-- This edits a player's save on load, so what is pinned hardest is everything
-- it must REFUSE to touch. The repair is worth nothing if it cannot be trusted
-- with a slot it does not understand.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local MOD = arg[0]:gsub("[/\\]tests[/\\][^/\\]+$", "")
local Repair = dofile(MOD .. "/src/moverepair.lua")

-- A move table shaped like a real merged one: the cart's own spelling is
-- inconsistent (Gold owns ANCIENTPOWER without an underscore and RAPID_SPIN
-- with one), which is the whole reason a normalised lookup is needed rather
-- than a rule.
local MOVES = {
  TACKLE = { pp = 35 },
  RAPID_SPIN = { pp = 40 },
  SWEET_KISS = { pp = 10 },
  ANCIENTPOWER = { pp = 5 },
  POISONTAIL = { pp = 25 },
}

-- --- the index ------------------------------------------------------------
local index = Repair.index(MOVES)
T.eq(index.RAPIDSPIN, "RAPID_SPIN", "a squashed id maps to the cart's spelling")
T.eq(index.SWEETKISS, "SWEET_KISS", "and so does every other one")
T.eq(index.ANCIENTPOWER, "ANCIENTPOWER",
  "an id that needs no translation maps to itself")
T.eq(index.MOONBLAST, nil, "and an id nothing owns maps to nothing")

-- Two real moves differing only in punctuation is a situation this mod has no
-- business resolving silently, so the key is dropped rather than guessed at.
local ambiguous = Repair.index({ ["FOO_BAR"] = { pp = 5 }, FOOBAR = { pp = 10 } })
T.eq(ambiguous.FOOBAR, nil, "an ambiguous normalised form is refused, not picked")

-- --- the repair -----------------------------------------------------------
local mon = { species = "ROLYCOLY", moves = {
  { id = "TACKLE", pp = 12, maxPp = 35 },
  { id = "RAPIDSPIN", pp = 0, maxPp = 0 },
} }
T.eq(Repair.repairMon(mon, MOVES, index), 1, "one slot is repaired")
T.eq(mon.moves[2].id, "RAPID_SPIN", "onto the id the game can resolve")
T.eq(mon.moves[2].pp, 40, "with the record's PP restored")
T.eq(mon.moves[2].maxPp, 40, "on both fields")

-- The working slot beside it is untouched, PARTIAL PP INCLUDED. A repair that
-- also topped up a move the player had been using would be handing out free
-- PP under cover of a bug fix.
T.eq(mon.moves[1].id, "TACKLE", "a resolvable slot keeps its id")
T.eq(mon.moves[1].pp, 12, "and its spent PP")

-- --- what it must refuse --------------------------------------------------
-- An id nothing can be matched to is left exactly as it is: it may belong to
-- another mod that has not loaded yet, and guessing is worse than the 0/0 it
-- would replace.
local foreign = { moves = { { id = "SOMEOTHERMOD_MOVE", pp = 0, maxPp = 0 } } }
T.eq(Repair.repairMon(foreign, MOVES, index), 0, "an unmatchable id is left alone")
T.eq(foreign.moves[1].id, "SOMEOTHERMOD_MOVE", "with its id intact")

-- A move this mod itself registered resolves in the merged table, so it is
-- never even considered -- the Venipede case from the real save.
local ours = { moves = { { id = "POISONTAIL", pp = 25, maxPp = 25 } } }
T.eq(Repair.repairMon(ours, MOVES, index), 0,
  "a move that already resolves is never touched, whoever registered it")

T.eq(Repair.repairMon(nil, MOVES, index), 0, "no Pokemon, nothing repaired")
T.eq(Repair.repairMon({}, MOVES, index), 0, "nor one with no moves")

-- --- boxes count -----------------------------------------------------------
-- A broken slot follows the Pokemon into storage, and the real save had one
-- there: a player who boxed the Pokemon before the fix is exactly who this has
-- to reach.
local save = {
  party = { { moves = { { id = "RAPIDSPIN", pp = 0, maxPp = 0 } } } },
  boxes = {
    { { moves = { { id = "SWEETKISS", pp = 0, maxPp = 0 } } } },
    { mons = { { moves = { { id = "RAPIDSPIN", pp = 0, maxPp = 0 } } } } },
  },
}
T.eq(Repair.run(save, MOVES), 3, "party and both box shapes are all walked")
T.eq(save.party[1].moves[1].id, "RAPID_SPIN", "the party mon is repaired")
T.eq(save.boxes[1][1].moves[1].id, "SWEET_KISS", "a bare-array box is repaired")
T.eq(save.boxes[2].mons[1].moves[1].id, "RAPID_SPIN",
  "and so is a box that keeps its mons under a key")

-- Idempotent: a second load must find nothing left to do, or every load would
-- report a repair it did not perform.
T.eq(Repair.run(save, MOVES), 0, "running it again changes nothing")

-- --- it cannot run without a move table -----------------------------------
T.eq(Repair.run(save, nil), 0, "no move table, no repair")
T.eq(Repair.run(nil, MOVES), 0, "and no save is not an error either")

T.finish("national_dex_moverepair")

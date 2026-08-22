-- A learnset must name a move the running game can actually resolve.
--
-- THE BUG THIS PINS, because the shape of it is not obvious from either side.
-- normaliseId strips punctuation, so this mod's RAPIDSPIN matches the cart's
-- RAPID_SPIN and src/moves.lua correctly SKIPS registering over it -- the
-- cart's Rapid Spin is a real implementation with the ROM's own animation and
-- index, and overwriting it would be this mod rewriting the base game to say
-- what it already says. That skip is right and stays.
--
-- What was missing is the other half: the learnset shards still said
-- RAPIDSPIN, and nothing translated it into the id the game holds. A species
-- widened with such a row got a move slot naming a record that does not exist,
-- and the Gen 2 mon builder reads `pp = moveDef and moveDef.pp or 0` -- so the
-- move sat in the FIGHT menu at 0/0 PP and could never be used. A real save
-- showed a level 6 ROLYCOLY holding `RAPIDSPIN 0/0`.
--
-- GEN 2 ONLY, and not because the code differs. Gold and Silver own 253 moves
-- to Red's 165, and the extra ones are precisely the Gen 2 additions -- Rapid
-- Spin, Scary Face, Giga Drain, Metal Claw, Baton Pass -- that this mod
-- otherwise registers itself. On Red they collide with nothing, every id
-- resolves, and the same code is silent.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local MOD = arg[0]:gsub("[/\\]tests[/\\][^/\\]+$", "")
local Moves = dofile(MOD .. "/src/moves.lua")

-- A registry standing in for a cart that spells its ids with underscores,
-- which is what both real games do for a large share of theirs.
local CART = { "TACKLE", "RAPID_SPIN", "SCARY_FACE", "WATER_GUN", "GIGA_DRAIN" }
local registry = { each = function() return CART end }

-- --- existingIds answers WHICH spelling, not merely whether ---------------
local existing = Moves.existingIds(registry)
T.eq(existing["RAPIDSPIN"], "RAPID_SPIN",
  "the normalised key answers the id the cart actually registered")
T.eq(existing["SCARYFACE"], "SCARY_FACE", "and so does every other one")
T.eq(existing["TACKLE"], "TACKLE",
  "an id with no punctuation answers itself, unchanged")
T.eq(existing["MOONBLAST"], nil, "and a move the cart lacks answers nothing")

-- Still truthy, because the collision check that reads this only ever wanted
-- a yes or no and must keep working.
T.check(existing["RAPIDSPIN"], "the value stays truthy for the collision check")

-- --- mergeRows translates the row it adds ---------------------------------
local translate = { RAPIDSPIN = "RAPID_SPIN", SCARYFACE = "SCARY_FACE" }
local allowed = { RAPIDSPIN = true, SCARYFACE = true, MOONBLAST = true,
                  TACKLE = true }

local rows = Moves.mergeRows({}, {
  { level = 5, move = "RAPIDSPIN" },
  { level = 9, move = "MOONBLAST" },
}, allowed, translate)

local byLevel = {}
for _, row in ipairs(rows) do byLevel[row.level] = row.move end
T.eq(byLevel[5], "RAPID_SPIN",
  "a move the cart owns is added under the CART's spelling, not this mod's")
T.eq(byLevel[9], "MOONBLAST",
  "and a move only this mod supplies keeps its own, since nothing else has it")

-- --- no duplicate when the species already knows the cart's spelling ------
-- Translating after the dedup would list one move twice, one of them dead.
local dup = Moves.mergeRows({ { level = 1, move = "RAPID_SPIN" } },
  { { level = 5, move = "RAPIDSPIN" } }, allowed, translate)
local count = 0
for _, row in ipairs(dup) do
  if row.move == "RAPID_SPIN" or row.move == "RAPIDSPIN" then count = count + 1 end
end
T.eq(count, 1, "the same move is not listed twice under two spellings")
T.eq(dup[1].move, "RAPID_SPIN", "and the row kept is the cart's own")

-- --- absent translation changes nothing -----------------------------------
-- Red builds an empty table, so this path must behave exactly as it did.
local untranslated = Moves.mergeRows({}, { { level = 5, move = "RAPIDSPIN" } },
  allowed, nil)
T.eq(untranslated[1].move, "RAPIDSPIN",
  "with no translation table the row is added unchanged, as on Gen 1")
local empty = Moves.mergeRows({}, { { level = 5, move = "RAPIDSPIN" } },
  allowed, {})
T.eq(empty[1].move, "RAPIDSPIN", "and an empty one is the same thing")

-- --- the real data, end to end -------------------------------------------
-- The unit assertions above would all pass against a translation table built
-- wrongly. This walks every learnset shard the mod actually ships and proves
-- no row can name a move a Gen 2 game could not resolve.
local ok, index = pcall(dofile,
  MOD .. "/data/moves/generated/learnsets/index.lua")
local okPayload, payload = pcall(dofile,
  MOD .. "/data/moves/generated/registry_gen2.lua")
if ok and okPayload and type(index) == "table" and type(payload) == "table" then
  -- A cart vocabulary shaped like Gold's: every id this mod supplies, spelled
  -- the way a cart that owned it would.
  local cartIds, cart = {}, {}
  for id in pairs(payload.moves) do
    -- Half of them get an underscore, which is the shape that breaks things.
    local spelled = id:gsub("^(%u%u%u%u)(%u+)$", "%1_%2")
    cartIds[#cartIds + 1] = spelled
    cart[spelled] = true
  end
  local live = Moves.existingIds({ each = function() return cartIds end })
  local map, resolvable = {}, {}
  for id in pairs(payload.moves) do
    local key = Moves.normaliseId(id)
    local actual = key and live[key]
    if type(actual) == "string" then
      resolvable[actual] = true
      if actual ~= id then map[id] = actual end
    else
      resolvable[id] = true
    end
  end

  local files, refs, bad, firstBad = {}, 0, 0, nil
  for _, number in pairs(index) do files[number] = true end
  for number in pairs(files) do
    local loaded, shard = pcall(dofile,
      ("%s/data/moves/generated/learnsets/%03d.lua"):format(MOD, number))
    if loaded and type(shard) == "table" then
      for _, list in pairs(shard) do
        for _, row in ipairs(list) do
          if type(row.move) == "string" then
            refs = refs + 1
            local final = map[row.move] or row.move
            if not resolvable[final] then
              bad = bad + 1
              firstBad = firstBad or row.move
            end
          end
        end
      end
    end
  end
  T.check(refs > 1000, "the shipped learnsets were actually walked (" .. refs .. ")")
  T.eq(bad, 0, "every learnset row resolves once translated (first bad: "
    .. tostring(firstBad) .. ")")
end

T.finish("national_dex_moveid_translation")

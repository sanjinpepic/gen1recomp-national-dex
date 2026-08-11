-- Reshapes a species record from the Gen 1 registry shape this mod's data is
-- generated in into the Gen 2 one, for a Pokemon Gold boot.
--
-- Gold is not Gen 1 with different spelling.  The engine keeps two record
-- schemas for the SAME registry (gen1recomp src/mods/Schemas.lua, R.pokemon
-- `fields` vs `gen2Fields`) and they differ in four structural places:
--
--   * `baseStats.special` becomes `specialAttack` + `specialDefense`
--   * `learnset` + `level1Moves` become one `levelMoves` table
--   * `frontSize` becomes `picSize`
--   * an evolution points at `into`, not `species`
--
-- and the Gen 2 shape carries no `dexEntry` at all.  That schema's own note
-- is blunt about what happens without a translation: register "is unusable
-- for a Gold species -- every record fails on the missing `special`", while
-- patch happens to work, "which is the worst of both".  Since every
-- registration here is pcall-guarded, an untranslated record would not crash
-- anything; the mod would simply load with no species and no explanation.
--
-- Everything this mod attaches beyond the schema -- `spAttack`/`spDefense`,
-- `form`/`baseSpecies`, and the dex-page payload -- rides through untouched,
-- because the API (src/api.lua) and the dex UI read those fields back off the
-- registered record and must find the same data whichever game is running.
--
-- Everything below M.generation is pure -- no love, no engine module, no mod
-- handle -- so tests call it directly with plain tables.

local M = {}

-- Which generation this boot is, read off the mod API rather than inferred
-- from the version -- the Gen 2 guide's whole point about allow-lists is that
-- `id == "red" or id == "blue" or ...` answers wrongly the day a fourth cart
-- appears.  `generation` is a Gen 2 constant the ROM import stamps and the
-- engine's own Gen 2 constants schema declares; Gen 1 has no such key, so
-- this reads 2 on Gold and nil on Red/Blue/Yellow.
--
-- It is readable in the entry chunk because Gold fills data.gen2Constants
-- while it boots, before it hands the loader the dataset and long before any
-- mod runs.  Deliberately NOT require("src.core.GameVersion"): that answers
-- the same question, but reaching past the mod API for it trips the dev
-- shim's engine-internals warning for something the sanctioned surface
-- already exposes.
--
-- Anything unexpected falls back to 1, the shape the generated data is
-- already in, so a boot this cannot read behaves exactly as every release
-- before Gold support did rather than reshaping records on a guess.
function M.generation(mod)
  local ok, value = pcall(function()
    return mod.content.constants:get("generation")
  end)
  if ok and type(value) == "number" then return value end
  return 1
end

-- Gold's cart describes #1-251 itself.  The player's ROM import registers
-- them before any mod runs, so those ids are already taken.
M.ROM_DEX_MAX = 251

-- Written in their Gen 2 spelling below, so they must not also survive under
-- their Gen 1 name -- a stale `learnset` beside a fresh `levelMoves` invites
-- the next reader to trust whichever one it happens to know about.
local GEN1_ONLY = { learnset = true, level1Moves = true, frontSize = true }

local function clamp(value, low, high)
  if type(value) ~= "number" then return nil end
  value = math.floor(value)
  if value < low then return low end
  if value > high then return high end
  return value
end

-- Gen 1 stores the level-1 moves in their own list AND repeats them as
-- level-1 rows of `learnset`; Gen 2 has only the one table.  So the two are
-- merged and de-duplicated rather than concatenated -- straight concatenation
-- teaches Chikorita TACKLE twice at level 1.  `level1Moves` goes in first so
-- the result stays in ascending level order for a caller that walks it.
function M.levelMoves(record)
  local rows, seen = {}, {}
  local function add(level, move)
    if type(level) ~= "number" or type(move) ~= "string" then return end
    local key = level .. " " .. move
    if seen[key] then return end
    seen[key] = true
    rows[#rows + 1] = { level = level, move = move }
  end
  for _, move in ipairs(record.level1Moves or {}) do add(1, move) end
  for _, row in ipairs(record.learnset or {}) do add(row.level, row.move) end
  return rows
end

-- The real Sp.Atk/Sp.Def when the record carries the split, and the collapsed
-- `special` for both halves when it does not.  Falling back that way keeps a
-- record registrable instead of failing the schema's required field: a
-- species with an equal-halves guess still appears, and the alternative is
-- that it does not exist on Gold at all.
function M.baseStats(record)
  local base = record.baseStats or {}
  local special = base.special
  return {
    hp = clamp(base.hp, 1, 255),
    attack = clamp(base.attack, 1, 255),
    defense = clamp(base.defense, 1, 255),
    speed = clamp(base.speed, 1, 255),
    specialAttack = clamp(record.spAttack or special, 1, 255),
    specialDefense = clamp(record.spDefense or special, 1, 255),
  }
end

-- Accepts either spelling of the target so the function is safe to run twice
-- over a record that has already been through it.
function M.evolutions(record)
  local out = {}
  for _, evo in ipairs(record.evolutions or {}) do
    local into = evo.into or evo.species
    if type(evo.method) == "string" and type(into) == "string" then
      out[#out + 1] = { method = evo.method, into = into,
                        level = evo.level, item = evo.item }
    end
  end
  return out
end

-- True when Gold's own cart already describes this species, so registering it
-- would be a second claim on an id the ROM import has taken.  A form is never
-- ROM-owned however low its `dex` reads: a form's `dex` is deliberately its
-- BASE species' number (see src/nationaldex.lua), not its own.
function M.romOwned(record)
  return record.form == nil
    and type(record.dex) == "number"
    and record.dex <= M.ROM_DEX_MAX
end

-- The Gen 2 record for a species Gold does not have.
function M.record(source)
  local out = {}
  for key, value in pairs(source) do
    if not GEN1_ONLY[key] then out[key] = value end
  end
  out.baseStats = M.baseStats(source)
  out.levelMoves = M.levelMoves(source)
  out.evolutions = M.evolutions(source)
  out.picSize = source.frontSize or source.picSize
  return out
end

-- What to say about a species Gold already has: its modern typing, plus the
-- split for anything reading this mod's records back.  Deliberately NOT its
-- base stats -- on Gen 2 those are live battle numbers the cart supplies and
-- the engine reads directly, so replacing #1-251 with current-generation
-- values would silently rebalance a Gold playthrough.  Gen 1 shows the same
-- restraint toward `baseStats.special` for the same reason.
function M.romPatch(record)
  return {
    types = record.types,
    spAttack = record.spAttack,
    spDefense = record.spDefense,
  }
end

return M

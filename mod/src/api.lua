-- Cross-mod read API: what another mod asks this one for.
--
-- Runs entirely IN PROCESS.  Nothing is hosted, nothing listens on a socket,
-- there is no server to start and no port to configure -- `mod.exports` is a
-- plain Lua table the engine hands to any other loaded mod through
-- `mod:find("national_dex")` (src/mods/Loader.lua returns
-- {id, version, exports} for a mod that loaded, nil for one that did not).
-- The only requirement on the player's side is that this mod is installed and
-- enabled; a consumer that finds nil must carry on without us.
--
-- Everything here is READ-ONLY and hands back COPIES.  A consumer holding a
-- live reference into the content registry could mutate the species data the
-- battle engine reads, which is exactly the class of bug this project keeps
-- paying for -- so no table returned from this file is ever one we still use.
--
-- Consumer sketch:
--
--   local dex = mod:find("national_dex")
--   if dex and dex.exports.apiVersion then
--     local charizard = dex.exports.statsByDex(6)
--     -- charizard.stats.spAttack == 109, charizard.stats.special == 85
--   end
--
-- API VERSIONING: `apiVersion` is an integer that only goes up, and only when
-- an existing field changes meaning or disappears.  Adding a new field does
-- not bump it, so a consumer should check `>=`, never `==`.

local M = {}

M.API_VERSION = 1

-- ------------------------------------------------------------- extras load
--
-- The complete, unfiltered modern data (movesFull, movesByMethod, abilities,
-- evYield, eggGroups, baseHappiness, growthRateName, genderRate) never rides
-- on the registered pokemon record -- see tools/build_national_dex.py's
-- EXTRAS_KEYS for why: bolting it onto every one of 1351 records once pushed
-- a single national.lua past LuaJIT's 65,536-constants-per-chunk ceiling,
-- and the mod loaded with zero species. It lives instead in
-- data/species/generated/extras/<NNN>.lua shards plus an index.lua mapping
-- species id -> shard number, and THIS module is the only thing that ever
-- reads them: nothing the game itself does needs this data.
--
-- Loaded lazily and cached: the index (one small read) on the first request
-- for ANY species' extras, then one shard (one bigger read) on the first
-- request for a species that shard covers. A second request for the same
-- species, or any other species sharing that shard, costs nothing further.
local EXTRAS_INDEX_PATH = "data/species/generated/extras/index.lua"
-- must match write_extras()'s zero-padding exactly (build_national_dex.py
-- hardcodes the same width for the same reason: the name has to be
-- reconstructable from the bare shard number index.lua stores).
local EXTRAS_FILENAME_WIDTH = 3

local function extrasShardPath(number)
  return string.format("data/species/generated/extras/%0" .. EXTRAS_FILENAME_WIDTH
    .. "d.lua", number)
end

-- mod:read(...) + load(...) is the exact route main.lua's loadOptionalSibling
-- already uses to load a sibling data file -- but that helper asserts on a
-- syntax error, which is correct at mod-load time (a broken sibling should
-- fail loudly then) and wrong here: a request for one species' extras must
-- degrade to "no extras" and still answer the caller, never take the whole
-- API down. So this pcalls the chunk too, rather than asserting.
local function loadDataModule(mod, name)
  local source = mod:read(name)
  if not source then return nil end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. name)
  if not chunk then return nil end
  local ok, result = pcall(chunk)
  if not ok then return nil end
  return result
end

-- Builds the extras lookup for one `mod`, with its own index/shard cache --
-- returned as a single function so M.install can capture one instance per
-- installed mod rather than sharing state across calls.
local function makeExtrasLookup(mod)
  -- nil = not yet attempted; false = attempted, unavailable (missing or
  -- unreadable); a table = loaded.  Distinguishing nil from false is what
  -- makes this "try once, then cache the answer either way" instead of
  -- re-reading a genuinely missing file on every single call.
  local index
  local shards = {}

  local function getIndex()
    if index == nil then
      local loaded = loadDataModule(mod, EXTRAS_INDEX_PATH)
      index = (type(loaded) == "table") and loaded or false
    end
    return index or nil
  end

  local function getShard(number)
    if shards[number] == nil then
      local loaded = loadDataModule(mod, extrasShardPath(number))
      shards[number] = (type(loaded) == "table") and loaded or false
    end
    return shards[number] or nil
  end

  -- The extras table for one species id, or nil -- missing index, missing
  -- shard, an id absent from the index, or a shard that doesn't carry that
  -- id after all (an index/shard gone stale relative to each other) all
  -- answer nil the same way. Never raises.
  return function(id)
    local idx = getIndex()
    local shardNumber = idx and idx[id]
    if not shardNumber then return nil end
    local shard = getShard(shardNumber)
    return shard and shard[id] or nil
  end
end

-- ------------------------------------------------------------- pure shaping

-- A full independent copy of a species record.  Deep rather than shallow
-- because the interesting parts -- learnset, evolutions, dexEntry -- are
-- nested tables, and handing back a shallow copy would still leak live
-- references to those into another mod's hands.
--
-- `seen` guards against a cycle rather than trusting the data to be a tree:
-- a record is plain data today, but a consumer crashing the game on a stack
-- overflow because someone added a back-reference is not an acceptable way
-- to find that out.  Functions are dropped; nothing on a species record
-- should be callable, and passing one across the mod boundary would hand out
-- an upvalue closure over our own state.
local function deepCopy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for key, item in pairs(value) do
    if type(item) ~= "function" and type(key) ~= "function" then
      out[deepCopy(key, seen)] = deepCopy(item, seen)
    end
  end
  return out
end
M.deepCopy = deepCopy

-- The stat block, in one shape whatever the record carries.
--
-- `special` is the ROM's single collapsed stat and is what the engine's own
-- damage maths reads -- it is reported unchanged and must stay that way.
-- `spAttack`/`spDefense` are the real Gen 6 split, present only on records
-- this mod supplied; `hasSplit` says which of the two worlds a caller is in
-- rather than making them infer it from a nil.
function M.statBlock(record)
  local base = (type(record) == "table" and record.baseStats) or {}
  local split = type(record) == "table"
    and type(record.spAttack) == "number"
    and type(record.spDefense) == "number"
  local stats = {
    hp = base.hp, attack = base.attack, defense = base.defense,
    speed = base.speed, special = base.special,
    spAttack = split and record.spAttack or nil,
    spDefense = split and record.spDefense or nil,
  }
  local total = 0
  for _, key in ipairs({ "hp", "attack", "defense", "speed" }) do
    total = total + (stats[key] or 0)
  end
  -- The total counts the six modern stats when the split is known and the
  -- five Gen 1 ones when it is not, so it always matches what the same
  -- record would display -- never a mix of the two.
  if split then
    total = total + stats.spAttack + stats.spDefense
  else
    total = total + (stats.special or 0)
  end
  return stats, split, total
end

-- EVERYTHING the record carries, plus a normalised view on top.
--
-- The reply is a full copy of the species record rather than a hand-picked
-- subset, so a consumer gets the learnset, level-1 moves, evolutions, growth
-- rate, catch rate, base experience, typing, the dex entry (kind, height,
-- weight, and the id of its description text) and the art paths -- and so
-- that a field added to the records later reaches consumers without this
-- file needing to be edited to let it through.  Someone implementing mega
-- evolutions needs the whole record, not the parts we happened to think of.
--
-- Added on top, and the reason this is not just deepCopy:
--   stats     normalised block; `special` is the ROM's collapsed stat that
--             the engine's damage maths reads, `spAttack`/`spDefense` the
--             real split where this mod supplies it.  `baseStats` is still
--             present, untouched, for anything that wants the raw shape.
--   hasSplit  whether the split is real for this record, rather than making
--             a caller infer it from a nil
--   total     sum of the six modern stats when the split is known, the five
--             Gen 1 ones when it is not -- never a mix
--   baseDex   for a FORM, the dex number to display.  A form's own `dex` is
--             a synthetic key far above the real roster, invented so it can
--             register without colliding with its base species, and it must
--             never be shown to a player.
--
-- Deliberately NOT merged here: movesFull/movesByMethod/abilities/evYield/
-- eggGroups/baseHappiness/growthRateName/genderRate. Those never ride on the
-- registered record at all (see the extras-load section above), so there is
-- nothing on `record` for deepCopy to pick up -- M.install's withExtras()
-- merges them in as a separate step, after this function returns, because it
-- needs the installed `mod` to read the shard from and this function stays a
-- pure function of its arguments.
function M.shape(id, record, forms, baseDex)
  if type(record) ~= "table" then return nil end
  local out = deepCopy(record)
  local stats, hasSplit, total = M.statBlock(record)
  out.id = record.id or id
  out.stats = stats
  out.hasSplit = hasSplit
  out.total = total
  out.baseDex = baseDex or record.dex
  out.forms = forms
  return out
end

-- ------------------------------------------------------------------ install

-- Every species id the pokemon registry knows, engine-supplied included.
-- Registry:each() is the sanctioned walk; it is defended rather than trusted
-- because a shape change there must degrade this API, never fail the load.
local function allIds(registry)
  local ok, result = pcall(function() return registry:each() end)
  if not ok then return nil end
  if type(result) == "function" then
    local ids = {}
    for id in result do ids[#ids + 1] = id end
    return ids
  end
  if type(result) == "table" then return result end
  return nil
end

function M.install(mod)
  local pokemon = mod.content and mod.content.pokemon
  if not pokemon then return false end

  -- One extras lookup (its own index/shard cache) per installed mod -- see
  -- makeExtrasLookup above.
  local extrasFor = makeExtrasLookup(mod)

  -- Merges a species' extras (if any) into an already-shaped reply, as a
  -- COPY -- exactly like every other field M.shape hands out, so a consumer
  -- mutating movesFull/abilities on the reply can never reach the cached
  -- shard.  Takes and returns the shaped table so call sites can wrap
  -- M.shape(...) inline; passes nil straight through so a caller never has
  -- to null-check twice.
  local function withExtras(shaped)
    if not shaped then return nil end
    local extras = extrasFor(shaped.id)
    if type(extras) == "table" then
      for key, value in pairs(deepCopy(extras)) do
        shaped[key] = value
      end
    end
    return shaped
  end

  -- Built once, on the first call rather than at load: the registry is still
  -- being written to while mods load, and a snapshot taken then would miss
  -- every species registered by a mod ordered after this one.
  local index, formsOf
  local function build()
    if index then return end
    index, formsOf = {}, {}
    local ids = allIds(pokemon) or {}
    for _, id in ipairs(ids) do
      local ok, record = pcall(function() return pokemon:get(id) end)
      if ok and type(record) == "table" then
        if record.baseSpecies and record.form then
          local list = formsOf[record.baseSpecies]
          if not list then list = {}; formsOf[record.baseSpecies] = list end
          list[#list + 1] = id
        elseif type(record.dex) == "number" and index[record.dex] == nil then
          -- first writer wins, so a mod registering an extra record against a
          -- dex number cannot displace the species that owns it
          index[record.dex] = id
        end
      end
    end
    for _, list in pairs(formsOf) do table.sort(list) end
  end

  local function record(id)
    local ok, value = pcall(function() return pokemon:get(id) end)
    if ok and type(value) == "table" then return value end
    return nil
  end

  local function shapeSpecies(id)
    local base = record(id)
    if not base then return nil end
    build()
    -- A form asked for DIRECTLY still has to report a displayable number.
    -- Its own `dex` is the synthetic registration key (Mega Charizard Y
    -- registers under 30035), so baseDex has to come from its base species
    -- or the caller is handed the very number this API exists to hide.
    if base.baseSpecies and base.form then
      local parent = record(base.baseSpecies)
      return withExtras(M.shape(id, base, nil, parent and parent.dex or nil))
    end
    local forms
    for _, formId in ipairs(formsOf[id] or {}) do
      local formRecord = record(formId)
      if formRecord then
        forms = forms or {}
        forms[#forms + 1] = withExtras(M.shape(formId, formRecord, nil, base.dex))
      end
    end
    return withExtras(M.shape(id, base, forms))
  end

  -- --- the published surface

  mod.exports.apiVersion = M.API_VERSION

  -- statsBySpecies("CHARIZARD") / statsBySpecies("CHARIZARD_MEGA_X")
  mod.exports.statsBySpecies = function(id)
    if type(id) ~= "string" then return nil end
    return shapeSpecies(id)
  end

  -- statsByDex(6) -> Charizard, with its megas and gigantamax under .forms
  mod.exports.statsByDex = function(number)
    number = tonumber(number)
    if not number then return nil end
    build()
    local id = index[number]
    if not id then return nil end
    return shapeSpecies(id)
  end

  -- The directory: { { dex = 1, id = "BULBASAUR", name = "Bulbasaur",
  --                    forms = 0 }, ... } ascending by dex.  Deliberately
  -- thin -- it is for building a menu or resolving a name, and a caller that
  -- wants stats asks for the one species it actually needs.
  mod.exports.listSpecies = function()
    build()
    local out = {}
    for number, id in pairs(index) do
      local value = record(id)
      -- `formIds` so a consumer can enumerate a species' forms and then ask
      -- for the ones it wants by id, without a second pass over the whole
      -- roster.  Mega Charizard X and Y are BOTH national dex No. 6 -- the
      -- games have one entry for Charizard with its forms inside it, and so
      -- does this: a form is never its own row here.  Address it by id.
      local ids = {}
      for i, formId in ipairs(formsOf[id] or {}) do ids[i] = formId end
      out[#out + 1] = {
        dex = number,
        id = id,
        name = value and value.name or id,
        forms = #ids,
        formIds = ids,
      }
    end
    table.sort(out, function(a, b) return a.dex < b.dex end)
    return out
  end

  -- Just the alternate forms of one species, by id or dex number.
  mod.exports.formsOf = function(idOrDex)
    build()
    local id = type(idOrDex) == "string" and idOrDex or index[tonumber(idOrDex or 0)]
    if not id then return {} end
    local out = {}
    for _, formId in ipairs(formsOf[id] or {}) do
      local value = record(formId)
      if value then
        local baseRecord = record(id)
        out[#out + 1] = withExtras(M.shape(formId, value, nil,
          baseRecord and baseRecord.dex or nil))
      end
    end
    return out
  end

  return true
end

setmetatable(M, { __call = function(_, mod) return M.install(mod) end })

return M

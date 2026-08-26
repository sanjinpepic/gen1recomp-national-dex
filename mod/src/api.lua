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

-- 2: added moveById / listMoves and the sharded move payload behind them.
-- 3: added evolutionsOf / listEvolutions and the sharded evolution payload
--    behind them.  Nothing that existed at 1 or 2 changed meaning, so a
--    consumer written against either keeps working -- which is exactly what
--    the >= check is for.
-- 4: added abilityById / listAbilities and the sharded ability payload behind
--    them.  Additive in the same way: nothing below 4 changed meaning.
-- 5: added itemById / listItems and the sharded item catalogue behind them.
--    Additive again; nothing below 5 changed meaning.
M.API_VERSION = 5

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

-- Builds a lazy index+shard lookup for one `mod`, with its own cache --
-- returned as a pair of functions so M.install can capture one instance per
-- installed mod per tree rather than sharing state across calls.  The species
-- extras and the move payload are the same shape (one index.lua mapping key
-- -> shard number, plus zero-padded shard files), so they share this rather
-- than carrying two copies that can drift.
local function makeShardLookup(mod, indexPath, pathFor)
  -- nil = not yet attempted; false = attempted, unavailable (missing or
  -- unreadable); a table = loaded.  Distinguishing nil from false is what
  -- makes this "try once, then cache the answer either way" instead of
  -- re-reading a genuinely missing file on every single call.
  local index
  local shards = {}

  local function getIndex()
    if index == nil then
      local loaded = loadDataModule(mod, indexPath)
      index = (type(loaded) == "table") and loaded or false
    end
    return index or nil
  end

  local function getShard(number)
    if shards[number] == nil then
      local loaded = loadDataModule(mod, pathFor(number))
      shards[number] = (type(loaded) == "table") and loaded or false
    end
    return shards[number] or nil
  end

  -- The record for one key, or nil -- missing index, missing shard, a key
  -- absent from the index, or a shard that doesn't carry that key after all
  -- (an index/shard gone stale relative to each other) all answer nil the
  -- same way. Never raises.
  local function lookup(id)
    local idx = getIndex()
    local shardNumber = idx and idx[id]
    if not shardNumber then return nil end
    local shard = getShard(shardNumber)
    return shard and shard[id] or nil
  end

  -- Every key the index knows, sorted.  One small read; the shards stay
  -- untouched, which is the point of answering a directory question from the
  -- index rather than by walking the payload.
  local function keys()
    local idx = getIndex()
    local out = {}
    if not idx then return out end
    for id in pairs(idx) do out[#out + 1] = id end
    table.sort(out)
    return out
  end

  return lookup, keys
end

-- --------------------------------------------------------------- moves load
--
-- The complete PokeAPI record for every one of the 833 moves anything in this
-- mod's data can learn, built by tools/build_moves.py into
-- data/moves/generated/api/<NNN>.lua plus an index.lua mapping move id ->
-- shard number.  Sharded and lazily loaded for the identical reason the
-- species extras are, and read by NOTHING ELSE: none of it is registered, and
-- the game never looks at it.
--
-- What a consumer gets that the registry does not carry: the English effect
-- text (short and long), the PokeAPI move id and slug, the damage class,
-- target, generation, the whole `meta` block (ailment and its chance, flinch
-- and stat chance, crit rate, drain, healing, hit and turn counts) and the
-- stat-change rows.
--
-- Two fields are this mod's own answer rather than PokeAPI's, and a consumer
-- reading the `moves` REGISTRY needs them: `gen1Effect`/`gen2Effect` are the
-- effect id the move is registered with on that generation, and
-- `gen1EffectModeled`/`gen2EffectModeled` say whether that id is the move's
-- real behaviour or a PLACEHOLDER.  A record with EffectModeled false is
-- registered so the move exists by name and stats; its effect is plain
-- damage, not what the move does, and this mod refuses to put it in any
-- learnset.  Treat a false there as "this engine cannot execute this move".
-- ---------------------------------------------------------- abilities load
--
-- Built by tools/build_abilities.py into data/abilities/generated/api/<NNN>.lua
-- plus an index.lua mapping ability id -> shard number.  Same lazy sharded
-- shape as the payloads above.
--
-- DISPLAY AND HANDOFF DATA, AND NOTHING ELSE. Neither engine in this project
-- has an ability system -- Gen 1 and Gen 2 carts predate the concept entirely
-- -- so nothing here executes and no `modeled` flag is carried: there is
-- nothing for an ability to be modeled AGAINST, and a uniformly false boolean
-- would imply a possibility that does not exist. Species records name their
-- abilities today and say nothing about what they do; this is what they do,
-- for a dex page to show and for an engine that HAS abilities to read.
--
-- No structured meta either, unlike moves. PokeAPI gives a move a `meta`
-- object this mod reads straight; it gives an ability one English sentence and
-- one longer paragraph. Deriving structure from that prose by pattern-matching
-- would be inventing data and calling it extracted.
-- -------------------------------------------------------------- items load
--
-- Built by tools/build_items.py into data/items/generated/api/<NNN>.lua plus an
-- index.lua mapping item id -> shard number.  Same lazy sharded shape as
-- everything above.
--
-- A CATALOGUE, NOT A REGISTRY, and the distinction matters more here than
-- anywhere else in this mod.  The dex describes 1025 species most of which
-- never appear, 833 moves most of which never execute, and 313 abilities none
-- of which do -- describing has never implied existing.  Items are the first
-- thing it carries that it COULD make real, because registering an item is
-- what puts it in a player's bag.  This mod registers none of them.
--
-- battle_forms owns its own Z-Crystals, Mega Stones, Band, Orb and Shards: it
-- registers them, triggers them, and decides when they are usable.  This
-- payload is where it can read one line of display text instead of carrying a
-- second copy.  With battle_forms uninstalled a player sees no Mega Stone
-- anywhere -- and the dex can still say what one is.
local ITEMS_INDEX_PATH = "data/items/generated/api/index.lua"
local ITEMS_FILENAME_WIDTH = 3

local function itemsShardPath(number)
  return string.format("data/items/generated/api/%0"
    .. ITEMS_FILENAME_WIDTH .. "d.lua", number)
end

local ABILITIES_INDEX_PATH = "data/abilities/generated/api/index.lua"
local ABILITIES_FILENAME_WIDTH = 3

local function abilitiesShardPath(number)
  return string.format("data/abilities/generated/api/%0"
    .. ABILITIES_FILENAME_WIDTH .. "d.lua", number)
end

local MOVES_INDEX_PATH = "data/moves/generated/api/index.lua"
-- must match build_moves.py's write_shards() zero-padding, exactly as
-- EXTRAS_FILENAME_WIDTH must match write_extras()'s
local MOVES_FILENAME_WIDTH = 3

local function movesShardPath(number)
  return string.format("data/moves/generated/api/%0" .. MOVES_FILENAME_WIDTH
    .. "d.lua", number)
end

-- --------------------------------------------------------- evolutions load
--
-- Built by tools/build_evolutions.py into data/evolutions/generated/<NNN>.lua
-- plus an index.lua mapping species id -> shard number.  Same lazy sharded
-- shape as the two payloads above, and read by nothing else.
--
-- DISPLAY DATA.  It is deliberately NOT the registered `evolutions` field,
-- which stays `{}` on every record this mod supplies: that field's `method`
-- is an f.id("evolution_methods") reference into a fixed per-generation
-- vocabulary (Red's {method, level, item, species}, Gold's {method, level,
-- item, into, time, comparison}), and friendship, location, held item, time
-- of day, a known move, trade-with-item, gender, weather and party state
-- have no honest id in either.  An approximate id would state in the
-- engine's own words that a species evolves a way it does not, and
-- Schemas.crossValidate would reject an invented one outright.  So a
-- consumer reading this is looking at what to DRAW, never at something the
-- battle engine will act on.
--
-- One record per species and per alternate form that has an evolution of its
-- own, carrying:
--
--   id/dex/name       the registered id, the DISPLAYABLE national dex number
--                     (a form reports its base species' number, never its
--                     own synthetic registration key) and the name the
--                     registered record carries
--   chainId           PokeAPI's evolution-chain number, so two records can
--                     be recognised as relatives without walking anything
--   chain             every id in this record's chain, root first, in
--                     evolution order -- the walk list for drawing the whole
--                     family from any member of it
--   stage             1-based depth in `chain`, for indenting that drawing
--   evolvesFrom       { id, dex, name, text, methods } or nil
--   evolvesInto       zero or more of the same shape, one per TARGET
--   baseSpecies/form  on a form record only
--
-- `methods` is every distinct way the evolution is known to happen, the one
-- PokeAPI marks current first (`isDefault`); the group's `text` is that
-- first one's sentence, which is what a page with room for a single line
-- should print.  A method carries its human-readable `text`, its PokeAPI
-- `trigger`, the `versionGroup` it was observed in, and whichever condition
-- fields apply (level, item, heldItem, location, timeOfDay, minHappiness,
-- knownMove, gender, region, tradeSpecies, ...) as raw PokeAPI slugs, so a
-- consumer that wants to word it differently has the parts.
--
-- Chains are the connected components of the resolved-id graph, NOT
-- PokeAPI's species tree: a regional variant whose evolution differs is its
-- own chain (YAMASK_GALAR -> RUNERIGUS is two nodes and does not mention
-- Yamask or Cofagrigus), which is the only arrangement that draws right.
local EVOLUTIONS_INDEX_PATH = "data/evolutions/generated/index.lua"
-- must match build_evolutions.py's write_shards() zero-padding, exactly as
-- MOVES_FILENAME_WIDTH must match build_moves.py's
local EVOLUTIONS_FILENAME_WIDTH = 3

local function evolutionsShardPath(number)
  return string.format("data/evolutions/generated/%0" .. EVOLUTIONS_FILENAME_WIDTH
    .. "d.lua", number)
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

  -- One lookup per tree (each with its own index/shard cache) per installed
  -- mod -- see makeShardLookup above.
  local extrasFor = makeShardLookup(mod, EXTRAS_INDEX_PATH, extrasShardPath)
  local moveFor, moveIds = makeShardLookup(mod, MOVES_INDEX_PATH, movesShardPath)
  local abilityFor, abilityIds =
    makeShardLookup(mod, ABILITIES_INDEX_PATH, abilitiesShardPath)
  local itemFor, itemIds = makeShardLookup(mod, ITEMS_INDEX_PATH, itemsShardPath)
  local evolutionFor, evolutionIds =
    makeShardLookup(mod, EVOLUTIONS_INDEX_PATH, evolutionsShardPath)

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

  -- moveById("FLAMETHROWER") -> the complete PokeAPI record for one move, or
  -- nil for an id this mod has no data for (the cart's own moves that nothing
  -- in the national dex can learn are the realistic case).  A COPY, like
  -- everything else here, so a consumer mutating the reply cannot reach the
  -- cached shard.  See the moves-load section above for the fields, and in
  -- particular for what gen1EffectModeled/gen2EffectModeled mean -- a
  -- consumer that acts on a move's effect must check them.
  --
  -- The id is the one the move is REGISTERED under (the engine's own spelling
  -- where the cart already had the move, e.g. PSYCHIC_M); `strippedId` on the
  -- reply is the separator-free spelling the species extras' movesFull and
  -- movesByMethod use, for reconciling the two.
  mod.exports.moveById = function(id)
    if type(id) ~= "string" then return nil end
    local record = moveFor(id)
    if type(record) ~= "table" then return nil end
    return deepCopy(record)
  end

  -- Every move id this mod carries data for, sorted.  Deliberately thin for
  -- the same reason listSpecies is -- it is for building a menu or checking
  -- membership, and a caller that wants a move's numbers asks moveById for
  -- the one it needs rather than paying for all 833.
  mod.exports.listMoves = function()
    return moveIds()
  end

  -- abilityById("INTIMIDATE") -> what that ability DOES, or nil for an id this
  -- mod has no record for.  A COPY, like every other reply here.
  --
  -- The id is the ability's name uppercased with separators removed, which is
  -- the same spelling a species' own extras record can be reduced to: an
  -- extras entry says `name = "Vital Spirit"`, and VITALSPIRIT is the key.
  -- Matching the move ids' convention rather than inventing a third.
  --
  -- Fields: id, slug, name, abilityId (PokeAPI's own number), generation,
  -- shortEffect, effect, speciesCount, effectChanges.
  --
  -- NOTHING HERE EXECUTES on either engine -- see the abilities-load section
  -- above.  A consumer on this project's own games should treat a reply as
  -- text to display; one running an engine that has abilities has the whole
  -- behaviour in `effect`.
  --
  -- `effectChanges` is the field to read before implementing anything: it is
  -- PokeAPI's own record of an ability whose behaviour CHANGED between
  -- generations, so an implementer working from `effect` alone would get
  -- those wrong.  Empty for the great majority.
  mod.exports.abilityById = function(id)
    if type(id) ~= "string" then return nil end
    local record = abilityFor(id)
    if type(record) ~= "table" then return nil end
    return deepCopy(record)
  end

  -- Every ability id this mod carries data for, sorted.  Thin for the same
  -- reason listMoves and listSpecies are: it is for building a menu or
  -- checking membership, and a caller wanting one ability's text asks
  -- abilityById for it.
  mod.exports.listAbilities = function()
    return abilityIds()
  end

  -- itemById("LEFTOVERS") -> what that item is and does, or nil.  A COPY, like
  -- every other reply here.
  --
  -- Fields: id, slug, name, itemId (PokeAPI's own number), category (one of
  -- 54), attributes (a list from a fixed 8 -- `holdable`, `usable-in-battle`,
  -- `consumable` and friends), flingPower where the item can be flung at all,
  -- shortEffect, effect, heldBySpeciesCount.
  --
  -- NOTHING HERE IS REGISTERED -- see the items-load section above.  A reply
  -- describes an item; it does not put one in anybody's bag.
  --
  -- THE `--held` FALLBACK.  PokeAPI models a Z-Crystal as TWO records: the bag
  -- item (`electrium-z--bag`, category "unused") and the held one
  -- (`electrium-z--held`, category "z-crystals").  A caller naming the item
  -- means the held one essentially always, and asking for ELECTRIUMZ would
  -- otherwise miss entirely -- so a bare id that finds nothing is retried once
  -- with HELD appended.  Deliberately narrow: one suffix, tried once, only
  -- after an exact miss.  Guessing at ids in general is how a lookup starts
  -- answering plausibly instead of correctly.
  mod.exports.itemById = function(id)
    if type(id) ~= "string" then return nil end
    local record = itemFor(id)
    if type(record) ~= "table" then record = itemFor(id .. "HELD") end
    if type(record) ~= "table" then return nil end
    return deepCopy(record)
  end

  -- Every item id this mod carries data for, sorted.  Thin for the same reason
  -- listMoves and listAbilities are -- and thinner still in practice, because
  -- there are 2222 of them and a caller wanting one asks itemById.
  mod.exports.listItems = function()
    return itemIds()
  end

  -- evolutionsOf("EEVEE") / evolutionsOf(133) -> what to DRAW for one
  -- species' evolution chain, or nil for an id this mod has no data for.  See
  -- the evolutions-load section above for the record's fields and, more
  -- importantly, for why none of this is the registered `evolutions` field --
  -- a consumer must not feed any of it to something that evolves a mon.
  --
  -- A dex number resolves to the species that owns it, so a FORM is only
  -- reachable by id: Alolan Raichu and Raichu are both No. 26, and the number
  -- has to keep answering the one a player asked for.  A form that has no
  -- evolution of its own answers nil rather than borrowing its base
  -- species' -- Mega Charizard X does not evolve from Charmeleon at level 36,
  -- and saying so would be an invention.  Read `baseSpecies` off the form's
  -- own record (statsBySpecies) and ask again for the base species' chain if
  -- that is what the page wants to show.
  mod.exports.evolutionsOf = function(idOrDex)
    local id = idOrDex
    if type(id) ~= "string" then
      local number = tonumber(idOrDex)
      if not number then return nil end
      build()
      id = index[number]
      if not id then return nil end
    end
    local found = evolutionFor(id)
    if type(found) ~= "table" then return nil end
    return deepCopy(found)
  end

  -- Every id this mod carries evolution data for, sorted -- the 1025 species
  -- plus the alternate forms that evolve differently from their base.  Thin
  -- for the same reason listSpecies and listMoves are.
  mod.exports.listEvolutions = function()
    return evolutionIds()
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

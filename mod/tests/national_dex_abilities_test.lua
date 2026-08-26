-- The ability payload, against the REAL built dataset rather than a fixture.
--
-- What this suite is really guarding is a promise about SCOPE. Neither engine
-- in this project has an ability system -- Gen 1 and Gen 2 carts predate the
-- concept -- so nothing here executes and nothing here should ever pretend to.
-- The value is that every species record already NAMES its abilities and says
-- nothing about what they do; this payload is what they do, for a dex page to
-- show and for an engine that has abilities to read.
--
-- The check that matters most is coverage: an ability a species names but the
-- payload has no record for is a label with nothing behind it, which is the
-- exact state this was built to end.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local MOD = arg[0]:gsub("[/\\]tests[/\\][^/\\]+$", "")

local index = dofile(MOD .. "/data/abilities/generated/api/index.lua")
local shards = {}
local function abilityFor(id)
  local number = index[id]
  if not number then return nil end
  shards[number] = shards[number]
    or dofile(string.format("%s/data/abilities/generated/api/%03d.lua", MOD, number))
  return shards[number][id]
end

local function strip(text)
  return (tostring(text):upper():gsub("[^A-Z0-9]", ""))
end

-- --- there is a payload at all ----------------------------------------------
local count = 0
for _ in pairs(index) do count = count + 1 end
T.check(count > 200, "the ability index carries a real payload (" .. count .. ")")

-- --- every ability a species names has a record -----------------------------
-- The whole point. A species saying "Vital Spirit" with nothing behind it is
-- what this payload exists to fix, so a name with no record is a regression
-- even if everything else here passes.
local extrasIndex = dofile(MOD .. "/data/species/generated/extras/index.lua")
local extrasShards = {}
local function extrasFor(id)
  local number = extrasIndex[id]
  if not number then return nil end
  extrasShards[number] = extrasShards[number]
    or dofile(string.format("%s/data/species/generated/extras/%03d.lua", MOD, number))
  return extrasShards[number][id]
end

local named, orphans, carriers = {}, {}, 0
for speciesId in pairs(extrasIndex) do
  local record = extrasFor(speciesId)
  for _, ability in ipairs((record and record.abilities) or {}) do
    local key = strip(ability.name or "")
    if key ~= "" and not named[key] then
      named[key] = true
      carriers = carriers + 1
      if not index[key] then orphans[#orphans + 1] = tostring(ability.name) end
    end
  end
end
T.check(carriers > 0, "species records name abilities at all (" .. carriers .. " distinct)")
T.eq(#orphans, 0, "every ability a species names has a record ("
  .. (#orphans > 0 and table.concat(orphans, ", ") or "none missing") .. ")")

-- --- the record's shape -----------------------------------------------------
-- Checked on a known ability rather than the first the iterator hands back, so
-- a failure names something a reader can look up.
local intimidate = abilityFor("INTIMIDATE")
T.check(intimidate ~= nil, "INTIMIDATE has a record")
if intimidate then
  T.eq(intimidate.id, "INTIMIDATE", "the id is the key")
  T.eq(intimidate.slug, "intimidate", "with PokeAPI's own slug alongside it")
  T.eq(intimidate.name, "Intimidate", "and a display name a page can print")
  T.eq(type(intimidate.abilityId), "number", "PokeAPI's own number is carried")
  T.eq(intimidate.generation, "generation-iii", "and the generation it arrived in")
  T.check(#intimidate.shortEffect > 0, "the one-line effect is present")
  T.check(#intimidate.effect > 0, "and the full text")
  T.check(intimidate.speciesCount > 0, "with how many species carry it")
end

-- --- the id convention ------------------------------------------------------
-- Separator-free uppercase, matching the MOVE ids rather than inventing a
-- third spelling. This is what lets a consumer reduce a species extras entry
-- ("Vital Spirit") to a key without a lookup table.
local badKeys = {}
for id in pairs(index) do
  if id ~= strip(id) then badKeys[#badKeys + 1] = id end
end
T.eq(#badKeys, 0, "every id is separator-free uppercase ("
  .. (#badKeys > 0 and table.concat(badKeys, ", ") or "all clean") .. ")")
T.check(abilityFor("VITALSPIRIT") ~= nil,
  "so a species' own 'Vital Spirit' reduces straight to a key")

-- --- no modelled flag, deliberately ----------------------------------------
-- Moves carry gen1EffectModeled/gen2EffectModeled because the engine HAS an
-- effect system some of them map onto. There is nothing for an ability to be
-- modelled against, and a uniformly false boolean would imply a possibility
-- that does not exist. A future engine that grows abilities can add one; this
-- payload must not ship a fake.
local flagged = {}
for id in pairs(index) do
  local record = abilityFor(id)
  for _, field in ipairs({ "effectModeled", "gen1EffectModeled",
                           "gen2EffectModeled", "modeled" }) do
    if record and record[field] ~= nil then flagged[#flagged + 1] = id .. "." .. field end
  end
end
T.eq(#flagged, 0, "no record claims an engine models it ("
  .. (#flagged > 0 and table.concat(flagged, ", "):sub(1, 90) or "none do") .. ")")

-- --- effect text is actually there -----------------------------------------
-- An empty string is how this payload says "PokeAPI had no English text",
-- which is honest but useless to a consumer -- so it must stay rare. A build
-- that started emitting them wholesale would mean the fetch or the language
-- filter broke, and everything else here would still pass.
local blank = 0
for id in pairs(index) do
  local record = abilityFor(id)
  if not record or not record.shortEffect or record.shortEffect == "" then
    blank = blank + 1
  end
end
T.check(blank <= 5, "at most a handful carry no effect text (" .. blank .. ")")

-- --- effectChanges, the field an implementer must read ----------------------
-- PokeAPI's own record of an ability whose behaviour CHANGED between
-- generations. Somebody implementing from `effect` alone would get those
-- wrong, which is why it is carried rather than flattened away.
local changed, shaped = 0, true
for id in pairs(index) do
  local record = abilityFor(id)
  for _, change in ipairs((record and record.effectChanges) or {}) do
    changed = changed + 1
    if type(change.versionGroup) ~= "string" or type(change.effect) ~= "string" then
      shaped = false
    end
  end
end
T.check(changed > 0, "some abilities record a behaviour change (" .. changed .. ")")
T.eq(shaped, true, "and each names its version group and its text")

T.finish("national_dex_abilities")

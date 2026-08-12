-- Headless loader test proving the national_dex mod boots clean on BOTH
-- Gen 1 (Red/Blue/Yellow) and Gen 2 (Gold) engines from one source tree.
--
-- Run from a Gen1Recomp engine checkout (no ROM needed):
--   luajit "C:/path/to/dev/tests/gen2_test.lua"
--
-- Unlike tests/national_dex_test.lua, this mounts the REAL generated payload
-- (data/species/generated/national.lua, type_chart_modern.lua, extras/*) --
-- a synthetic fixture cannot exercise src/gen2shape.lua's reshaping against
-- the shapes build_national_dex.py actually emits, nor prove the modern type
-- chart's 324 rows against the ids the engine itself already claims.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local scriptPath = arg and arg[0] or "../tests/gen2_test.lua"
local ROOT = scriptPath:gsub("[/\\]tests[/\\][^/\\]+$", "")
local MOD_DIR = ROOT .. "/national_dex_mod"

-- ------- mount every file the mod ships (manifest, code, and the real
-- generated data -- extras/ included even though nothing in the load path
-- reads it eagerly today, because "every file the mod ships" is the whole
-- point: a future change that starts reading a shard during load must be
-- caught here, not in a fixture that never had the shard to begin with).
local MOD_FILES = {
  "manifest.json", "mod.card", "main.lua",
  "src/nationaldex.lua", "src/dexpage.lua", "src/summarystats.lua",
  "src/api.lua", "src/gen2shape.lua", "src/dexscroll.lua", "src/dexview.lua",
  "src/gen2dexlist.lua",
  "src/gen2summary.lua",
  "data/species/generated/type_chart_modern.lua",
  "data/species/generated/national.lua",
  "data/species/generated/extras/index.lua",
}
-- extras/001.lua .. extras/034.lua, per tools/build_national_dex.py's
-- write_extras() shard count as of this build (dev/national_dex_mod/data/
-- species/generated/extras on disk: 34 numbered shards + index.lua)
for shard = 1, 34 do
  MOD_FILES[#MOD_FILES + 1] =
    ("data/species/generated/extras/%03d.lua"):format(shard)
end

local mount = {}
for _, rel in ipairs(MOD_FILES) do
  local handle = assert(io.open(MOD_DIR .. "/" .. rel, "rb"),
    "missing mod source file: " .. rel)
  mount["mods/national_dex/" .. rel] = handle:read("*a")
  handle:close()
end

-- national_dex ON, modern chart active, on both boots -- same options both
-- generations run the mod's real registration path under, per the brief.
mount["options.lua"] = [==[return { modOptions = {
  ["national_dex"] = { type_chart = "modern", national_dex = "on" },
} }]==]

local fs = T.sdk.memfs(mount)

-- ------- what the fixture dataset actually is, and why Gen 2 needs help
--
-- tests/modkit/fixtures.lua's Fixtures.fresh() loads tests/fixture_data/,
-- a small ROM-free stand-in (pokemon.lua seeds exactly FIXMON_A/B/C, per
-- Fixtures.ids.species) -- nowhere near the 251 species a real Gold cart's
-- ROM import would have already registered.  Two consequences for a Gen 2
-- run against it:
--
--   1. data.gen2Constants does not exist at all in the fixture (grep across
--      tests/fixture_data and src/core/Data.lua turns up nothing).  On a
--      real boot src/core/Game2.lua:load builds it from data/generated/
--      constants.lua before mods:load runs; the SDK harness's opts.generation
--      only steers the LOADER's own schema/routing choice (Loader.lua:242),
--      a completely separate mechanism from src/gen2shape.lua's own runtime
--      probe (mod.content.constants:get("generation")).  Skipping this seed
--      is exactly the trap item 2 below is written to catch: the two would
--      silently disagree, and the mod would reshape nothing while still
--      being told (via opts.generation) that it runs on Gen 2.
--      tests/engine/gen2_content_registries.lua's goldData() sets
--      data.gen2Constants by hand for the same reason; this test follows
--      that established convention rather than inventing a new one.
--
--   2. #152-251 (Chikorita onward) do not exist in data.pokemon at all, so
--      nothing here can collide with a register the way Gold's own ROM
--      import would collide.  src/gen2shape.lua's romOwned() guard exists
--      PRECISELY to route those ids through :patch instead of :register --
--      :register throws on an id the registry already holds, :patch never
--      does, so an untested guard could quietly regress from :patch to
--      :register and this suite would still pass, having never given the
--      registry a #152-251 id to collide against.  A handful of stub species
--      are seeded below (real ids/dex numbers the mod's own national.lua
--      also defines, so the reshape runs against them exactly as it would
--      against a genuine Gold ROM import) to force that path to matter.
--      Each stub carries hp=77, a value neither the fixture nor the real
--      CHIKORITA/AMPHAROS/CELEBI record uses (the real ones are 45/90/100)
--      -- so if the guard ever called :register instead of :patch, the
--      registered payload would REPLACE the stub outright (Registry.lua's
--      fold: register under non-deep semantics assigns entry.value wholesale)
--      and hp would read as the mod's own number instead of staying 77.
--      :patch deep-merges over the stub unconditionally (fold() never checks
--      spec.semantics for patch), so hp=77 surviving is the tell.
local ROM_STUBS = {
  CHIKORITA = { id = "CHIKORITA", dex = 152, name = "Chikorita",
    types = { "GRASS" }, romSource = "gold_cart_stub",
    baseStats = { hp = 77, attack = 49, defense = 65, speed = 45, special = 65 } },
  AMPHAROS = { id = "AMPHAROS", dex = 181, name = "Ampharos",
    types = { "ELECTRIC" }, romSource = "gold_cart_stub",
    baseStats = { hp = 77, attack = 75, defense = 75, speed = 55, special = 95 } },
  CELEBI = { id = "CELEBI", dex = 251, name = "Celebi",
    types = { "PSYCHIC_TYPE", "GRASS" }, romSource = "gold_cart_stub",
    baseStats = { hp = 77, attack = 100, defense = 100, speed = 100, special = 100 } },
}

local function baseData(generation)
  local data = T.fixtures.fresh()
  if generation == 2 then
    data.gen2Constants = { generation = 2 }
    for id, record in pairs(ROM_STUBS) do
      data.pokemon[id] = record
    end
  end
  return data
end

-- ------- capture the mod's own print() line without losing it from the
-- console: forwarded to the real print as it comes in, and also kept so the
-- report below can quote it verbatim rather than re-deriving it from state.
local function withCapturedPrint(fn)
  local original = print
  local lines = {}
  print = function(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do parts[i] = tostring(select(i, ...)) end
    lines[#lines + 1] = table.concat(parts, "\t")
    original(...)
  end
  local ok, result = pcall(fn)
  print = original
  if not ok then error(result, 0) end
  return result, lines
end

-- The summary goes through mod.log:info, not print, so the loader stamps it
-- "[info] [national_dex] ..." -- NOT anchored at the start of the line, and
-- not the "[nationaldex]" spelling this matched when the mod still used a
-- bare print.  Both assertions below it went quietly dead at that change:
-- they searched for a line that no longer exists in that shape and reported
-- only "not printed", which reads like the mod fell silent rather than like
-- the test lost track of it.
local function nationaldexLine(lines)
  for _, line in ipairs(lines) do
    if line:find("%[national_dex%] gen=") then return line end
  end
  return nil
end

local function parseLine(line)
  if not line then return nil end
  -- `rows` joined the line when TYPE CHART became a three-era choice; it is
  -- captured rather than skipped so a future change to the applied-matchup
  -- count is visible here instead of quietly unparsed.
  local gen, chart, rows, patched, registered, text, skipped, rest =
    line:match(
      "%[national_dex%] gen=(%d+) chart=(%a+) rows=(%d+) patched=(%d+) "
      .. "registered=(%d+) text=(%d+) skipped=(%d+)(.*)")
  if not gen then return nil end
  return { gen = tonumber(gen), chart = chart, rows = tonumber(rows),
           patched = tonumber(patched), registered = tonumber(registered),
           text = tonumber(text), skipped = tonumber(skipped), rest = rest }
end

print("==================== national_dex: Gen 1 boot ====================")
local run1, lines1 = withCapturedPrint(function()
  return T.sdk.loadMod("national_dex", { fs = fs, data = baseData(1), generation = 1 })
end)

print("==================== national_dex: Gen 2 boot ====================")
local run2, lines2 = withCapturedPrint(function()
  return T.sdk.loadMod("national_dex", { fs = fs, data = baseData(2), generation = 2 })
end)

-- ------- 1. both boots loaded clean
--
-- run.mod.state is the real signal (per the brief) -- #run.errors is NOT
-- required to be zero here, and cannot be: national.lua's real learnset/
-- growthRate references are real engine move/growth-rate ids
-- (build_national_dex.py filters against the engine's own move table before
-- writing them), but tests/fixture_data/moves.lua and growth_rates only
-- carry the four FIX_* moves and whatever growth_rates the fixture seeds --
-- nowhere near enough to resolve a 1200-species production file.  Every
-- dangling reference Schemas.crossValidate finds lands in run.errors
-- unconditionally for an api-2 mod (src/mods/Loader.lua:1379-1389), so
-- loading the REAL data against the SDK's default fixture always produces
-- a large run.errors list -- that is the fixture's move table being tiny,
-- not the mod being broken.  What actually matters: every single one of
-- those errors is the SAME known shape (an unresolved moves/growth_rates
-- reference) and nothing else -- no duplicate-registration error, no love/
-- asset error, nothing crossValidate wasn't built to say -- classified below
-- instead of asserted away.
local function classifyErrors(errors)
  local counts, other = { moves = 0, growth_rates = 0 }, {}
  for _, message in ipairs(errors) do
    local registry = message:match("unresolved reference to ([%a_]+) ")
    if registry and counts[registry] ~= nil then
      counts[registry] = counts[registry] + 1
    else
      other[#other + 1] = message
    end
  end
  return counts, other
end

T.eq(run1.mod.state, "loaded",
  "gen1: mod state is loaded (errors: " .. tostring(run1.errors[1]) .. ")")
T.eq(run2.mod.state, "loaded",
  "gen2: mod state is loaded (errors: " .. tostring(run2.errors[1]) .. ")")

local counts1, other1 = classifyErrors(run1.errors)
local counts2, other2 = classifyErrors(run2.errors)
print(("gen1: run.errors has %d entries -- %d unresolved moves refs, "
  .. "%d unresolved growth_rates refs, %d of any other shape")
  :format(#run1.errors, counts1.moves, counts1.growth_rates, #other1))
print(("gen2: run.errors has %d entries -- %d unresolved moves refs, "
  .. "%d unresolved growth_rates refs, %d of any other shape")
  :format(#run2.errors, counts2.moves, counts2.growth_rates, #other2))
T.eq(#other1, 0,
  "gen1: every run.errors entry is a known fixture-vs-production reference "
  .. "gap, nothing else (first unexpected: " .. tostring(other1[1]) .. ")")
T.eq(#other2, 0,
  "gen2: every run.errors entry is a known fixture-vs-production reference "
  .. "gap, nothing else (first unexpected: " .. tostring(other2[1]) .. ")")

-- ------- 2. the [nationaldex] line itself, and the generation probe
local line1, line2 = nationaldexLine(lines1), nationaldexLine(lines2)
print("gen1 line: " .. tostring(line1))
print("gen2 line: " .. tostring(line2))
T.check(line1 ~= nil, "gen1: the [nationaldex] summary line printed")
T.check(line2 ~= nil, "gen2: the [nationaldex] summary line printed")

local parsed1, parsed2 = parseLine(line1), parseLine(line2)
if parsed1 then
  T.eq(parsed1.gen, 1, "gen1 boot: the line's gen= field reads 1")
end
if parsed2 then
  T.eq(parsed2.gen, 2,
    "gen2 boot: the line's gen= field reads 2 -- if this fails the "
    .. "generation probe (src/gen2shape.lua's mod.content.constants:get"
    .. "(\"generation\")) is broken or the harness failed to seed "
    .. "data.gen2Constants.generation the way a real Gold boot would")
end

-- ------- 3. Gen 2 record shape: Chikorita (ROM-owned, patched) and
-- Treecko (beyond ROM_DEX_MAX, freshly registered in the Gen 2 shape)
local chikorita = run2.data.pokemon.CHIKORITA
T.check(chikorita ~= nil, "gen2: CHIKORITA resolves after load")
if chikorita then
  T.eq(chikorita.romSource, "gold_cart_stub",
    "gen2: CHIKORITA kept its stub marker -- proves the ROM-owned path "
    .. "used :patch, not :register (a :register would have replaced the "
    .. "whole record and dropped this field)")
  T.eq(chikorita.baseStats.hp, 77,
    "gen2: CHIKORITA's stub hp survived the merge -- the same :patch-not-"
    .. ":register tell, read off baseStats instead of a bare field")
  T.eq(chikorita.spAttack, 49, "gen2: CHIKORITA's patch applied the modern Sp.Atk split")
  T.eq(chikorita.spDefense, 65, "gen2: CHIKORITA's patch applied the modern Sp.Def split")
end

local treecko = run2.data.pokemon.TREECKO
T.check(treecko ~= nil, "gen2: TREECKO (dex 252, beyond Gold's ROM) registers")
if treecko then
  T.check(type(treecko.baseStats) == "table", "gen2: TREECKO carries a baseStats table")
  if type(treecko.baseStats) == "table" then
    T.check(type(treecko.baseStats.specialAttack) == "number",
      "gen2: TREECKO's baseStats.specialAttack is a number")
    T.check(type(treecko.baseStats.specialDefense) == "number",
      "gen2: TREECKO's baseStats.specialDefense is a number")
    T.check(treecko.baseStats.special == nil,
      "gen2: TREECKO's baseStats.special is absent (Gen 2 schema, not Gen 1's)")
  end
  T.check(type(treecko.levelMoves) == "table", "gen2: TREECKO carries a levelMoves table")
  T.check(treecko.learnset == nil, "gen2: TREECKO carries no Gen 1 learnset field")
  T.check(treecko.level1Moves == nil, "gen2: TREECKO carries no Gen 1 level1Moves field")
  T.check(type(treecko.picSize) == "number", "gen2: TREECKO's picSize is a number")
end

-- ------- 4. type_chart collisions: how many of the mod's ids were already
-- claimed before nationaldex.lua's own registrations ran, and why
--
-- src/mods/Builtins.lua registers the vanilla type chart (src/battle/
-- TypeChart.lua's 15 bare type ids, plus every matchup row the dataset's
-- OWN data.type_chart.matchups carries) into the SAME registry the mod
-- writes into, before any mod runs, on EVERY generation alike -- type_chart
-- is not one of the registries Gen 2 swaps a different registrant in for
-- (Builtins.lua's GEN2_REGISTRANTS table has no "type_chart" entry).  So the
-- baseline is identical on both boots as long as the dataset is: computed
-- here with a mod-free load (T.sdk.loadNone) against the exact same fixture
-- data, which is "before the mod's own registrations would run" made literal
-- rather than inferred from the skipped count alone.
local Chart = dofile(MOD_DIR .. "/data/species/generated/type_chart_modern.lua")
local chartIds = {}
for id in pairs(Chart.types) do chartIds[#chartIds + 1] = id end
for _, row in ipairs(Chart.rows) do
  chartIds[#chartIds + 1] = row.attacker .. ">" .. row.defender
end
table.sort(chartIds)

local function collisionReport(generation)
  -- Deliberately NOT `fs = fs`: that memfs's "mods" directory holds
  -- national_dex itself, and Loader:_discover lists the whole "mods"
  -- directory regardless of which mod ids Sdk.loadMods was asked to return
  -- -- reusing it here would load the mod again and call every one of its
  -- own successful registrations a "pre-existing collision" against itself.
  -- Omitting fs falls back to Sdk.loadMods' own aliasFs with an empty alias
  -- table, whose "mods" listing is always empty (tests/modkit/sdk.lua's
  -- aliasFs), which is what makes this a genuine mod-free boot -- the same
  -- one Sdk.loadNone is documented as being for.
  local baseline = T.sdk.loadNone({ data = baseData(generation), generation = generation })
  local collided, examples = 0, {}
  for _, id in ipairs(chartIds) do
    if baseline.loader.content.type_chart:get(id) ~= nil then
      collided = collided + 1
      if #examples < 6 then examples[#examples + 1] = id end
    end
  end
  baseline.release()
  return collided, examples
end

local collided1, examples1 = collisionReport(1)
local collided2, examples2 = collisionReport(2)

print(("gen1: %d/%d of the mod's chart ids are already registered before "
  .. "the mod runs; examples: %s"):format(collided1, #chartIds, table.concat(examples1, ", ")))
print(("gen2: %d/%d of the mod's chart ids are already registered before "
  .. "the mod runs; examples: %s"):format(collided2, #chartIds, table.concat(examples2, ", ")))

T.eq(collided1, collided2,
  "the pre-mod type_chart baseline is identical on both generations -- "
  .. "type_chart is not one of the registries Gen 2 routes to a different "
  .. "registrant, so the same ids collide either way")

if parsed1 then
  print(("gen1: printed skipped=%d, of which %d attributable to type_chart "
    .. "id collisions (the remainder, if any, is national.register/patch/"
    .. "text failures unrelated to the chart)")
    :format(parsed1.skipped, collided1))
end
if parsed2 then
  print(("gen2: printed skipped=%d, of which %d attributable to type_chart "
    .. "id collisions"):format(parsed2.skipped, collided2))
end

-- The era chart winning, asserted end-to-end instead of inferred from a skip
-- count of zero.  Both ids below are ones the engine registers ITSELF before
-- any mod runs, so until src/nationaldex.lua learned to :override them the
-- cart's own row survived and the era the player picked was a lie for every
-- pair of types the cart already knew about.  A skip count only says nothing
-- threw; these say the mod's number is the one the game will read.
local function multiplierOf(run, id)
  local row = run.loader.content.type_chart:get(id)
  return type(row) == "table" and row.multiplier or nil
end

for _, case in ipairs({ { run1, 1 }, { run2, 2 } }) do
  local run, generation = case[1], case[2]
  -- Gen 1's famous 0x, which MODERN puts at 2x -- the sharpest case there is.
  T.eq(multiplierOf(run, "GHOST>PSYCHIC_TYPE"), 20,
    ("gen%d: the MODERN chart's GHOST>PSYCHIC_TYPE beats the engine's own row")
      :format(generation))
  -- One of the six ids measured colliding on the mod-free baseline above.
  T.eq(multiplierOf(run, "FIRE>WATER"), 5,
    ("gen%d: the MODERN chart's FIRE>WATER beats the engine's own row")
      :format(generation))
end

run1.release()
run2.release()

T.finish("gen2_test")

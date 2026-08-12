-- Headless loader test for the national_dex mod.
--
-- Run from a Gen1Recomp engine checkout (no ROM needed; the fixture dataset
-- stands in for generated data):
--   luajit "C:/path/to/Pokemon Recomp Mod/tests/national_dex_test.lua"
--
-- The mod mounts through the SDK's in-memory filesystem, with small
-- synthetic copies of the generated payloads (the real files are built by
-- tools/build_national_dex.py into national_dex_mod/data/species/generated/;
-- the production data additionally gets a static dev-time verification
-- against the engine's move table, since the fixture moveset cannot resolve
-- real engine move ids).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local scriptPath = arg and arg[0] or "../tests/national_dex_test.lua"
local ROOT = scriptPath:gsub("[/\\]tests[/\\][^/\\]+$", "")

local MOD_FILES = {
  "manifest.json", "mod.card", "main.lua",
  "src/nationaldex.lua", "src/dexpage.lua", "src/summarystats.lua",
  "src/api.lua", "src/gen2shape.lua", "src/dexscroll.lua", "src/dexview.lua",
}
local mount = {}
for _, rel in ipairs(MOD_FILES) do
  local handle = assert(io.open(ROOT .. "/national_dex_mod/" .. rel, "rb"),
    "missing mod source file: " .. rel)
  mount["mods/national_dex/" .. rel] = handle:read("*a")
  handle:close()
end

-- Load-time options (Loader reads options.lua at the fs root): the dex is
-- ON and the modern chart active, so all registrations happen during load.
mount["options.lua"] = [==[return { modOptions = {
  ["national_dex"] = { type_chart = "modern", national_dex = "on" },
} }]==]

mount["mods/national_dex/data/species/generated/type_chart_modern.lua"] = [==[
return {
  types = {
    FAIRY = { name = "FAIRY", category = "physical" },
    DARK = { name = "DARK", category = "physical" },
  },
  rows = {
    { attacker = "FAIRY", defender = "DRAGON", multiplier = 0 },
    { attacker = "DARK", defender = "PSYCHIC_TYPE", multiplier = 20 },
  },
}
]==]
mount["mods/national_dex/data/species/generated/national.lua"] = [==[
return {
  patch = {
    -- ONLY what the engine's schema validates rides here -- exercised so
    -- the fixture proves the patch path stays clean too, not just register.
    -- FIXMON_A's complete modern data (movesFull/abilities/...) lives in
    -- the mounted extras/ shard below instead -- see EXTRAS_KEYS in
    -- tools/build_national_dex.py for why it never rides on this table.
    FIXMON_A = {
      types = { "GRASS", "FAIRY" },
    },
  },
  register = {
    FIXLUGIA = {
      id = "FIXLUGIA", dex = 1025, name = "FIXLUGIA",
      types = { "PSYCHIC_TYPE", "FLYING" },
      baseStats = { hp = 106, attack = 90, defense = 130, speed = 110, special = 154 },
      catchRate = 3, baseExp = 255,
      level1Moves = { "FIX_TACKLE" },
      growthRate = "MEDIUM_SLOW",
      learnset = {
        { level = 1, move = "FIX_TACKLE" },
        { level = 9, move = "FIX_EMBERISH" },
      },
      evolutions = {},
      spriteFront = "assets/sets/placeholder/front.png",
      spriteBack = "assets/sets/placeholder/back.png",
      frontSize = 5,
      dexEntry = { kind = "DIVING", heightFt = 17, heightIn = 1, weight = 476.2,
        heightM = 5.2, weightKg = 216, text = "NDEX_1025" },
      -- NOTE: no movesFull/movesByMethod/abilities/evYield/eggGroups/
      -- baseHappiness/growthRateName/genderRate here -- the complete
      -- modern data lives in the mounted extras/001.lua shard below and
      -- only ever reaches a caller through src/api.lua's lazy load, never
      -- by riding on the registered record.  This is the whole fix for the
      -- withdrawn 0.8.0 build: see EXTRAS_KEYS in build_national_dex.py.
    },
    -- an alternate-form record (build_national_dex.py's build_form_record):
    -- same table as a beyond-151 species, shares its BASE species' dex
    -- number instead of claiming a new one, and carries the two extra
    -- top-level keys (form/baseSpecies) plus the spAttack/spDefense split.
    FIXLUGIA_MEGA = {
      id = "FIXLUGIA_MEGA", dex = 1025, name = "fixlugia-mega",
      types = { "PSYCHIC_TYPE", "DARK" },
      baseStats = { hp = 106, attack = 150, defense = 90, speed = 130, special = 180 },
      spAttack = 180, spDefense = 120,
      catchRate = 3, baseExp = 255,
      level1Moves = { "FIX_TACKLE" },
      growthRate = "MEDIUM_SLOW",
      learnset = { { level = 1, move = "FIX_TACKLE" } },
      evolutions = {},
      spriteFront = "assets/sets/placeholder/front.png",
      spriteBack = "assets/sets/placeholder/back.png",
      frontSize = 5,
      dexEntry = { kind = "DIVING", heightFt = 20, heightIn = 0, weight = 600,
        heightM = 6.1, weightKg = 272, text = "NDEX_1025" },
      form = "MEGA",
      baseSpecies = "FIXLUGIA",
      -- likewise: its own abilities/evYield/movesFull live in the extras
      -- shard, keyed under FIXLUGIA_MEGA there, deliberately DIFFERENT from
      -- FIXLUGIA's -- the CHARIZARD_MEGA_Y-vs-CHARIZARD case (Drought vs
      -- Blaze), proven below through the API rather than the raw record.
    },
  },
  text = {
    NDEX_1025 = "It dwells in the deep.",
  },
}
]==]

-- The complete, unfiltered modern data: sharded exactly the way
-- tools/build_national_dex.py's write_extras() emits it (a species id ->
-- shard number index plus one file per shard), so src/api.lua's lazy loader
-- is exercised against the real file shape, not a shortcut.  FIXMON_A (a
-- PATCHED Kanto species) and FIXLUGIA/FIXLUGIA_MEGA (a registered species
-- and its form) share shard 1 on purpose -- proving the index, not just the
-- shard read, resolves each id independently.  FIXMON_B (seeded by
-- T.fixtures.fresh(), untouched by this mod) is deliberately absent from
-- the index entirely, covering "no extras for this species at all".
mount["mods/national_dex/data/species/generated/extras/index.lua"] = [==[
return {
  FIXMON_A = 1,
  FIXLUGIA = 1,
  FIXLUGIA_MEGA = 1,
}
]==]
mount["mods/national_dex/data/species/generated/extras/001.lua"] = [==[
return {
  FIXMON_A = {
    abilities = { { name = "Overgrow", slot = 1, hidden = false } },
    evYield = { hp = 0, attack = 0, defense = 0, spAttack = 1, spDefense = 0, speed = 0 },
    movesFull = {
      { level = 1, move = "FIXTACKLE", name = "Fix Tackle", slug = "fix-tackle" },
      { level = 7, move = "FIXGROWL", name = "Fix Growl", slug = "fix-growl" },
    },
    movesByMethod = {
      egg = { { move = "FIXCURSE", name = "Fix Curse", slug = "fix-curse" } },
    },
    eggGroups = { "Monster", "Grass" },
    baseHappiness = 70,
    growthRateName = "medium-slow",
    genderRate = 1,
  },
  -- the move ids below deliberately do NOT resolve to any FIX_* engine
  -- move -- that is the whole point of movesFull being unfiltered.
  FIXLUGIA = {
    abilities = {
      { name = "Pressure", slot = 1, hidden = false },
      { name = "Multiscale", slot = 3, hidden = true },
    },
    evYield = { hp = 3, attack = 0, defense = 0, spAttack = 0, spDefense = 0, speed = 0 },
    movesFull = {
      { level = 0, move = "FIXHATCH", name = "Fix Hatch", slug = "fix-hatch" },
      { level = 1, move = "FIX_TACKLE", name = "Fix Tackle", slug = "fix-tackle" },
      { level = 9, move = "FIX_EMBERISH", name = "Fix Emberish", slug = "fix-emberish" },
      { level = 40, move = "AEROBLAST", name = "Aeroblast", slug = "aeroblast" },
    },
    movesByMethod = {
      machine = {
        { move = "FIXSURF", name = "Fix Surf", slug = "fix-surf" },
        { move = "FIX_TACKLE", name = "Fix Tackle", slug = "fix-tackle" },
      },
      tutor = { { move = "FIXRECOVER", name = "Fix Recover", slug = "fix-recover" } },
    },
    eggGroups = { "No Eggs" },
    baseHappiness = 0,
    growthRateName = "slow",
    genderRate = -1,
  },
  -- a form's OWN abilities, deliberately different from FIXLUGIA's --
  -- exactly the CHARIZARD_MEGA_Y-vs-CHARIZARD case (Drought vs Blaze)
  FIXLUGIA_MEGA = {
    abilities = { { name = "Multiscale", slot = 1, hidden = false } },
    evYield = { hp = 3, attack = 3, defense = 0, spAttack = 0, spDefense = 0, speed = 0 },
    movesFull = {
      { level = 1, move = "FIX_TACKLE", name = "Fix Tackle", slug = "fix-tackle" },
    },
    movesByMethod = {},
    eggGroups = { "No Eggs" },
    baseHappiness = 0,
    growthRateName = "slow",
    genderRate = -1,
  },
}
]==]

local run = T.sdk.loadMod("national_dex",
  { fs = T.sdk.memfs(mount), data = T.fixtures.fresh() })
T.eq(#run.errors, 0, "national_dex loads clean (" .. tostring(run.errors[1]) .. ")")

local data = run.data

T.check(data.pokemon.FIXLUGIA ~= nil, "national dex registers beyond-151 species")
if data.pokemon.FIXLUGIA then
  T.same(data.pokemon.FIXLUGIA.types, { "PSYCHIC_TYPE", "FLYING" },
    "registered species carries its modern types")
  T.eq(data.pokemon.FIXLUGIA.dex, 1025, "registered species keeps its dex number")
  T.eq(data.pokemon.FIXLUGIA.dexEntry.text, "NDEX_1025",
    "registered species points at its dex text")
  T.eq(data.pokemon.FIXLUGIA.growthRate, "MEDIUM_SLOW",
    "registered species resolves its growth rate id")
  T.check(data.pokemon.FIXLUGIA.learnset ~= nil
    and #data.pokemon.FIXLUGIA.learnset == 2,
    "registered species carries its filtered learnset")
  if data.pokemon.FIXLUGIA.learnset and #data.pokemon.FIXLUGIA.learnset == 2 then
    T.eq(data.pokemon.FIXLUGIA.learnset[1].move, "FIX_TACKLE",
      "learnset slot 1 is the level-1 move")
    T.eq(data.pokemon.FIXLUGIA.learnset[2].move, "FIX_EMBERISH",
      "learnset slot 2 is the level-9 move")
    T.eq(data.pokemon.FIXLUGIA.learnset[2].level, 9,
      "learnset levels pass through")
  end
  -- The engine loads spriteFront/spriteBack through Sprites.path ->
  -- Assets.resolve, which rewrites only the assets/generated/ prefix.  A
  -- mod-relative path is therefore looked up at the *game* root, where it
  -- does not exist, and love.image.newImageData throws the instant the
  -- species is sent into battle.  The registered record has to carry the
  -- path already anchored at the mod root.
  T.eq(data.pokemon.FIXLUGIA.spriteFront,
    "mods/national_dex/assets/sets/placeholder/front.png",
    "registered species front pic is anchored at the mod root")
  T.eq(data.pokemon.FIXLUGIA.spriteBack,
    "mods/national_dex/assets/sets/placeholder/back.png",
    "registered species back pic is anchored at the mod root")

  -- the complete modern data (movesFull, movesByMethod, abilities, evYield,
  -- eggGroups, baseHappiness, growthRateName, genderRate) must NOT be on
  -- the registered record itself -- that is the entire fix for the
  -- withdrawn 0.8.0 build, which bolted it onto every one of 1351 records
  -- and pushed a single national.lua past LuaJIT's 65,536-constants-per-
  -- chunk ceiling.  It lives in the mounted extras/001.lua shard instead
  -- and only reaches a caller through src/api.lua below.
  T.eq(data.pokemon.FIXLUGIA.movesFull, nil,
    "the registered record does not carry movesFull -- extras are sharded, "
    .. "never bolted onto the record read by the battle engine")
  T.eq(data.pokemon.FIXLUGIA.abilities, nil,
    "the registered record does not carry abilities either")
end

-- alternate-form registration (326 forms alongside the 874 beyond-151
-- species, per build_national_dex.py's build_form_record): a form is an
-- ordinary pokemon record that shares its base species' dex number rather
-- than claiming a new one, so it must never grow the Pokedex list.
T.check(data.pokemon.FIXLUGIA_MEGA ~= nil, "an alternate-form record registers")
if data.pokemon.FIXLUGIA_MEGA then
  T.same(data.pokemon.FIXLUGIA_MEGA.types, { "PSYCHIC_TYPE", "DARK" },
    "form record carries its own types, distinct from its base species")
  T.eq(data.pokemon.FIXLUGIA_MEGA.baseStats.special, 180,
    "form record carries its own collapsed special stat")
  T.neq(data.pokemon.FIXLUGIA_MEGA.baseStats.special,
    data.pokemon.FIXLUGIA and data.pokemon.FIXLUGIA.baseStats.special,
    "form's stats differ from its base species' stats")
  T.eq(data.pokemon.FIXLUGIA_MEGA.dex, 1025,
    "form record shares its BASE species' dex number, not a new one")
  T.eq(data.pokemon.FIXLUGIA_MEGA.form, "MEGA",
    "form record carries the form suffix as an extra field")
  T.eq(data.pokemon.FIXLUGIA_MEGA.baseSpecies, "FIXLUGIA",
    "form record carries its base species id as an extra field")
  -- a form's abilities live in the extras shard, same as its base species'
  -- -- neither is on the raw registered record; proven via the API below
  -- ("a form's abilities differ from its base species'")
  T.eq(data.pokemon.FIXLUGIA_MEGA.abilities, nil,
    "a form's registered record does not carry abilities either")
end
-- the form shares FIXLUGIA's dex (1025, already the roster's max), so
-- registering it must not push dexSize past the true species count
T.eq(data.constants.dexSize, 1025,
  "registering a form does not increase dexSize past its base species")

-- mod.exports.splitStats: the cross-mod integration surface (main.lua).
-- Confirmed against a live loaded mod rather than assumed from source, the
-- same way every other cross-registry assertion in this suite works.
local exports = run.loader.exports.national_dex
T.check(exports ~= nil, "national_dex mod publishes exports")
if exports then
  T.eq(exports.hasSplitStats, true, "exports advertise the split-stats capability")
  local split = exports.splitStats and exports.splitStats("FIXLUGIA_MEGA")
  T.check(split ~= nil, "splitStats resolves a form id")
  if split then
    T.eq(split.spAttack, 180, "splitStats returns the form's raw Sp.Atk")
    T.eq(split.spDefense, 120, "splitStats returns the form's raw Sp.Def")
  end
  local none = exports.splitStats and exports.splitStats("NOT_A_REAL_SPECIES")
  T.check(none == nil, "splitStats answers nil for an unregistered species")
end

T.same(data.pokemon.FIXMON_A.types, { "GRASS", "FAIRY" },
  "patch retypes an existing species for modern generations")
-- a PATCHED Kanto species's extras are sharded exactly like a registered
-- one's -- neither rides on the record itself; proven via the API below
T.eq(data.pokemon.FIXMON_A.abilities, nil,
  "a patched Kanto species's registered record does not carry abilities")
T.eq(data.text.NDEX_1025, "It dwells in the deep.", "dex text registers")
T.check(data.type_chart.types.FAIRY ~= nil, "modern chart registers the FAIRY type")
if data.type_chart.types.FAIRY then
  T.eq(data.type_chart.types.FAIRY.name, "FAIRY", "type record carries its name")
  T.eq(data.type_chart.types.FAIRY.category, "physical",
    "type record carries its category")
end
T.check(data.type_chart.types.DARK ~= nil, "modern chart registers the DARK type")
local function chartRow(matchups, attacker, defender)
  for _, row in ipairs(matchups) do
    if row.attacker == attacker and row.defender == defender then return row end
  end
end
local fairyRow = chartRow(data.type_chart.matchups, "FAIRY", "DRAGON")
T.check(fairyRow ~= nil, "modern chart row FAIRY>DRAGON registers")
if fairyRow then
  T.eq(fairyRow.multiplier, 0, "FAIRY is immune to DRAGON")
end
local darkRow = chartRow(data.type_chart.matchups, "DARK", "PSYCHIC_TYPE")
T.check(darkRow ~= nil, "modern chart row DARK>PSYCHIC_TYPE registers")
if darkRow then
  T.eq(darkRow.multiplier, 20, "DARK hits PSYCHIC for 2x")
end
T.eq(data.constants.dexSize, 1025, "dexSize patches past the Gen 1 roster")
T.eq(data.constants.dexDigits, 4, "dexDigits tracks the roster width")

-- a second load with the dex OFF must leave the fixture data untouched
local offMount = {}
for key, value in pairs(mount) do offMount[key] = value end
offMount["options.lua"] = [==[return { modOptions = {
  ["national_dex"] = { type_chart = "gen1", national_dex = "off" },
} }]==]
local runOff = T.sdk.loadMod("national_dex",
  { fs = T.sdk.memfs(offMount), data = T.fixtures.fresh() })
T.check(runOff.data.pokemon.FIXLUGIA == nil,
  "dex data absent when national_dex is off")
T.same(runOff.data.pokemon.FIXMON_A.types, { "GRASS" },
  "typing untouched when the dex is off")
T.eq(runOff.data.constants.dexSize, 3, "dexSize stays seeded when the dex is off")
runOff.release()

run.release()

-- dexpage.lua's pure logic (form-list ordering, stat-row shaping) has no
-- love/engine dependency, so it loads directly with dofile rather than
-- through the mod SDK -- this is the headless coverage
-- national_dex_mod/CLAUDE.md's testability rule asks for, proven against
-- the actual shipped module rather than a re-typed copy of its logic.
local Dexpage = dofile(ROOT .. "/national_dex_mod/src/dexpage.lua")

-- buildFormList --------------------------------------------------------

local formsFixture = {
  FIXLUGIA = { id = "FIXLUGIA" },
  -- two forms on purpose: pairs() has no defined order, so a build that
  -- happened to walk the hash part in insertion order would still pass a
  -- single-form test by accident. Two forms whose alphabetical order is
  -- the OPPOSITE of insertion order catches that.
  FIXLUGIA_MEGA = { id = "FIXLUGIA_MEGA", baseSpecies = "FIXLUGIA", form = "MEGA" },
  FIXLUGIA_GMAX = { id = "FIXLUGIA_GMAX", baseSpecies = "FIXLUGIA", form = "GMAX" },
  UNRELATED = { id = "UNRELATED" },
}

local noForms = Dexpage.buildFormList(formsFixture, "UNRELATED")
T.same(noForms, { "UNRELATED" },
  "a species with no forms yields a single-entry list")

local withForms = Dexpage.buildFormList(formsFixture, "FIXLUGIA")
T.same(withForms, { "FIXLUGIA", "FIXLUGIA_GMAX", "FIXLUGIA_MEGA" },
  "a species with forms yields base-first then forms in id order")

-- rebuilding from the same table must always land on the same list --
-- LEFT/RIGHT's order is only meaningful if it cannot reshuffle between
-- one dex-page open and the next
T.same(Dexpage.buildFormList(formsFixture, "FIXLUGIA"), withForms,
  "the form list is deterministic across rebuilds")

-- statRows ---------------------------------------------------------------

local baseStats = { hp = 100, attack = 90, defense = 80, speed = 70, special = 60 }
local splitRecord = { baseStats = baseStats, spAttack = 65, spDefense = 55 }
local unsplitRecord = { baseStats = baseStats }

local gen1Rows = Dexpage.statRows(unsplitRecord, "gen1")
T.eq(#gen1Rows, 6, "gen1 mode yields 6 rows (5 base stats + TOTAL)")
T.same({ gen1Rows[1][1], gen1Rows[2][1], gen1Rows[3][1], gen1Rows[4][1],
         gen1Rows[5][1], gen1Rows[6][1] },
  { "HP", "ATK", "DEF", "SPD", "SPC", "TOTAL" },
  "gen1 rows are HP/ATK/DEF/SPD/SPC/TOTAL, in that order")
T.eq(gen1Rows[6][2], 100 + 90 + 80 + 70 + 60,
  "TOTAL matches the sum of the shown stats (gen1)")

local modernRows = Dexpage.statRows(splitRecord, "modern")
T.eq(#modernRows, 7, "modern mode yields 7 rows (6 base stats + TOTAL)")
T.same({ modernRows[1][1], modernRows[2][1], modernRows[3][1], modernRows[4][1],
         modernRows[5][1], modernRows[6][1], modernRows[7][1] },
  { "HP", "ATK", "DEF", "SP.A", "SP.D", "SPD", "TOTAL" },
  "modern rows are HP/ATK/DEF/SP.A/SP.D/SPD/TOTAL -- speed LAST so the two "
  .. "Special rows sit together, and SPD still always means speed, never "
  .. "Sp.Def.  Must stay identical in order to the party summary's split "
  .. "layout: the same mon's numbers appear on both screens.")
T.eq(modernRows[4][2], 65, "modern SP.A reads the record's own spAttack")
T.eq(modernRows[5][2], 55, "modern SP.D reads the record's own spDefense")
T.eq(modernRows[6][2], 70, "modern SPD still reads the record's own speed")
T.eq(modernRows[7][2], 100 + 90 + 80 + 70 + 65 + 55,
  "TOTAL matches the sum of the shown stats (modern)")

-- a record the split never reached (no spAttack/spDefense) must not error
-- out of a "modern" request -- it degrades to the gen1 shape instead, the
-- same fallback the base game's own SPECIAL stat represents
local degraded = Dexpage.statRows(unsplitRecord, "modern")
T.eq(#degraded, 6,
  "a record missing spAttack degrades to the gen1 rows under STATS=modern")
T.eq(degraded[5][1], "SPC",
  "the degraded rows keep the collapsed SPC label, not a broken SP.A")

-- summarystats.lua's pure logic (party summary stats box) is likewise
-- love/engine-free and loaded the same way, straight off the shipped file.
local Summarystats = dofile(ROOT .. "/national_dex_mod/src/summarystats.lua")

-- the real engine formula, required directly -- Stats.lua has no love
-- dependency outside randomDVs, which none of this calls -- so the
-- expectations below run through the SAME code production wires in, not a
-- hand-typed copy of home/move_mon.asm CalcStat
local Stats = require("src.pokemon.Stats")

local summaryDef = { baseStats = baseStats, spAttack = 65, spDefense = 55 }
local summaryDefUnsplit = { baseStats = baseStats }
local mon = {
  level = 50, dvs = { special = 9 }, statExp = { special = 10000 },
  stats = { attack = 111, defense = 102, speed = 93, special = 84 },
}

-- gen1 mode: the STATUS screen must render exactly as it always has -- the
-- vanilla four rows straight off mon.stats, and no repaint signaled, so the
-- draw patch's overpaint never runs
local gen1Summary, gen1Modern = Summarystats.statRows(mon, summaryDef, "gen1",
  Stats.calc, Dexpage.splitStats)
T.eq(gen1Modern, false, "gen1 mode never signals a repaint")
T.eq(#gen1Summary, 4, "gen1 mode yields the vanilla 4 rows")
T.same({ gen1Summary[1][1], gen1Summary[2][1], gen1Summary[3][1], gen1Summary[4][1] },
  { "ATTACK", "DEFENSE", "SPEED", "SPECIAL" },
  "gen1 rows keep the vanilla ATTACK/DEFENSE/SPEED/SPECIAL labels")

-- a record the split never reached must fall back to the vanilla 4 rows
-- even under STATS=modern -- the same degrade-safely rule dexpage.lua's
-- statRows follows, so a mon of a species this mod's data never touched
-- still gets a normal STATUS screen instead of a broken one
local unsplitSummary, unsplitModern = Summarystats.statRows(mon, summaryDefUnsplit,
  "modern", Stats.calc, Dexpage.splitStats)
T.eq(unsplitModern, false, "a record missing the split never signals a repaint")
T.eq(#unsplitSummary, 4, "an unsplit record falls back to 4 rows under modern")

-- modern mode with a split record: six rows, abbreviated labels, in order.
-- HP leads and SPEED trails, matching the dex STATS page exactly -- the two
-- screens print the same mon's stats and a reader moving between them should
-- not have to hunt for a row that moved.
--
-- There is deliberately NO TOTAL row here, unlike the dex page.  This box's
-- interior is 64px wide and the font is fixed 8px per glyph, so "TOTAL" (40px)
-- beside a level-100 total (four digits, 32px) needs 72px and would overlap
-- its own label.  The dex page has the room; this one does not.
local modernSummary, modernModern = Summarystats.statRows(mon, summaryDef, "modern",
  Stats.calc, Dexpage.splitStats)
T.eq(modernModern, true, "modern mode with a split record signals a repaint")
T.eq(#modernSummary, 6, "modern mode yields 6 rows")
T.same({ modernSummary[1][1], modernSummary[2][1], modernSummary[3][1],
         modernSummary[4][1], modernSummary[5][1], modernSummary[6][1] },
  { "HP", "ATK", "DEF", "SP.A", "SP.D", "SPD" },
  "modern rows are HP/ATK/DEF/SP.A/SP.D/SPD, in that order")
T.eq(#modernSummary[#modernSummary][1] <= 4, true,
  "every label stays within 4 glyphs, so a 3-digit value cannot collide")

-- HP/ATK/DEF/SPD come straight off the mon's already-computed stats, untouched
T.eq(modernSummary[1][2], mon.stats.hp, "HP reads the mon's computed max HP")
T.eq(modernSummary[2][2], mon.stats.attack, "ATK reads the mon's computed attack")
T.eq(modernSummary[3][2], mon.stats.defense, "DEF reads the mon's computed defense")
T.eq(modernSummary[6][2], mon.stats.speed, "SPD reads the mon's computed speed")

-- Sp.Atk/Sp.Def are the engine's own Gen 1 formula fed the record's split
-- base through the mon's EXISTING special DV/stat-exp -- checked against
-- the real Stats.calc rather than a hardcoded number, so this still holds
-- if the formula is ever refined
local function expectSpecial(base)
  local synthetic = { baseStats = { hp = baseStats.hp, attack = baseStats.attack,
    defense = baseStats.defense, speed = baseStats.speed, special = base } }
  return Stats.calc(synthetic, mon.level, mon.dvs, mon.statExp).special
end
T.eq(modernSummary[4][2], expectSpecial(summaryDef.spAttack),
  "SP.A equals the engine's own formula fed the record's spAttack as the special base")
T.eq(modernSummary[5][2], expectSpecial(summaryDef.spDefense),
  "SP.D equals the engine's own formula fed the record's spDefense as the special base")
-- the two must legitimately differ here (65 vs 55 base) -- catches a
-- copy-paste that quietly computed SP.D from spAttack too
T.neq(modernSummary[4][2], modernSummary[5][2],
  "SP.A and SP.D differ when the record's spAttack and spDefense differ")

-- this box is display only -- computing SP.A/SP.D must never write back
-- into anything the battle engine reads
T.eq(mon.stats.special, 84,
  "computing SP.A/SP.D never rewrites the mon's collapsed special stat")
T.eq(summaryDef.baseStats.special, baseStats.special,
  "computing SP.A/SP.D never rewrites the species record's collapsed special")


-- ---- form art lookup: which name a sprite set is actually asked for
--
-- A set keys form art UNDER THE BASE SPECIES (universal_sprites'
-- Registry:registerForm), so asking by a form's own compound id
-- ("CHARIZARD_MEGA_X") matches no entry and the dex falls back to this mod's
-- "?" placeholder.  Measured against the installed sets, asking correctly
-- resolves 124 of the 326 forms in gen5ani and 226 in gen5.
T.same({ Dexpage.formCandidates({ baseSpecies = "VENUSAUR", form = "MEGA" },
    "VENUSAUR_MEGA") },
  { "VENUSAUR", "MEGA", nil },
  "a form is asked for as base species + form, never by its compound id")

-- Sets built before the form ids settled squash the underscores out of their
-- keys (MEGAX, POMPOM, GALARZEN) because the build tool took them from
-- filenames that omit the hyphen, and the registry's key cleaner never
-- INSERTS an underscore -- so the two spellings can never meet and the miss
-- is silent.  5 forms in gen5ani and 14 in gen5 are affected, including both
-- Charizard and both Mewtwo megas, which are the first things anyone checks.
T.same({ Dexpage.formCandidates({ baseSpecies = "CHARIZARD", form = "MEGA_X" },
    "CHARIZARD_MEGA_X") },
  { "CHARIZARD", "MEGA_X", "MEGAX" },
  "an underscored form offers the squashed spelling as a second attempt")
T.eq(select(3, Dexpage.formCandidates({ baseSpecies = "PIKACHU", form = "GMAX" },
  "PIKACHU_GMAX")), nil,
  "a form with no underscore has no alternate spelling to try")

-- a plain species carries neither: it is asked for exactly as it is
T.same({ Dexpage.formCandidates({ id = "PIKACHU" }, "PIKACHU") },
  { "PIKACHU", nil, nil },
  "a species with no form fields is asked for under its own id")


-- ---- cross-mod read API (src/api.lua)
--
-- Runs in process: mod.exports is a plain table another mod reaches through
-- mod:find("national_dex").  Nothing is hosted and nothing listens, so the
-- only precondition is that this mod loaded -- which is what this asserts,
-- against a really-loaded mod rather than by reading the source.
-- Pinned to the exact number rather than checked with >=, which is what a
-- CONSUMER should do: this is the side that owns the number, and a bump has
-- to be a deliberate edit here rather than something a change elsewhere can
-- make quietly.  2 added moveById/listMoves, 3 evolutionsOf/listEvolutions
-- (src/api.lua).
T.eq(exports and exports.apiVersion, 3, "the read API publishes its version")
if exports and exports.statsByDex then
  local lugia = exports.statsByDex(1025)
  T.check(lugia ~= nil, "statsByDex resolves a national dex number")
  if lugia then
    T.eq(lugia.id, "FIXLUGIA", "statsByDex returns the species that owns the number")
    T.eq(lugia.stats.attack, 90, "the reply carries the collapsed base stats")
    T.eq(lugia.stats.special, 154,
      "the reply reports the ROM's collapsed special unchanged -- it is what "
      .. "the engine's own damage maths reads")
    T.eq(lugia.hasSplit, false, "a record without the split says so explicitly")
    T.check(lugia.forms ~= nil and #lugia.forms == 1,
      "a species' alternate forms come back nested under it")
    if lugia.forms and lugia.forms[1] then
      T.eq(lugia.forms[1].id, "FIXLUGIA_MEGA", "the nested form is identified")
      T.eq(lugia.forms[1].form, "MEGA", "the nested form carries its form id")
      T.eq(lugia.forms[1].stats.spAttack, 180,
        "a split record reports its real Sp.Atk")
      T.eq(lugia.forms[1].hasSplit, true, "a split record says so")
      T.eq(lugia.forms[1].total, 106 + 150 + 90 + 130 + 180 + 120,
        "total counts the six modern stats when the split is known")
    end
  end
  -- a consumer must never be handed a live reference into the registry: a
  -- stray write there would reach the battle engine's own species data
  local first = exports.statsByDex(1025)
  if first then
    first.stats.attack = -1
    local second = exports.statsByDex(1025)
    T.eq(second and second.stats.attack, 90,
      "the reply is a copy -- mutating it cannot reach the species record")
  end
  T.eq(exports.statsByDex(99999), nil, "an unknown dex number answers nil")
  T.eq(exports.statsBySpecies("NOT_A_SPECIES"), nil,
    "an unknown species id answers nil")

  local list = exports.listSpecies()
  T.check(type(list) == "table" and #list > 0, "listSpecies returns a directory")
  if type(list) == "table" and #list > 1 then
    T.check(list[1].dex < list[#list].dex, "the directory is ordered by dex number")
  end
  local named
  for _, row in ipairs(list or {}) do
    if row.id == "FIXLUGIA" then named = row end
  end
  T.check(named ~= nil, "the directory includes a registered species")
  if named then
    T.eq(named.name, "FIXLUGIA", "each directory row carries the display name")
    T.eq(named.forms, 1, "each directory row counts the species' alternate forms")
  end
  T.eq(#exports.formsOf(1025), 1, "formsOf answers by dex number")
  T.eq(#exports.formsOf("FIXLUGIA"), 1, "formsOf answers by species id")
  T.same(exports.formsOf("NOT_A_SPECIES"), {},
    "formsOf answers an empty list for an unknown species")
end


-- The reply is the WHOLE record, not a curated subset: a mod implementing
-- mega evolutions needs the learnset and evolutions, not just the stats.
if exports and exports.statsBySpecies then
  local full = exports.statsBySpecies("FIXLUGIA")
  T.check(full and full.learnset ~= nil, "the reply carries the learnset")
  if full and full.learnset then
    T.eq(#full.learnset, 2, "the learnset comes through in full")
    T.eq(full.learnset[1].move, "FIX_TACKLE", "learnset entries keep their move")
    T.eq(full.learnset[2].level, 9, "learnset entries keep their level")
  end
  T.check(full and full.evolutions ~= nil, "the reply carries evolutions")
  T.eq(full and full.growthRate, "MEDIUM_SLOW", "the reply carries the growth rate")
  T.eq(full and full.catchRate, 3, "the reply carries the catch rate")
  T.eq(full and full.dexEntry and full.dexEntry.text, "NDEX_1025",
    "the reply carries the dex entry, including its description text id")
  -- nested tables must be copies too, or a consumer still holds a live
  -- reference into the species data the battle engine reads
  if full and full.learnset then full.learnset[1].move = "TAMPERED" end
  local again = exports.statsBySpecies("FIXLUGIA")
  T.eq(again and again.learnset and again.learnset[1].move, "FIX_TACKLE",
    "nested tables are copied too -- a deep write cannot reach the record")

  -- api.lua's deepCopy is generic (it walks pairs(value), not a fixed field
  -- list), so the new unfiltered fields have to reach a consumer with no
  -- change to api.lua at all -- proven here rather than assumed, the same
  -- way every other field on this API is proven against a live loaded mod.
  T.check(full and full.movesFull ~= nil and #full.movesFull == 4,
    "the reply carries movesFull, the complete unfiltered learnset")
  T.check(full and full.movesByMethod ~= nil and full.movesByMethod.tutor ~= nil,
    "the reply carries movesByMethod")
  T.check(full and full.abilities ~= nil and #full.abilities == 2,
    "the reply carries abilities")
  T.eq(full and full.evYield and full.evYield.hp, 3, "the reply carries evYield")
  T.same(full and full.eggGroups, { "No Eggs" }, "the reply carries eggGroups")
  T.eq(full and full.growthRateName, "slow", "the reply carries growthRateName")
  T.eq(full and full.genderRate, -1, "the reply carries genderRate")

  -- and the copy has to be DEEP for these new fields too -- a shallow copy
  -- would still leak a live reference into movesFull's rows
  if full and full.movesFull then full.movesFull[1].move = "TAMPERED" end
  if full and full.abilities then full.abilities[1].name = "TAMPERED" end
  local againFull = exports.statsBySpecies("FIXLUGIA")
  T.eq(againFull and againFull.movesFull and againFull.movesFull[1].move, "FIXHATCH",
    "movesFull is copied too -- a deep write cannot reach the record")
  T.eq(againFull and againFull.abilities and againFull.abilities[1].name, "Pressure",
    "abilities is copied too -- a deep write cannot reach the record")

  -- A form is addressable directly by id, which is how another mod would
  -- implement mega evolution; it is never its own dex row, because Mega
  -- Charizard X and Y are both national dex No. 6 in the real games.
  local mega = exports.statsBySpecies("FIXLUGIA_MEGA")
  T.check(mega ~= nil, "a form is addressable as a first-class record by id")
  T.eq(mega and mega.baseDex, 1025,
    "a form reports its BASE species' dex number for display, never its "
    .. "own synthetic registration key")

  -- the CHARIZARD_MEGA_Y-vs-CHARIZARD case, proven through the extras shard
  -- mechanism this time (both FIXLUGIA and FIXLUGIA_MEGA's abilities live in
  -- the SAME mounted shard, extras/001.lua, under different keys) rather
  -- than the raw record, which no longer carries abilities at all
  T.check(mega and mega.abilities ~= nil and mega.abilities[1].name == "Multiscale",
    "a form's shard-sourced abilities are its own")
  T.neq(mega and mega.abilities and mega.abilities[1].name,
    full and full.abilities and full.abilities[1].name,
    "a form's abilities differ from its base species' abilities")

  -- a species absent from the extras index entirely (FIXMON_B, seeded by
  -- T.fixtures.fresh(), untouched by this mod) must still answer with its
  -- stats -- a missing/absent extras entry degrades to "no extras", never
  -- an error, and never withholds the reply the caller actually asked for
  local noExtras = exports.statsBySpecies("FIXMON_B")
  T.check(noExtras ~= nil, "a species outside the extras index still resolves")
  if noExtras then
    T.check(noExtras.stats ~= nil, "it still carries its stats block")
    T.eq(noExtras.movesFull, nil, "it carries no movesFull -- there is no shard entry for it")
    T.eq(noExtras.abilities, nil, "it carries no abilities -- there is no shard entry for it")
  end
end


-- ---- the PRODUCTION data file must actually compile
--
-- Everything above this line runs against a small inline fixture, which is
-- exactly how a 10.8 MB generated national.lua once reached the install tray
-- with 140 green checks behind it: a single Lua chunk may hold at most 65,536
-- constants, and that build tripped the limit at line 36050, so the mod would
-- have loaded with NO species at all.  A fixture can never catch that.
--
-- loadfile COMPILES without running, so this costs a parse and nothing else.
-- If it ever fails, the payload has to be split across several chunks -- the
-- ceiling is the constant count, not the byte size.
local prodPath = ROOT .. "/national_dex_mod/data/species/generated/national.lua"
local prodChunk, prodErr = loadfile(prodPath)
T.check(prodChunk ~= nil,
  "the production species file compiles (" .. tostring(prodErr) .. ")")

-- ---- the PRODUCTION extras shards (and their index) must actually compile
--
-- The whole reason movesFull/movesByMethod/abilities/evYield/eggGroups/
-- baseHappiness/growthRateName/genderRate moved out of national.lua and
-- into data/species/generated/extras/: bolted onto every one of 1351
-- records, they were exactly what pushed the withdrawn build past the
-- 65,536-constant ceiling. Splitting the data only actually fixes anything
-- if every shard this build produces is small enough to compile on its
-- own -- asserted here the same way the production national.lua guard
-- above does, rather than trusted from the shard-size constant alone.
local extrasDir = ROOT .. "/national_dex_mod/data/species/generated/extras"
local indexPath = extrasDir .. "/index.lua"
local indexChunk, indexErr = loadfile(indexPath)
T.check(indexChunk ~= nil,
  "the production extras index compiles (" .. tostring(indexErr) .. ")")

if indexChunk then
  local ok, index = pcall(indexChunk)
  T.check(ok and type(index) == "table",
    "the production extras index runs and returns a table")
  if ok and type(index) == "table" then
    -- every shard number the index actually points at, deduplicated --
    -- write_extras() never emits an empty shard, so this set is exactly
    -- the set of files on disk under extras/ (besides index.lua itself)
    local shardNumbers, count = {}, 0
    for _, shardNumber in pairs(index) do
      if not shardNumbers[shardNumber] then
        shardNumbers[shardNumber] = true
        count = count + 1
      end
    end
    T.check(count > 0, "the production extras index references at least one shard")

    local compiled, failed = 0, {}
    for shardNumber in pairs(shardNumbers) do
      local shardPath = extrasDir .. ("/%03d.lua"):format(shardNumber)
      local shardChunk, shardErr = loadfile(shardPath)
      if shardChunk then
        compiled = compiled + 1
      else
        failed[#failed + 1] = shardPath .. ": " .. tostring(shardErr)
      end
    end
    T.check(#failed == 0,
      ("every production extras shard compiles (%d/%d; failures: %s)")
        :format(compiled, count, table.concat(failed, " | ")))
  end
end

T.finish("national_dex")

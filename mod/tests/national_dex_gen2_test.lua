-- Standalone: luajit ../dev/national_dex_mod/tests/national_dex_gen2_test.lua
-- run with cwd at the root of a gen1recomp checkout (game/).
--
-- manifest.games claims gen1 AND gen2, and the loader gates on that claim: a
-- mod that does not name the running game is skipped, which is deliberately
-- not an error.  So this asserts the mod's STATE -- an error count of zero
-- passes just as happily for a mod that never ran a line.
--
-- Its own file rather than a block in national_dex_test.lua because the
-- engine's builtin registries are registered once per process; a second
-- loader.load in the same run raises on `statuses already registered` before
-- the mod is reached.
--
-- The mod itself is not physically present under the checkout's mods/, so
-- "mods/national_dex" is rewritten to this file's own location the same way
-- national_dex_defaults_test.lua and national_dex_effectmodeled_test.lua do
-- -- MOD, derived from arg[0], self-locates regardless of cwd tricks.  The
-- earlier version of this file skipped that aliasing and asked the bare fs
-- for "mods/national_dex" directly; against a checkout with no such
-- directory that resolves to nothing at all, run.mod comes back nil, and
-- the assertions below never got past their first line -- a guard that
-- looked like it was checking the Gen 2 boot while actually checking an
-- empty loader.mods table. Silent integrity checks have cost this project
-- days before; this was another one.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local FsIo = require("tests.fs_io")
local MOD = arg[0]:gsub("[/\\]tests[/\\][^/\\]+$", "")

-- The real dataset, not the SDK's fixture: the fixture carries a handful of
-- moves, so 1025 species' learnsets resolve to thousands of unresolved
-- references that say nothing about Gen 2.  Safe in this file because it is
-- the only load in the process.
local Data = require("src.core.Data")
Data:load()

-- A ROM-owned species is exactly what src/gen2shape.lua's M.generation now
-- probes as its second signal (see that file's own header for why the first
-- one, mod.content.constants:get("generation"), has a confirmed gap).  Red's
-- own extracted Bulbasaur carries the Gen 1 shape (baseStats.special); this
-- stands in for what Data:load() actually returns on a Gold boot (baseStats
-- split into specialAttack/specialDefense), without checking any ROM-derived
-- table into the repo -- it is a synthetic shape, not extracted content.
Data.pokemon.BULBASAUR.baseStats.specialAttack =
  Data.pokemon.BULBASAUR.baseStats.special
Data.pokemon.BULBASAUR.baseStats.specialDefense =
  Data.pokemon.BULBASAUR.baseStats.special

local ENCODED_OPTIONS = [[return {
  mods = { national_dex = true },
  modOptions = { national_dex = { national_dex = "on", type_chart = "modern" } },
}]]

local function optionsFs()
  local inner = FsIo.new(".")
  local function map(path)
    if path == nil then return path end
    local prefix = "mods/national_dex"
    if path == prefix then return MOD end
    if path:sub(1, #prefix + 1) == prefix .. "/" then
      return MOD .. path:sub(#prefix + 1)
    end
    return path
  end
  local fs = { root = inner.root }
  function fs.read(path)
    if path == "options.lua" then return ENCODED_OPTIONS end
    return inner.read(map(path))
  end
  function fs.load(path)
    if path == "options.lua" then return load(ENCODED_OPTIONS, "@options.lua") end
    return inner.load(map(path))
  end
  function fs.getInfo(path)
    if path == "options.lua" then return { type = "file" } end
    if path == "mods" then return { type = "directory" } end
    return inner.getInfo(map(path))
  end
  function fs.getDirectoryItems(path)
    if path == "mods" then return { "national_dex" } end
    return inner.getDirectoryItems(map(path))
  end
  function fs.write() return true end
  return fs
end

-- generation = 2 is the loader-level seam (the same one Gold's real boot and
-- tools/save-editor/App.lua both set correctly -- App.lua calls
-- GameVersion.set(opts.version) before building its loader, and
-- ModLoader.new() reads GameVersion.generation() from that).  What this
-- deliberately does NOT do is seed Data.gen2Constants.  A real Gold boot
-- (src/core/Game2.lua:925) always sets it before mods:load runs; the save
-- editor's own bootstrap (tools/save-editor/Gen.lua:bindGoldData) binds
-- gen2Maps/gen2Tilesets/gen2Palettes and a handful of others but never
-- gen2Constants, so mod.content.constants:get("generation") comes back nil
-- there even though the loader itself, and every registry it built, already
-- knows this is Gen 2.  That gap, reproduced exactly, is what makes this
-- suite mean something.
local run = T.sdk.loadMods({ "national_dex" }, { data = Data, fs = optionsFs(),
                                                  generation = 2 })

T.eq(run.mods and run.mods.national_dex and run.mods.national_dex.state, "loaded",
  "the gen2 claim gets it past the gate: "
    .. tostring(run.mods and run.mods.national_dex
      and run.mods.national_dex.skipReason))

-- Pre-existing and engine-side, unrelated to registration: Schemas.GEN1
-- gates six registries and growth_rates/evolution_methods are not among
-- them, so every species' own growthRate and evolutions[].method -- ROM
-- fields this mod never writes, patched or not -- read as an unresolved
-- reference against the merge target's own (empty here) growth_rates and
-- evolution_methods registries.  Not this mod's bug and not fixed here;
-- pinned so a future change to either count is a deliberate one.
local unresolved = 0
for _, message in ipairs(run.errors) do
  if message:find("unresolved reference", 1, true) then
    unresolved = unresolved + 1
  end
end
T.eq(unresolved, #run.errors,
  "every hard error is the documented pre-existing unresolved-reference gate, "
    .. "none of them a registration failure")

-- The actual regression this file exists to catch: species landing in
-- data.pokemon at all under a Gen 2 boot, the exact thing the save editor's
-- species picker and Catalog.build(data) both read.  Before src/gen2shape.lua
-- gained its second generation signal, gen2shape.generation(mod) fell back to
-- 1 here (mod.content.constants:get("generation") reads nil, the same as it
-- does through tools/save-editor's bootstrap), nationaldex.lua registered
-- every beyond-251 species in Gen 1 shape, and the pokemon registry -- built
-- Gen 2-shaped because the LOADER's own generation was correctly 2 the whole
-- time -- rejected all ~1140 of them on the missing specialAttack field.
-- Every rejection was pcall-guarded, so the mod still loaded, still reported
-- zero hard errors, and the tally line saying so went out through
-- mod.log:warn -- which reaches a print() the packaged launcher discards.
--
-- TREECKO (dex 252), not a species in Gold's own #1-251 cart range: a
-- Johto-range species like Chikorita (dex 152) is romOwned() on a REAL Gold
-- boot -- the cart already has it -- and this suite's merge target is Red's
-- fixture data, which has no such entry to patch onto, so it would prove
-- only that a patch onto nothing still leaves a row behind, not that the
-- full register() + gen2shape.record() path ran.  TREECKO is never
-- romOwned on either cart, so it always takes that path.
T.check(Data.pokemon.TREECKO ~= nil,
  "a beyond-251 species reaches data.pokemon under a Gen 2 boot, even when "
    .. "the constants registry cannot answer M.generation's primary read")
if Data.pokemon.TREECKO then
  T.check(Data.pokemon.TREECKO.levelMoves ~= nil,
    "and it carries the Gen 2 shape (levelMoves), not the untranslated Gen 1 "
      .. "one (learnset) the schema mismatch would have rejected on sight")
  T.check(Data.pokemon.TREECKO.baseStats
    and Data.pokemon.TREECKO.baseStats.specialAttack ~= nil,
    "and the split stat, not the collapsed Gen 1 `special`")
end

-- The read API is published regardless of options or generation, so a
-- consumer mod on Gold still gets an answer.
local exports = run.loader.exports.national_dex
T.check(type(exports) == "table", "exports are published on a Gen 2 boot")
T.check((exports.apiVersion or 0) >= 1, "including the apiVersion consumers gate on")

run.release()
T.finish("national_dex_gen2")

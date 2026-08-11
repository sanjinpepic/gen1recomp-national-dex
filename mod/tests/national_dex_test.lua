-- Standalone: luajit mods/national_dex/tests/national_dex_test.lua
--
-- Run from the root of a gen1recomp checkout with this mod installed (or
-- symlinked) at mods/national_dex.
--
-- What this suite is for is the dex the mod REGISTERS, not the fact that it
-- loaded.  NATIONAL DEX defaults to OFF, and with it off the mod loads
-- cleanly and registers nothing at all -- so a suite that only checked
-- #run.errors would pass just as green against an empty registry.  The
-- injected options.lua below is what stops every assertion here from being
-- vacuous.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local FsIo = require("tests.fs_io")
local Data = require("src.core.Data")
Data:load()

local ID = "national_dex"
local PATH = "mods/" .. ID

-- `mods` is non-empty on purpose: the loader reads an empty table as a first
-- run and disables every mod it discovers, which would skip this one.
local OPTIONS = [[return {
  mods = { national_dex = true },
  modOptions = { national_dex = { national_dex = "on", type_chart = "modern" } },
}]]

-- The real checkout, with options.lua answered from memory instead of disk.
-- `mods` lists only this mod so a developer's other installs cannot colour
-- the counts below, and writes are dropped because a suite must never edit
-- the checkout it is reading -- the loader persists enable state on load.
local function optionsFs()
  local inner = FsIo.new(".")
  local fs = { root = inner.root }

  function fs.read(path)
    if path == "options.lua" then return OPTIONS end
    return inner.read(path)
  end

  function fs.load(path)
    if path == "options.lua" then return load(OPTIONS, "@options.lua") end
    return inner.load(path)
  end

  function fs.getInfo(path)
    if path == "options.lua" then return { type = "file" } end
    return inner.getInfo(path)
  end

  function fs.getDirectoryItems(path)
    if path == "mods" then return { ID } end
    return inner.getDirectoryItems(path)
  end

  function fs.write() return true end

  return fs
end

local run = T.sdk.loadMod(PATH, { data = Data, fs = optionsFs() })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local exports = run.loader.exports[ID]
T.check(type(exports) == "table", "the mod published its exports")
T.check((exports.apiVersion or 0) >= 1, "apiVersion is the integer consumers gate on")
for _, name in ipairs({ "statsByDex", "statsBySpecies", "listSpecies",
                        "formsOf", "splitStats" }) do
  T.check(type(exports[name]) == "function", name .. " is exported")
end

-- ------- the roster

local roster = exports.listSpecies()
T.eq(#roster, 1025, "the whole national dex is registered")
T.eq(roster[1].dex, 1, "the directory starts at No. 001")
T.eq(roster[#roster].dex, 1025, "and runs to No. 1025 with no gaps")

-- ------- a form is never a dex row of its own

local charizard = exports.statsByDex(6)
T.check(charizard ~= nil, "No. 006 resolves")
T.eq(charizard.id, "CHARIZARD", "No. 006 is Charizard, not one of its megas")

local forms = exports.formsOf(6)
T.check(#forms >= 2, "Charizard reports its megas as forms")
for _, form in ipairs(forms) do
  T.eq(form.baseDex, 6,
    tostring(form.id) .. " displays as No. 006, not its registration key")
end

local megaY = exports.statsBySpecies("CHARIZARD_MEGA_Y")
T.check(megaY ~= nil, "a form can be asked for directly, by id")
T.eq(megaY.baseDex, 6, "and still reports the number a player should see")

local listed = {}
for _, entry in ipairs(roster) do listed[entry.id] = true end
T.check(not listed["CHARIZARD_MEGA_Y"], "but forms stay out of the dex listing")

-- ------- the split, carried alongside the stat the engine actually reads

T.check(exports.hasSplitStats == true, "the split is advertised to consumers")
local umbreon = exports.statsBySpecies("UMBREON")
T.check(umbreon ~= nil, "a beyond-151 species resolves")
T.check(umbreon.hasSplit, "and carries the Sp.Atk/Sp.Def split")
T.check(type(umbreon.stats.special) == "number",
  "the ROM's collapsed Special survives, because damage maths reads it")
T.eq(umbreon.total,
  umbreon.stats.hp + umbreon.stats.attack + umbreon.stats.defense
    + umbreon.stats.speed + umbreon.stats.spAttack + umbreon.stats.spDefense,
  "the total counts the six modern stats, never a mix of the two shapes")

-- ------- the modern chart, without which the typing above says nothing

local chart = run.data.type_chart
T.check(type(chart) == "table" and type(chart.types) == "table",
  "the chart registry merged")
T.check(chart.types.DARK ~= nil, "DARK exists, which a Gen 1 chart cannot express")
T.check(chart.types.STEEL ~= nil and chart.types.FAIRY ~= nil,
  "and so do STEEL and FAIRY")

-- Rows register under "ATTACKER>DEFENDER" but merge into a list of
-- { attacker, defender, multiplier }, so the lookup has to be rebuilt here.
local matchup = {}
for _, row in ipairs(chart.matchups) do
  matchup[row.attacker .. ">" .. row.defender] = row.multiplier
end
T.eq(#chart.matchups, 324, "all 324 modern matchups reached the merged chart")

-- PSYCHIC_TYPE, not PSYCHIC: the move owns the shorter id.
T.eq(matchup["DARK>PSYCHIC_TYPE"], 20,
  "DARK is super effective on PSYCHIC, in the chart's x10 encoding")
T.eq(matchup["FAIRY>DRAGON"], 20, "and FAIRY on DRAGON")
T.eq(matchup["STEEL>FAIRY"], 20, "and STEEL on FAIRY")

-- The three matchups Gen 1 and the modern chart genuinely disagree on, and
-- the whole reason picking an era has to mean something.  The cart registers
-- its own chart before any mod runs and :register throws on an id that
-- already exists, so these three used to be counted as skips and silently
-- keep the ROM's answer -- Ghost stayed 0x on Psychic under a chart that says
-- 2x.  :override is what makes the era win.
T.eq(matchup["GHOST>PSYCHIC_TYPE"], 20,
  "GHOST on PSYCHIC is 2x, not Gen 1's immunity bug")
T.eq(matchup["POISON>BUG"], 10, "POISON on BUG is neutral, not Gen 1's 2x")
T.eq(matchup["BUG>POISON"], 5, "BUG on POISON is resisted, not Gen 1's 2x")

local isDark = false
for _, id in ipairs(umbreon.types or {}) do
  if id == "DARK" then isDark = true end
end
T.check(isDark, "Umbreon is typed DARK, which only the modern chart can say")

-- ------- every reply is a copy the caller may write to

local first = exports.statsByDex(6)
first.name = "MUTATED"
first.stats.attack = 1
local second = exports.statsByDex(6)
T.check(second.name ~= "MUTATED", "a mutated reply cannot reach the next caller")
T.check(second.stats.attack ~= 1, "nor can a mutated nested table")

-- ------- an absent thing is an answer, not a crash

T.check(exports.statsByDex(9999) == nil, "an unknown dex number answers nil")
T.check(exports.statsBySpecies("NOT_A_SPECIES") == nil, "so does an unknown id")
T.check(exports.statsBySpecies(nil) == nil, "and so does a non-string")
T.eq(#exports.formsOf("NOT_A_SPECIES"), 0, "an unknown id lists no forms")
T.check(exports.splitStats("NOT_A_SPECIES") == nil,
  "splitStats answers nil rather than raising for a species it never saw")

run.release()
T.finish("national_dex")

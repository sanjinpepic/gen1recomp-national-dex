-- The guard national_dex_test.lua's own header explains why it does NOT
-- provide: "NATIONAL DEX defaults to OFF, and with it off the mod loads
-- cleanly and registers nothing at all -- so a suite that only checked
-- #run.errors would pass just as green against an empty registry." That
-- reasoning is what let this ship: with the dex registration skipped, the
-- registry is not EMPTY -- src/moves.lua registers the full modern move
-- roster UNCONDITIONALLY, on purpose (its own header: turning MOVES back off
-- must never delete an already-learned move off a save, so the ids have to
-- always be there) -- and until this suite existed, nothing ever booted that
-- combination against the real engine to see what "always be there" actually
-- produced. Over a hundred of those moves carry a `type` of DARK, STEEL or
-- FAIRY, and the only thing that ever taught the engine those three type ids
-- was the NATIONAL DEX-gated block those same moves do not wait for.
-- Schemas.crossValidate turned every one into a hard "unresolved reference
-- to type_chart" load error, on every single default-settings boot, listed
-- on every mod's own error page in the manager -- not merely this one's.
--
-- This is this mod's own equivalent of battle_forms_reachability_test.lua:
-- it boots the REAL entry point against the REAL, ROM-extracted engine data,
-- with NOTHING configured -- the one install this project ships to a player
-- who has never opened the settings screen -- and demands zero errors,
-- rather than trusting that "registers nothing" also means "asserts
-- nothing".
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local FsIo = require("tests.fs_io")
local MOD = arg[0]:gsub("[/\\]tests[/\\][^/\\]+$", "")

local Data = require("src.core.Data")
Data:load()

-- No modOptions at all -- not even an empty table -- matching a save that
-- has never written one, the same precondition national_dex_test.lua's own
-- OPTIONS constant calls out for `mods`.
local ENCODED_OPTIONS = "return { mods = { national_dex = true } }"

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

local run = T.sdk.loadMods({ "national_dex" }, { data = Data, fs = optionsFs() })
T.eq(#run.errors, 0,
  "untouched defaults (NATIONAL DEX off, TYPE CHART gen1, MOVES gen-native) "
    .. "load with zero errors (" .. table.concat(run.errors, " | ") .. ")")

-- Confirms the block above is not vacuous: NATIONAL DEX really is off, so
-- the beyond-151 species really are absent -- the exact "registers nothing"
-- state national_dex_test.lua's header describes, proven rather than
-- assumed.
T.check(Data.pokemon.MEW ~= nil, "precondition: Mew (dex 151) is always present")
T.check(Data.pokemon.CHIKORITA == nil,
  "untouched defaults: a beyond-151 species is NOT registered")

-- The move roster IS present regardless -- src/moves.lua's own unconditional
-- contract -- which is exactly why it needed a type to point at even though
-- nothing else about National Dex ran.
T.check(Data.moves.MOONBLAST ~= nil,
  "untouched defaults: the modern move roster registers anyway (MOONBLAST)")
T.check(Data.type_chart and Data.type_chart.types and Data.type_chart.types.FAIRY ~= nil,
  "untouched defaults: and so does the FAIRY type id its own `type` field "
    .. "names, which is the fix this suite pins")
T.check(Data.type_chart and Data.type_chart.types and Data.type_chart.types.STEEL ~= nil,
  "untouched defaults: STEEL too")
T.check(Data.type_chart and Data.type_chart.types and Data.type_chart.types.DARK ~= nil,
  "untouched defaults: and DARK")

-- Only the three bare type ids, never a matchup row for one of them --
-- picking Gen 1 (the default) has to mean Gen 1 still decides every
-- multiplier a player's battle actually rolls, not modern's.
local sawMatchup = false
if Data.type_chart and Data.type_chart.matchups then
  for _, row in ipairs(Data.type_chart.matchups) do
    if row.attacker == "STEEL" or row.defender == "STEEL"
      or row.attacker == "DARK" or row.defender == "DARK"
      or row.attacker == "FAIRY" or row.defender == "FAIRY" then
      sawMatchup = true
    end
  end
end
T.check(not sawMatchup,
  "untouched defaults: no DARK/STEEL/FAIRY matchup row exists -- only the "
    .. "bare type ids the move roster needs to resolve, never the full "
    .. "modern chart a player did not ask for")

-- src/machinemoves.lua's byteless-TM pipeline is gated on the SAME MOVES=ALL
-- flag as src/moves.lua's own learnset widening -- untouched defaults means
-- MOVES=GEN-NATIVE, so this registers nothing at all, not even a dangling
-- item nobody can use yet. GRASSYGLIDE (one of tools/build_moves.py's own
-- six-move roster) stands in for the whole payload.
T.check(Data.items.TM172 == nil,
  "untouched defaults: the machine-TM pipeline registers no item at all")
T.check(Data.pokemon.BULBASAUR == nil or Data.pokemon.BULBASAUR.tmhm == nil
  or (function()
    for _, id in ipairs(Data.pokemon.BULBASAUR.tmhm) do
      if id == "GRASSYGLIDE" then return false end
    end
    return true
  end)(),
  "untouched defaults: and BULBASAUR's tmhm list never gains GRASSYGLIDE")

run.release()
T.finish("national_dex_defaults")

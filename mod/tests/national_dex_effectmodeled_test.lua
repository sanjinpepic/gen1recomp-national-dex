-- Pins the policy src/api.lua states in words (its own header: "A record
-- with EffectModeled false is registered so the move exists by name and
-- stats; its effect is plain damage, not what the move does, and this mod
-- refuses to put it in any learnset. Treat a false there as 'this engine
-- cannot execute this move'.") and src/moves.lua enforces in code (the
-- `allowed` filter mergeRows reads) -- against the REAL merged dataset a
-- fresh boot produces, not a synthetic fixture that could stay green while
-- the two drift apart. This is the exact shape of promise that quietly held
-- the eleven Z-Crystals hostage in a different mod (battle_forms) before
-- something checked it for real.
--
-- Two directions, checked separately, because they fail independently:
--
--   1. effectModeled = FALSE must never reach a learnset or a tmhm list --
--      that placeholder is plain damage wearing a real move's name, and a
--      player who saw it on their own Pokemon would have no way to know.
--
--   2. effectModeled = TRUE ought to be REACHABLE -- in a learnset (checked
--      with MOVES=ALL, the one setting that actually widens one) or a tmhm
--      entry -- or the "true" is a promise nothing in this mod keeps. 0.26.1
--      found sixteen that were not. src/machinemoves.lua (0.27.0) closed six
--      of them -- GRASSYGLIDE, LASHOUT, METEORBEAM, MISTYEXPLOSION,
--      POLTERGEIST, SCORCHINGSANDS -- the ones PokeAPI records a real
--      "machine" (TM) route for, taught the same way
--      dev/battle_forms_mod/src/terablasttm.lua proved the mechanism with
--      TM171/Tera Blast. KNOWN_UNREACHABLE below now names the ten still
--      open, read off this file rather than re-derived, so an ELEVENTH
--      appearing without anyone adding it here fails loudly instead of
--      joining the pile unnoticed. None of the ten is currently taught by a
--      dependent mod either (battle_forms's own data was checked). Two
--      groups, for two different reasons:
--
--      Six are TUTOR-only in PokeAPI's own data (BADDYBAD, FREEZYFROST,
--      GLITZYGLOW and SPARKLYSWIRL on eevee-starter; FLOATYFALL and
--      SPLISHYSPLASH on pikachu-starter -- the Let's Go partner Pokemon's
--      own signature moves, both already registered as national_dex forms
--      with otherwise-empty learnsets). Nothing under game/src implements a
--      move-tutor NPC, menu or mechanism of any kind -- confirmed by reading
--      the engine, not assumed -- so there is no route to build for these at
--      all, byteless or otherwise. Baking them into the form's own level-1
--      learnset was considered and rejected: PokeAPI calls this method
--      "tutor", never "level-up", and forcing a route the source data itself
--      does not claim is the exact invention
--      dev/battle_forms_mod/src/terablasttm.lua's own header already refused
--      for Tera Blast.
--
--      Four are LEVEL-UP moves this mod's own pipeline still misses, for a
--      different reason (HEALORDER on Vespiquen; HEARTSTAMP on Jynx,
--      Smoochum, Luvdisc, Woobat and Swoobat, plus an EGG route on Miltank;
--      NEEDLEARM on Cacnea, Cacturne, Maractus, Quilladin and Chesnaught;
--      STEAMROLLER on Golem, Golem-Alola, Venipede, Whirlipede and
--      Scolipede). Every one of these species really did learn the move by
--      level-up in a real mainline game -- just not in the single most
--      modern version group tools/fetch_national_dex.py's own
--      choose_version_group prefers per species, which is this mod's
--      documented, deliberate policy (one canonical version group's
--      level-up rows per species) rather than a bug in the machine-route
--      pipeline this file otherwise pins. Widening that policy to fall back
--      across older version groups would fix these four, but it is a change
--      to how EVERY species' learnset is chosen, not a new acquisition
--      route, and is reported here rather than built as a side effect of
--      this pass. (Gen 2's real breeding mechanism, def.eggMoves in
--      game/src/core/gen2/Breeding.lua, DOES let a species inherit an egg
--      move from a compatible parent -- contrary to what a purely tutor/egg
--      framing might assume, egg is NOT unimplemented on this engine -- but
--      it needs two compatible parents and a Day Care visit to reach one
--      move on one species, and HEARTSTAMP's only egg carrier, Miltank,
--      gains nothing from it that the level-up fallback above would not
--      already cover, so it was not built for a single redundant case.)
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local FsIo = require("tests.fs_io")
local MOD = arg[0]:gsub("[/\\]tests[/\\][^/\\]+$", "")

local Data = require("src.core.Data")
Data:load()

-- MOVES=ALL is the one setting that actually widens a learnset with modern
-- rows -- GEN-NATIVE (the default) leaves them almost untouched, and a
-- suite that checked reachability only under the default would be checking
-- the wrong thing, exactly like national_dex_test.lua's own header explains
-- for NATIONAL DEX. TYPE CHART=modern so every DARK/STEEL/FAIRY move in the
-- widened set has somewhere to point.
local ENCODED_OPTIONS = [[return {
  mods = { national_dex = true },
  modOptions = { national_dex = { national_dex = "on", type_chart = "modern",
                                   moves = "all" } },
}]]

-- No junction or copy of national_dex_mod under game/mods/ can be assumed to
-- exist, so "mods/national_dex" is rewritten to this checkout's real path --
-- the same aliasing tests/modkit/sdk.lua's own Sdk.loadMods performs for a
-- mod outside mods/, done by hand here because options.lua also needs
-- intercepting in the same pass.
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
  "MOVES=ALL, TYPE CHART=modern, NATIONAL DEX=on loads with zero errors ("
    .. tostring(run.errors[1]) .. ")")

-- Every move id reachable from a fresh party or a fresh Bag, the same two
-- routes battle_forms_reachability_test.lua's own `reachable` helper checks
-- -- a learnset row or a tmhm entry, read off the REAL merged dataset.
local reachable = {}
for id, record in pairs(Data.pokemon) do
  if type(record) == "table" then
    for _, row in ipairs(record.learnset or {}) do reachable[row.move] = true end
    for _, moveId in ipairs(record.tmhm or {}) do reachable[moveId] = true end
  end
end

--------------------------------------------------------------------------
-- Direction 1: effectModeled = false never reaches a learnset or a tmhm.
--------------------------------------------------------------------------
local checkedFalse = 0
for id, record in pairs(Data.pokemon) do
  if type(record) == "table" then
    for _, row in ipairs(record.learnset or {}) do
      local move = Data.moves[row.move]
      if move then
        checkedFalse = checkedFalse + 1
        T.check(move.effectModeled ~= false,
          id .. "'s learnset carries " .. row.move
            .. ", which is effectModeled = false -- a placeholder reached "
            .. "a real Pokemon's moveset")
      end
    end
    for _, moveId in ipairs(record.tmhm or {}) do
      local move = Data.moves[moveId]
      if move then
        checkedFalse = checkedFalse + 1
        T.check(move.effectModeled ~= false,
          id .. "'s tmhm list carries " .. moveId
            .. ", which is effectModeled = false -- a placeholder reached "
            .. "a real Pokemon's moveset")
      end
    end
  end
end
T.check(checkedFalse > 1000,
  "precondition: MOVES=ALL actually widened enough learnsets for this "
    .. "check to mean something (checked " .. checkedFalse .. " entries)")

--------------------------------------------------------------------------
-- Direction 2: effectModeled = true is reachable, except the documented
-- sixteen. A future move joining this list without a matching row here
-- fails the count check below; a move LEAVING it (someone widens the
-- source data to cover it) fails the "still listed but reachable" check --
-- either way, the list drifting from reality is what fails, not a silent
-- pass.
--------------------------------------------------------------------------
local KNOWN_UNREACHABLE = {
  -- tutor-only, no engine mechanism exists (see the header above)
  BADDYBAD = true, FLOATYFALL = true, FREEZYFROST = true, GLITZYGLOW = true,
  SPARKLYSWIRL = true, SPLISHYSPLASH = true,
  -- level-up in a real game, but not this species' single chosen version
  -- group -- a version-group-selection policy question, reported not fixed
  HEALORDER = true, HEARTSTAMP = true, NEEDLEARM = true, STEAMROLLER = true,
}
local knownCount = 0
for _ in pairs(KNOWN_UNREACHABLE) do knownCount = knownCount + 1 end
T.eq(knownCount, 10, "the documented gap list itself names exactly ten -- "
  .. "0.27.0 closed six of the original sixteen with a machine (TM) route")

local checkedTrue, unexpectedGaps = 0, {}
for id, move in pairs(Data.moves) do
  if type(move) == "table" and move.effectModeled == true then
    checkedTrue = checkedTrue + 1
    if KNOWN_UNREACHABLE[id] then
      T.check(not reachable[id], id
        .. " is listed as a known, documented gap, but it IS reachable now "
        .. "-- remove it from KNOWN_UNREACHABLE, the gap has been closed")
    else
      T.check(reachable[id], id
        .. " is effectModeled = true and not in the documented gap list, "
        .. "but nothing teaches it -- either widen its source data or add "
        .. "it to KNOWN_UNREACHABLE with a reason, the same way this file's "
        .. "own header explains the other sixteen")
      if not reachable[id] then unexpectedGaps[#unexpectedGaps + 1] = id end
    end
  end
end
T.check(checkedTrue > 50,
  "precondition: a meaningful number of effectModeled=true moves exist to "
    .. "check (" .. checkedTrue .. ")")
T.eq(#unexpectedGaps, 0, "no UNDOCUMENTED gap turned up ("
  .. table.concat(unexpectedGaps, ", ") .. ")")

run.release()
T.finish("national_dex_effectmodeled")

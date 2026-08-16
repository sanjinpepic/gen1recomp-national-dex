-- src/machinemoves.lua: the byteless-TM pipeline that closes the "machine
-- route" slice of national_dex_effectmodeled_test.lua's own gap.
-- data/moves/generated/machine_teach.lua (tools/build_moves.py) supplies the
-- roster; this file only does three things per row -- register the item,
-- teach the eligible species, sell it -- and this suite pins each one
-- independently, the same discipline
-- dev/battle_forms_mod/tests/battle_forms_terablasttm_test.lua holds
-- src/terablasttm.lua to, because that file is this one's proof the
-- mechanism (an item's own `machine` field, taught through the engine's real
-- src/inventory/ItemEffects.lua path) actually works on this engine.
--
-- Three things this suite exists to prove and none of them for free:
--
--   1. M.eligible is the same form-pseudo-record test terablasttm.lua's own
--      M.eligible is, checked directly against a handful of shapes.
--
--   2. M.install's three jobs -- the item, the tmhm patches, the mart
--      listing -- degrade independently and stay gated on `widen` (MOVES=ALL,
--      the same gate src/moves.lua's own learnset widening runs under: a
--      GEN-NATIVE build promises every learnset stays byte-identical, and a
--      tmhm entry is exactly that kind of change).
--
--   3. Through the real loader, with MOVES=ALL: the roster this mod itself
--      built teaches GRASSYGLIDE onto BULBASAUR (one of tools/build_moves.py's
--      own six), byteless, sold at Celadon Mart 4F, and reachable through the
--      engine's real machine-item path end to end.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local FsIo = require("tests.fs_io")
local MOD = arg[0]:gsub("[/\\]tests[/\\][^/\\]+$", "")

local Machinemoves = dofile(MOD .. "/src/machinemoves.lua")

-- ---------------------------------------------------------------------
-- M.eligible: the same form-pseudo-record rule terablasttm.lua's own
-- M.eligible checks, so a form id can never be handed a tmhm entry no
-- battler's mon.species could ever match.
-- ---------------------------------------------------------------------
T.eq(Machinemoves.eligible({ id = "BULBASAUR" }), true, "an ordinary species is eligible")
T.eq(Machinemoves.eligible({ id = "CHARIZARD_MEGA_X", baseSpecies = "CHARIZARD", form = "MEGA_X" }),
  false, "a form pseudo-record -- both baseSpecies and form set -- is not")
T.eq(Machinemoves.eligible({ id = "ODD", baseSpecies = "CHARIZARD" }), true,
  "baseSpecies alone is not the form shape")
T.eq(Machinemoves.eligible({ id = "ODD2", form = "MEGA_X" }), true,
  "form alone is not the form shape either")
T.eq(Machinemoves.eligible(nil), false, "no record at all is never eligible")
T.eq(Machinemoves.eligible("not a table"), false, "a non-table record is never eligible")

-- ---------------------------------------------------------------------
-- M.install through a stub mod.
-- ---------------------------------------------------------------------
local function stubMod(opts)
  opts = opts or {}
  local registered = { items = {} }
  local patched = { pokemon = {}, text_pointers = {} }
  local warned = {}
  local moveRecords = opts.moves or {}
  local pokemonRecords = opts.pokemon or {}
  local mod = {
    content = {
      items = {
        register = function(_, id, record) registered.items[id] = record end,
      },
      moves = {
        get = function(_, id) return moveRecords[id] end,
      },
      pokemon = {
        get = function(_, id) return pokemonRecords[id] end,
        patch = function(_, id, partial)
          patched.pokemon[id] = patched.pokemon[id] or {}
          table.insert(patched.pokemon[id], partial)
        end,
      },
      text_pointers = opts.noTextPointers and nil or {
        patch = function(_, map, partial) patched.text_pointers[map] = partial end,
      },
    },
    log = {
      warn = function(_, fmt, ...) warned[#warned + 1] = fmt:format(...) end,
      info = function() end,
    },
  }
  return mod, registered, patched, warned
end

local ENTRIES = {
  { item = "TM172", move = "GRASSYGLIDE", number = 172,
    species = { "BULBASAUR", "IVYSAUR" } },
  { item = "TM173", move = "LASHOUT", number = 173, species = { "MEW" } },
}

-- widen = false: NOTHING happens, not even a dangling item -- GEN-NATIVE's
-- own promise (src/moves.lua's header) that every learnset stays
-- byte-identical to a build without the MOVES option.
do
  local mod, registered, patched, warned = stubMod({
    moves = { GRASSYGLIDE = { effectModeled = true } },
    pokemon = { BULBASAUR = {}, IVYSAUR = {} },
  })
  local result = Machinemoves.install(mod, ENTRIES, false)
  T.eq(next(registered.items), nil, "MOVES=GEN-NATIVE registers no item at all")
  T.eq(next(patched.pokemon), nil, "and teaches nothing")
  T.eq(next(patched.text_pointers), nil, "and sells nothing")
  T.eq(result.registered, 0, "reported as zero")
  T.eq(#warned, 0, "and nothing to warn about")
end

-- widen = true, every move modeled and every species present: all three
-- jobs go through.
do
  local mod, registered, patched, warned = stubMod({
    moves = {
      GRASSYGLIDE = { id = "GRASSYGLIDE", effectModeled = true },
      LASHOUT = { id = "LASHOUT", effectModeled = true },
    },
    pokemon = {
      BULBASAUR = { id = "BULBASAUR" }, IVYSAUR = { id = "IVYSAUR" },
      MEW = { id = "MEW" },
    },
  })
  local result = Machinemoves.install(mod, ENTRIES, true)

  T.check(registered.items.TM172 ~= nil, "TM172 is registered")
  T.eq(registered.items.TM172.id, "TM172", "under its own id")
  T.eq(registered.items.TM172.index, nil,
    "byteless on purpose -- no real bag byte is spent")
  T.eq(registered.items.TM172.machine.kind, "TM", "a TM")
  T.eq(registered.items.TM172.machine.move, "GRASSYGLIDE", "teaching GRASSYGLIDE")
  T.eq(registered.items.TM172.machine.number, 172, "carrying its own number")
  T.check(registered.items.TM172.price > 0, "never free")
  T.eq(registered.items.TM172.needsTarget, true, "needs a party target")
  T.eq(registered.items.TM172.tossable, true, "an ordinary, tossable TM")
  T.check(registered.items.TM173 ~= nil, "TM173 is registered too")

  T.check(patched.pokemon.BULBASAUR ~= nil, "BULBASAUR is taught")
  T.eq(patched.pokemon.BULBASAUR[1].tmhm.__append[1], "GRASSYGLIDE",
    "appending, never replacing, its tmhm list")
  T.check(patched.pokemon.IVYSAUR ~= nil, "IVYSAUR is taught too")
  T.check(patched.pokemon.MEW ~= nil, "and MEW, off the second entry")

  T.check(patched.text_pointers.CeladonMart4F ~= nil, "sold at Celadon Mart 4F")
  local mart = patched.text_pointers.CeladonMart4F.TEXT_CELADONMART4F_CLERK.mart
  local at = {}
  for i, id in ipairs(mart) do at[id] = i end
  T.check(at.TM172 and at.TM173, "both items are on the shelf")

  T.eq(result.registered, 2, "two items registered")
  T.eq(result.taught, 3, "three species-row teaches (2 + 1)")
  T.eq(#warned, 0, "nothing to warn about when every move and species exists")
end

-- A move that is not effectModeled = true (or does not exist at all): the
-- item still registers -- no invented item leaves a save carrying an id
-- nothing can resolve -- but with no `machine` field, and nothing is taught.
do
  local mod, registered, patched, warned = stubMod({
    moves = { GRASSYGLIDE = { effectModeled = false } },
    pokemon = { BULBASAUR = { id = "BULBASAUR" } },
  })
  local result = Machinemoves.install(mod, {
    { item = "TM172", move = "GRASSYGLIDE", number = 172, species = { "BULBASAUR" } },
  }, true)
  T.check(registered.items.TM172 ~= nil, "the item still registers")
  T.eq(registered.items.TM172.machine, nil,
    "but carries no machine field -- it would name a move with no real effect")
  T.eq(next(patched.pokemon), nil, "and nothing is taught")
  T.eq(#warned, 1, "the unmodeled move is reported")
  T.check(warned[1]:find("GRASSYGLIDE", 1, true) ~= nil, "naming it")
  T.eq(result.taught, 0, "reported as zero taught")
end

-- A form pseudo-record among the species list is skipped, never patched --
-- the same rule M.eligible states, exercised inside M.install itself.
do
  local mod, registered, patched = stubMod({
    moves = { GRASSYGLIDE = { effectModeled = true } },
    pokemon = {
      BULBASAUR = { id = "BULBASAUR" },
      VENUSAUR_MEGA = { id = "VENUSAUR_MEGA", baseSpecies = "VENUSAUR", form = "MEGA" },
    },
  })
  Machinemoves.install(mod, {
    { item = "TM172", move = "GRASSYGLIDE", number = 172,
      species = { "BULBASAUR", "VENUSAUR_MEGA" } },
  }, true)
  T.check(patched.pokemon.BULBASAUR ~= nil, "the ordinary species is taught")
  T.eq(patched.pokemon.VENUSAUR_MEGA, nil,
    "the form pseudo-record is never taught -- it can never be a battler's "
      .. "mon.species, so a tmhm entry on it would be unreachable regardless")
end

-- A species id the roster names but the registry does not carry (a stale
-- build, or a species this run never registered): skipped, not a crash.
do
  local mod, registered, patched = stubMod({
    moves = { GRASSYGLIDE = { effectModeled = true } },
    pokemon = { BULBASAUR = { id = "BULBASAUR" } },
  })
  Machinemoves.install(mod, {
    { item = "TM172", move = "GRASSYGLIDE", number = 172,
      species = { "BULBASAUR", "NOT_REGISTERED" } },
  }, true)
  T.check(patched.pokemon.BULBASAUR ~= nil, "the real species is still taught")
  T.eq(patched.pokemon.NOT_REGISTERED, nil, "the missing one is silently skipped")
end

-- No entries at all (a build that closed the gap by some other route and
-- shipped an empty machine_teach.lua): a no-op, not an error.
do
  local mod, registered, patched, warned = stubMod({})
  local result = Machinemoves.install(mod, {}, true)
  T.eq(result.registered, 0, "nothing to register")
  T.eq(next(patched.text_pointers), nil, "and nothing to sell")
end

-- entries is nil or malformed: degrades rather than raising.
do
  local mod = stubMod({})
  local ok = pcall(Machinemoves.install, mod, nil, true)
  T.check(ok, "a nil roster does not crash the load")
end

-- ---------------------------------------------------------------------
-- Through the real loader, with MOVES=ALL: the roster this mod's own build
-- produced (data/moves/generated/machine_teach.lua) teaches GRASSYGLIDE onto
-- BULBASAUR, byteless, and the item is sold at Celadon Mart 4F -- the real,
-- ROM-extracted engine, not a synthetic fixture.
-- ---------------------------------------------------------------------
do
  local Data = require("src.core.Data")
  Data:load()

  local ENCODED_OPTIONS = [[return {
    mods = { national_dex = true },
    modOptions = { national_dex = { national_dex = "on", type_chart = "modern",
                                     moves = "all" } },
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

  local run = T.sdk.loadMods({ "national_dex" }, { data = Data, fs = optionsFs() })
  T.eq(#run.errors, 0,
    "MOVES=ALL loads clean with the machine-TM pipeline live ("
      .. tostring(run.errors[1]) .. ")")

  local item = Data.items.TM172
  T.check(item ~= nil, "TM172 is registered")
  T.eq(item.index, nil, "byteless")
  T.eq(item.machine.move, "GRASSYGLIDE", "teaching GRASSYGLIDE")

  local bulbasaur = Data.pokemon.BULBASAUR
  T.check(bulbasaur ~= nil, "precondition: BULBASAUR is registered")
  local knows = false
  for _, id in ipairs(bulbasaur.tmhm or {}) do
    if id == "GRASSYGLIDE" then knows = true end
  end
  T.check(knows, "BULBASAUR's tmhm list carries GRASSYGLIDE")

  local mart = Data.text_pointers.CeladonMart4F.TEXT_CELADONMART4F_CLERK.mart
  local sold = false
  for _, id in ipairs(mart) do
    if id == "TM172" then sold = true end
  end
  T.check(sold, "TM172 is on the Celadon 4F shelf")
  local stillSold = false
  for _, id in ipairs(mart) do
    if id == "FIRE_STONE" then stillSold = true end
  end
  T.check(stillSold, "the vanilla stones are still on the shelf -- appended, not replaced")

  -- The teach, driven through the engine's OWN item-use code
  -- (src/inventory/ItemEffects.lua) rather than reimplemented here, exactly
  -- as battle_forms_terablasttm_test.lua's own final block does.
  local ItemEffects = require("src.inventory.ItemEffects")
  local save = { player = { name = "RED" } }
  local mon = { species = "BULBASAUR", moves = { { id = "TACKLE", pp = 35 } } }
  local result, payload = ItemEffects.use(Data, save, "TM172", mon)
  T.eq(result, "learn", "using TM172 on an eligible Pokemon offers to teach")
  T.eq(payload, "GRASSYGLIDE", "the move it offers is GRASSYGLIDE")

  run.release()
end

T.finish("national_dex_machinemoves")

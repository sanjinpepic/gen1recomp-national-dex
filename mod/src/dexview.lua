-- View modes for the Gen 1 Pokédex LISTING: the engine's own numerical order,
-- alphabetical, and the species this save has actually recorded.  START cycles
-- them and the mode is named on the title row beside POKéDEX.
--
-- With the national dex on, that screen is 1025 rows ordered by a number a
-- player mostly does not know.  Every other way into a species is by NAME --
-- the party, a trade, a conversation about one -- so a list that can only be
-- entered by its number is a list that has to be walked.
--
-- WHICH KEY.  The engine's list reads UP, DOWN, LEFT, RIGHT, A and B, plus
-- SELECT only when someone has set `onSelectKey` on it, which
-- src/ui/PokedexMenu.lua does not (src/ui/ListMenu.lua:137-179).  SELECT and
-- START are therefore both free, and this takes START on purpose:
--
--   * SELECT is where a dex MOD puts this.  useful_dex 1.3.0 binds it on this
--     very list to cycle its own num/alpha/caught, and Gold's own #DEX opens
--     its OPTION screen with it (src/ui/gen2/PokedexMenu.lua:361-366).  Taking
--     it would either clobber that neighbour's feature or force a detect-and-
--     stand-down whose result is that the key which works depends on what else
--     the player has installed.
--   * START is read nowhere on this screen -- not by the engine's list, not by
--     the neighbour -- so it is the same key with or without one, and no mod
--     has to lose anything for this to work.
--
-- The one thing that cannot be shared is WHO OWNS THE ROW ORDER.  A neighbour
-- that binds SELECT on this list is switching views of its own, and two owners
-- of one item array cannot both be right, so this stands down out loud when it
-- finds one (see the first-update check in `augment`) rather than fighting for
-- a screen it does not need to own.
--
-- Everything above M.apply is pure -- no love, no engine module, no mod handle
-- -- so the ordering, the filter and the cursor arithmetic are driven by tests
-- with plain tables.
--
-- A "row" here is one line of the listing: { dex = number, name = string,
-- known = boolean }, one per dex number the engine drew, in the engine's own
-- order.  A FORM is not a row and never becomes one: build_national_dex.py
-- numbers the 326 of them far above the real roster and src/nationaldex.lua
-- keeps dexSize off those numbers on purpose (see its FORM_DEX_BASE comment),
-- so `for n = 1, dexSize` never reaches them.  They stay where a player finds
-- them, on the entry page under LEFT/RIGHT, and sorting the listing by name
-- cannot pull twenty-six Alcremies in between two species.

local M = {}

-- ------------------------------------------------------------- pure logic

-- The cycle, in order, and the tag drawn for each.  Numerical is first and is
-- what a list opens in: it is the order the engine builds, the order the
-- entry pages number by and the order every guide ever written uses, so a
-- player who never presses START sees the screen they saw before this mod.
M.MODES = { "num", "alpha", "seen" }

-- The tag names the KEY as well as the mode.  Which view you are in is the
-- half that stops alphabetical reading as a corrupted list, but a player who
-- arrived somewhere by accident also needs to know what gets them back, and
-- the title row has room for both: POKéDEX ends at cell 7 and the longest of
-- these ends at cell 18 of 20.
M.TAG = { num = "START NUM", alpha = "START A-Z", seen = "START SEEN" }

-- The key a row sorts by.  Uppercased because the two halves of this list are
-- typed differently -- the cart's own 151 are "PIKACHU" and every species this
-- mod adds is "Chikorita" -- and a byte-wise sort would file all 874 newcomers
-- after all 151 natives and still call itself alphabetical.  ASCII-only by
-- design: string.upper leaves the multi-byte glyphs alone, so NIDORAN♀ and
-- NIDORAN♂ sort by their bytes, next to each other and always the same way
-- round, which is all this needs of them.
function M.sortKey(row)
  local name = type(row) == "table" and row.name or nil
  if type(name) ~= "string" then return "" end
  return name:upper()
end

function M.dexOf(row)
  local dex = type(row) == "table" and row.dex or nil
  return type(dex) == "number" and dex or 0
end

-- Alphabetical, over the rows a player can actually read.
--
-- An unrecorded row prints "052 -----", and a name nobody can see is a name
-- nobody can look up.  Sorting those rows by their real name would scatter
-- blanks through the list in an order the screen never explains, and it would
-- leak, in position, precisely the names the dashes are there to withhold.  So
-- the recorded rows sort by name and the rest follow in dex order: every
-- species is still reachable in this mode, which matters because dropping them
-- would make A-Z a second filter and there is already one of those.
--
-- Ties break on the dex number rather than on luck.  table.sort is not stable,
-- and two rows that compare equal both ways round is also the shape LuaJIT
-- rejects outright as an invalid order function.
function M.alphabetical(rows)
  local known, unknown = {}, {}
  if type(rows) ~= "table" then return known end
  for index, row in ipairs(rows) do
    if type(row) == "table" and row.known then
      known[#known + 1] = index
    else
      unknown[#unknown + 1] = index
    end
  end
  table.sort(known, function(a, b)
    local left, right = M.sortKey(rows[a]), M.sortKey(rows[b])
    if left ~= right then return left < right end
    return M.dexOf(rows[a]) < M.dexOf(rows[b])
  end)
  for _, index in ipairs(unknown) do known[#known + 1] = index end
  return known
end

-- Only the species this save has a record of.
--
-- `known` comes from the two tables the engine itself keeps -- save.pokedex.
-- seen and save.pokedex.owned -- because those are the only seen/caught state
-- Gen 1 has, and it is the same pair src/ui/PokedexMenu.lua consults to decide
-- whether a row gets a name or five dashes.  So this view is exactly the rows
-- that are not dashes, and exactly as long as the number the engine's own
-- footer is already calling SEEN at the bottom of the screen.
function M.recorded(rows)
  local out = {}
  if type(rows) ~= "table" then return out end
  for index, row in ipairs(rows) do
    if type(row) == "table" and row.known then out[#out + 1] = index end
  end
  return out
end

-- The next mode START moves to, skipping any view with nothing in it.
--
-- The skip is not tidiness.  A list with no items is a screen where the
-- engine's own update pops the stack on the next A or B (ListMenu.lua:143-150),
-- so cycling onto an empty recorded view on a save that has recorded nothing
-- would turn the very next button press into "the Pokédex closed itself".
-- `has` is a per-mode truth table; nil means all of them are available.
function M.nextMode(mode, has)
  local at = 1
  for index, name in ipairs(M.MODES) do
    if name == mode then at = index end
  end
  for step = 1, #M.MODES do
    local candidate = M.MODES[((at - 1 + step) % #M.MODES) + 1]
    if has == nil or has[candidate] then return candidate end
  end
  return mode
end

-- Where the cursor goes when the view changes.
--
-- On the same species, whenever the new view still has it: a mode change is a
-- change of route, not a change of destination, and someone who pressed START
-- while looking at Dragonite is asking where Dragonite sits alphabetically.
-- Only the recorded view can drop the row under the cursor, and then the
-- nearest one at or after its dex number is the closest thing to standing
-- still -- the neighbouring species is what was around the cursor anyway.
-- Past the end of the list, the last row.
function M.cursorFor(view, rows, target)
  if type(view) ~= "table" or #view == 0 then return 1 end
  for position, index in ipairs(view) do
    if index == target then return position end
  end
  local wanted = M.dexOf(type(rows) == "table" and rows[target] or nil)
  local after, afterDex, last, lastDex = nil, nil, nil, nil
  for position, index in ipairs(view) do
    local dex = M.dexOf(type(rows) == "table" and rows[index] or nil)
    if dex >= wanted and (afterDex == nil or dex < afterDex) then
      after, afterDex = position, dex
    end
    if lastDex == nil or dex > lastDex then last, lastDex = position, dex end
  end
  return after or last or 1
end

-- Scroll that keeps the cursor on the screen row it was already on.
--
-- The engine syncs scroll itself, but only far enough to drag the cursor back
-- into view (ListMenu.lua:102-107), which after a jump from row 900 to row 12
-- means the cursor lands on the top or bottom edge of the screen.  Holding the
-- row is what makes a mode change read as the list moving under a cursor that
-- stayed put, and it costs one clamp: never past the end of the list, never
-- off the window in either direction.
function M.scrollFor(index, screenRow, count, window)
  if type(index) ~= "number" or type(count) ~= "number"
    or type(window) ~= "number" or window < 1 then
    return 0
  end
  local row = type(screenRow) == "number" and screenRow or 1
  local scroll = index - math.max(1, math.min(row, window))
  scroll = math.min(scroll, math.max(0, count - window))
  if index - scroll > window then scroll = index - window end
  if index - scroll < 1 then scroll = index - 1 end
  return math.max(0, scroll)
end

-- ------------------------------------------------------------ engine patch

-- Required lazily and guarded, exactly the way src/dexpage.lua's requireAll
-- is: a missing or reshaped module costs this feature and nothing else, and
-- no headless caller of the pure half above pulls love or src.* in behind it.
local function requireAll()
  local names = { "src.render.Font", "src.core.Strings" }
  local found = {}
  for _, name in ipairs(names) do
    local ok, value = pcall(require, name)
    if not ok or type(value) ~= "table" then return nil end
    found[name] = value
  end
  return found
end

local function report(mod, message)
  if mod and mod.log and type(mod.log.info) == "function" then
    mod.log:info(message)
  end
end

-- The rows the engine drew, described again from the same two sources it used.
--
-- Deliberately a re-derivation rather than a reading of the built items: the
-- label is "025 PIKACHU" or "025 -----" and parsing a name back out of it
-- would depend on the number width, on the neighbour that may have written it,
-- and on a species whose name starts with a digit never existing.  Both loops
-- below are the ones in src/ui/PokedexMenu.lua:16-26, so the answer lines up
-- row for row -- and when it does not, that mismatch is the guard that stops
-- this reordering a list it does not understand.
local function describe(game)
  local constants = type(game.data.constants) == "table"
    and game.data.constants or {}
  local size = type(constants.dexSize) == "number" and constants.dexSize or 151
  local byDex = {}
  for _, def in pairs(game.data.pokemon) do
    if type(def) == "table" and def.dex then byDex[def.dex] = def end
  end
  local dex = type(game.save) == "table" and game.save.pokedex or nil
  local seen = type(dex) == "table" and type(dex.seen) == "table"
    and dex.seen or {}
  local owned = type(dex) == "table" and type(dex.owned) == "table"
    and dex.owned or {}
  local rows = {}
  for n = 1, size do
    local def = byDex[n]
    if type(def) == "table" then
      rows[#rows + 1] = {
        dex = n,
        name = type(def.name) == "string" and def.name or tostring(def.id),
        known = (owned[def.id] or seen[def.id]) and true or false,
      }
    end
  end
  return rows
end

local function augment(list, mod)
  local modules = requireAll()
  if not modules then
    report(mod, "the Pokédex listing's view modes need the font and string "
      .. "modules and this engine did not hand them over -- the list keeps "
      .. "dex order and START does nothing")
    return false
  end
  local Font = modules["src.render.Font"]
  local Strings = modules["src.core.Strings"]

  local game = type(list) == "table" and list.game or nil
  if type(list) ~= "table" or type(list.items) ~= "table"
    or type(list.update) ~= "function" or type(list.draw) ~= "function"
    or type(list.index) ~= "number" or type(list.scroll) ~= "number"
    or type(list.rows) ~= "number"
    or type(game) ~= "table" or type(game.data) ~= "table"
    or type(game.data.pokemon) ~= "table" then
    report(mod, "the Pokédex listing is not this engine's own list -- view "
      .. "modes reorder its item array and its cursor, and standing down is "
      .. "the only safe answer to a screen of a shape this cannot read")
    return false
  end

  local rows = describe(game)
  if #rows == 0 then
    report(mod, "the Pokédex listing has no species in dex range -- there is "
      .. "nothing for the view modes to order, so START does nothing")
    return false
  end
  if #rows ~= #list.items then
    report(mod, ("the Pokédex listing has %d rows where the dex numbers this "
      .. "engine holds make %d -- another mod is choosing the rows, and "
      .. "reordering a list this one did not build would put the wrong "
      .. "species under the cursor, so the view modes stand down")
      :format(#list.items, #rows))
    return false
  end

  -- The numerical view is the identity, and its items array is the very one
  -- the constructor built: switching back to NUM restores the original object,
  -- not a copy of it, so a neighbour holding a reference to that array still
  -- holds the array the player is looking at.
  local numerical = {}
  for index = 1, #rows do numerical[index] = index end
  local original = list.items

  local views = { num = numerical }
  local function viewFor(mode)
    local view = views[mode]
    if view == nil then
      if mode == "alpha" then
        view = M.alphabetical(rows)
      elseif mode == "seen" then
        view = M.recorded(rows)
      else
        view = numerical
      end
      views[mode] = view
    end
    return view
  end

  local function itemsFor(view)
    if view == numerical then return original end
    local items = {}
    for position, index in ipairs(view) do items[position] = original[index] end
    return items
  end

  local mode, current = "num", numerical

  local function switch(self, wanted)
    local view = viewFor(wanted)
    if type(view) ~= "table" or #view == 0 then return false end
    -- Which SPECIES the cursor is on has to be read before anything moves,
    -- and it is read in ROW terms -- the item under the cursor belongs to
    -- current[index], whatever order the current view happens to be in.
    local at = math.max(1, math.min(self.index, #current))
    local target = current[at] or 1
    local screenRow = self.index - self.scroll
    local items = itemsFor(view)
    local position = M.cursorFor(view, rows, target)
    self.items = items
    self.index = position
    self.scroll = M.scrollFor(position, screenRow, #items, self.rows)
    mode, current = wanted, view
    return true
  end

  local off = false
  local checked = false

  local originalUpdate = list.update
  list.update = function(self, dt)
    -- The neighbour check runs on the first frame rather than at install
    -- time, because a mod that REPLACES the dex screen builds this very list
    -- inside its own factory and decorates what comes back -- useful_dex
    -- 1.3.0's list IS the engine's, with wrap and an onSelectKey written onto
    -- it afterwards -- so at the moment this file runs there is nothing to
    -- see.  Before the original update, so the first press of anything is
    -- already judged by the answer.
    if not checked then
      checked = true
      if type(self.onSelectKey) == "function" then
        off = true
        report(mod, "another mod has bound SELECT on the Pokédex listing, "
          .. "which is where a dex mod puts its own view switching -- two "
          .. "owners of one row order cannot both be right, so this mod's "
          .. "list modes stand down and leave the screen to it")
      end
    end
    originalUpdate(self, dt)
    if off then return end
    local input = self.game and self.game.input
    if type(input) ~= "table" or type(input.wasPressed) ~= "function" then
      return
    end
    if input:wasPressed("start") then
      -- Availability is asked for at the press rather than kept, because the
      -- answer builds the views themselves and a dex opened and closed without
      -- ever pressing START should never have paid to sort 1025 rows.
      local wanted = M.nextMode(mode, {
        num = true,
        alpha = #viewFor("alpha") > 0,
        seen = #viewFor("seen") > 0,
      })
      if wanted ~= mode then switch(self, wanted) end
    end
  end

  local originalDraw = list.draw
  list.draw = function(self)
    originalDraw(self)
    if off then return end
    -- The list has already drawn by the time this runs, so a tag that threw
    -- costs the tag and leaves the screen standing -- which is the whole
    -- reason it is drawn after rather than woven in.
    pcall(function()
      local tag = Strings(M.TAG[mode] or M.TAG.num)
      love.graphics.setColor(0, 0, 0, 1)
      -- Right margin, on the title's own row: the list draws POKéDEX at
      -- (8, 4) and its first entry at y = 24, so this is the one line on the
      -- screen with nothing else on it.
      Font.draw(tag, 160 - 8 - Font.width(tag), 4)
      love.graphics.setColor(1, 1, 1, 1)
    end)
  end

  return true
end

-- Adds the view modes to one built listing, or answers false having said why.
-- Never throws: the caller is a constructor patch riding under a neighbour's
-- screen, and a throw there degrades that screen to the builtin one and costs
-- its owner every feature it came with.
function M.apply(list, mod)
  local ok, applied = pcall(augment, list, mod)
  if not ok then
    report(mod, ("the Pokédex listing's view modes failed to install (%s) -- "
      .. "the list keeps dex order and nothing else changes")
      :format(tostring(applied)))
    return false
  end
  return applied and true or false
end

setmetatable(M, { __call = function(_, list, mod) return M.apply(list, mod) end })

return M

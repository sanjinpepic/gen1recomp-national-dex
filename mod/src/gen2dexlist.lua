-- Gold's #DEX: the beyond-251 species in the listing, and alternate-form
-- browsing on the entry screen.
--
-- Why this file exists at all, and why none of it is a constant patch:
--
-- On Gen 1 the listing's length is a constant.  src/ui/PokedexMenu.lua:26
-- walks `for n = 1, constants.dexSize or 151`, so src/nationaldex.lua's
-- mod.content.constants:patch("dexSize", ...) is the whole feature.  Neither
-- half of that holds on Gold:
--
--   * The patch does not land where Gen 1's does.  src/mods/Schemas.lua:485
--     routes the `constants` registry to `gen2Constants` on a Gen 2 boot, so
--     the write reaches data.gen2Constants.dexSize instead of
--     data.constants.dexSize.  `dexSize` is not among R.constants.gen2Keys
--     either (Schemas.lua:1866-1882 -- that catalog is the ordered ROM lists
--     plus a fixed handful), so it merges as a mod's own unrecognised key.
--     No error is raised and nothing reads it back: the patch succeeds and
--     means nothing.
--   * Even landing it in data.constants would change nothing, because Gold's
--     screen never reads dexSize.  src/ui/gen2/PokedexMenu.lua sizes its list
--     from the ROM's own dex table: :order() (line 244) and :rebuild() (257)
--     build self.rows out of data.gen2Pokedex.entries, and a species with no
--     entry there is skipped outright (line 264, `if entry then`).
--
-- And data.gen2Pokedex has no registry pointing at it -- it is loaded straight
-- from the ROM cache in src/core/Game2.lua:879 and appears nowhere in
-- Schemas.GEN2.  There is therefore no sanctioned content route to widen
-- Gold's dex, which is what leaves an in-memory patch of Gold's own class as
-- the only seam, the same technique src/dexpage.lua uses on Gen 1.
--
-- The class is reached by its REAL name.  A mod's require is not redirected on
-- a Gold boot -- both generations ship in one archive, so
-- require("src.ui.PokedexMenu") would hand back Gen 1's class here and this
-- file would patch something Gold never draws.  Nothing below chooses its
-- behaviour by probing which methods exist, for the same reason: that probe
-- answers "yes" on the wrong class.  M.install refuses to run at all unless
-- the caller says generation 2.
--
-- Everything above M.install is pure -- no love, no engine module, no mod
-- handle -- so tests exercise it with plain tables.

local M = {}

-- ------------------------------------------------------------- pure logic

-- Gold's dex box is 18 columns wide and ClearBox(2,11) gives the description
-- three rows per page, stepped by the <NEXT> marker
-- (src/ui/gen2/PokedexMenu.lua:983-996).  This mod's dex text is flowing prose
-- written for Gen 1's own wrapper, so it has to be broken to that shape here
-- or it draws off the right edge of the window.
local LINE_COLS, PAGE_LINES = 18, 3

-- Splits on spaces, and hard-splits a single word longer than the box rather
-- than letting it overhang -- a chemical-formula-length token is rare in dex
-- prose but costs one branch to survive.
function M.wrapLines(text)
  local lines, current = {}, ""
  local function flush()
    if current ~= "" then lines[#lines + 1] = current end
    current = ""
  end
  for word in tostring(text or ""):gmatch("%S+") do
    while #word > LINE_COLS do
      flush()
      lines[#lines + 1] = word:sub(1, LINE_COLS)
      word = word:sub(LINE_COLS + 1)
    end
    local candidate = current == "" and word or (current .. " " .. word)
    if #candidate <= LINE_COLS then
      current = candidate
    else
      flush()
      current = word
    end
  end
  flush()
  return lines
end

-- The entry's two pages, each already <NEXT>-joined the way the ROM's own
-- strings arrive.  Anything past six lines is dropped: the screen has nowhere
-- to put it, and a third page is not a thing Gold's PAGE action can reach.
function M.wrapPages(text)
  local lines = M.wrapLines(text)
  local function page(from)
    local out = {}
    for i = from, math.min(from + PAGE_LINES - 1, #lines) do
      out[#out + 1] = lines[i]
    end
    return table.concat(out, "<NEXT>")
  end
  return page(1), page(1 + PAGE_LINES)
end

-- Both numbers the entry screen prints are PrintNum fields holding the DIGITS
-- rather than a physical measure: the height word is four digits with two in
-- front of the point (204 draws as 2'04") and the weight word five with four
-- in front (150 draws as 15.0 lb).  src/import/RomExtractorGen2.lua:4437-4442
-- is where the cart's own values get that treatment; this mod's records carry
-- feet/inches and pounds separately, so they are folded the same way.
function M.heightWord(dexEntry)
  local d = type(dexEntry) == "table" and dexEntry or {}
  local feet = type(d.heightFt) == "number" and d.heightFt or 0
  local inches = type(d.heightIn) == "number" and d.heightIn or 0
  return math.floor(feet) * 100 + math.floor(inches)
end

function M.weightWord(dexEntry)
  local d = type(dexEntry) == "table" and dexEntry or {}
  local pounds = type(d.weight) == "number" and d.weight or 0
  return math.floor(pounds * 10 + 0.5)
end

-- One synthetic row of data.gen2Pokedex.entries, in the shape the extractor
-- writes (RomExtractorGen2.lua:4450-4454) and the screen reads back:
-- { id, dex, kind, height, weight, text, text2 }.
function M.entryFor(record, description)
  local page1, page2 = M.wrapPages(description)
  local dexEntry = record.dexEntry
  return {
    id = record.id,
    dex = record.dex,
    kind = (type(dexEntry) == "table" and dexEntry.kind) or "",
    height = M.heightWord(dexEntry),
    weight = M.weightWord(dexEntry),
    text = page1,
    text2 = page2,
  }
end

-- Which species in the merged roster the cart's dex has no row for, in dex
-- order.  Deliberately "whatever `entries` is missing" rather than "anything
-- above 251": with the NATIONAL DEX option off this mod registers nothing
-- beyond the cart's own roster, so the same walk adds nothing and Gold's list
-- stays exactly the 251 it shipped with -- the option stays the only control,
-- and no second Gen 2-specific switch has to agree with it.
--
-- Two records are passed over.  A FORM is never a list row: its `dex` is
-- deliberately its BASE species' number (src/nationaldex.lua), so admitting
-- one would put a second claim on a number already in the list.  And a
-- species whose number some existing entry already holds is skipped too --
-- :order() indexes by `entry.dex` (PokedexMenu.lua:251-252), so a collision
-- silently replaces the row already there instead of adding one.
function M.newSpecies(pokemon, entries)
  entries = type(entries) == "table" and entries or {}
  local claimed = {}
  for _, entry in pairs(entries) do
    if type(entry) == "table" and type(entry.dex) == "number" then
      claimed[entry.dex] = true
    end
  end
  local out = {}
  if type(pokemon) ~= "table" then return out end
  for id, record in pairs(pokemon) do
    if type(record) == "table" and record.form == nil
      and type(record.dex) == "number"
      and entries[id] == nil and not claimed[record.dex] then
      claimed[record.dex] = true
      out[#out + 1] = { id = id, record = record }
    end
  end
  -- Sorted by dex number so the listing reads in national order and, more
  -- importantly, so the order is the same on every boot: a `pairs` walk over
  -- a hash part promises nothing, and an unstable list would reshuffle under
  -- a player between sessions with nothing in the save having changed.
  table.sort(out, function(a, b)
    if a.record.dex == b.record.dex then return a.id < b.id end
    return a.record.dex < b.record.dex
  end)
  return out
end

-- ------------------------------------------------------------ engine patch

-- Required once, guarded exactly the way src/dexpage.lua guards its own
-- imports: a missing or reshaped module means this feature does not install
-- rather than taking the mod load down, and nothing here runs at file scope,
-- so a headless test that only wants the pure half above never touches love.
local function requireGen2Menu()
  local ok, value = pcall(require, "src.ui.gen2.PokedexMenu")
  if not ok or type(value) ~= "table" then return nil end
  return value
end

-- installed guards against a second install patching the patch -- main.lua
-- calls this once, but the class is process-global and a reload would
-- otherwise stack wrappers until the call depth mattered.
local installed = false

-- `generation` is handed in rather than probed here.  See the file banner: the
-- one thing this must never do is decide it is on Gold because a Gold-shaped
-- method answered.  No `mod` handle is taken, unlike the siblings: everything
-- this installs reads the running game off the menu instance it patches, and
-- an argument it never used would only suggest otherwise.
function M.install(generation, buildFormList)
  if generation ~= 2 then return false end
  if installed then return false end
  local PokedexMenu = requireGen2Menu()
  if not PokedexMenu then return false end
  if type(PokedexMenu.rebuild) ~= "function"
    or type(PokedexMenu.update) ~= "function"
    or type(PokedexMenu.picFor) ~= "function"
    or type(PokedexMenu.drawEntryBody) ~= "function" then
    return false
  end

  -- The dex-page text this mod registered.  On a Gen 2 boot the `text`
  -- registry routes to gen2Text (Schemas.lua:486), so that -- not data.text --
  -- is where a record's dexEntry.text id resolves.
  local function describe(data, record)
    local dexEntry = record.dexEntry
    local id = type(dexEntry) == "table" and dexEntry.text or nil
    if type(id) ~= "string" then return "" end
    local text = data and data.gen2Text and data.gen2Text[id]
    return type(text) == "string" and text or ""
  end

  -- Builds this menu's own view of the dex table, once per instance.  A COPY
  -- rather than a write into data.gen2Pokedex: that table is shared by
  -- reference with src/ui/gen2/Pokegear.lua:1306, and growing the table it
  -- walks is a side effect this feature has no business having.
  local function augment(self)
    if self.nationalDexView then
      self.dex = self.nationalDexView
      return
    end
    local base = self.dex
    if type(base) ~= "table" or type(base.entries) ~= "table" then return end
    local added = M.newSpecies(self.pokemon, base.entries)
    if #added == 0 then return end

    local entries = {}
    for id, entry in pairs(base.entries) do entries[id] = entry end
    local data = self.game and self.game.data
    local ids = {}
    for _, item in ipairs(added) do
      entries[item.id] = M.entryFor(item.record, describe(data, item.record))
      ids[#ids + 1] = item.id
    end

    local view = {}
    for key, value in pairs(base) do view[key] = value end
    view.entries = entries
    -- Gold opens in NEW (Johto) order and offers A-Z beside it, and :order()
    -- returns those precomputed lists untouched when they exist
    -- (PokedexMenu.lua:248-249).  Widening only `entries` would therefore fix
    -- nothing a player actually sees on the screen the dex opens on.  The new
    -- ids are APPENDED to the cart's own lists rather than merged into them:
    -- the ROM's ordering is not ours to rearrange, and a player who knows
    -- where MEGANIUM sits in the Johto list should still find it there.
    view.newOrder = M.appended(base.newOrder, ids)
    view.alphabeticalOrder = M.appended(base.alphabeticalOrder,
      M.byName(self.pokemon, ids))
    self.nationalDexView = view
    self.dex = view
  end

  local originalRebuild = PokedexMenu.rebuild
  function PokedexMenu:rebuild()
    -- Before, not after: rebuild reads self.dex to build the rows, and every
    -- mode change comes back through here.
    pcall(augment, self)
    originalRebuild(self)
  end

  -- OLD (national) mode has no precomputed list: :order() builds one by
  -- indexing each species at its own dex NUMBER (PokedexMenu.lua:251-252),
  -- which leaves a hole wherever a number has no species -- and :rebuild()
  -- walks that result with ipairs, which stops dead at the first hole.  The
  -- cart never exposed this because its own 251 numbers are contiguous.  A
  -- national roster is only contiguous while every species registers, and
  -- src/nationaldex.lua guards each registration individually precisely
  -- because one can fail; a single skipped species would otherwise truncate
  -- the entire listing from that number on.  Compacting is a no-op on a
  -- gapless list, so this costs the healthy case nothing.
  local originalOrder = PokedexMenu.order
  function PokedexMenu:order()
    local list = originalOrder(self)
    if type(list) ~= "table" then return list end
    local highest = 0
    for index in pairs(list) do
      if type(index) == "number" and index > highest then highest = index end
    end
    local compact, count = {}, 0
    for index = 1, highest do
      if list[index] ~= nil then
        count = count + 1
        compact[count] = list[index]
      end
    end
    return compact
  end

  -- ------- alternate forms
  --
  -- NOT on LEFT/RIGHT, which is the one place this deliberately parts company
  -- with the Gen 1 page (src/dexpage.lua).  On Gold those two keys are
  -- already taken: they walk the arrow across PAGE / AREA / CRY / PRNT
  -- (PokedexMenu.lua:333-336), and the comment directly above that code
  -- records what happens when something else claims them -- "quietly makes
  -- three of the four actions unreachable -- AREA among them".  Rebinding
  -- them here would re-break the cart's own entry screen, and would do it
  -- only for the species that have forms, which is the worst version of it.
  -- UP/DOWN are read by no branch of the entry view, so they are free, and
  -- they keep the browsing bidirectional.
  local function formsFor(self, species)
    if self.formBase == species then return self.formList end
    local list = { species }
    if type(buildFormList) == "function" then
      local ok, built = pcall(buildFormList, self.pokemon, species)
      if ok and type(built) == "table" and #built > 0 then list = built end
    end
    self.formBase = species
    self.formList = list
    self.formIndex = 1
    self.formId = species
    return list
  end

  local function cycleForm(self, step)
    local row = self:current()
    if not row then return end
    local list = formsFor(self, row.species)
    if #list < 2 then return end
    self.formIndex = ((self.formIndex - 1 + step) % #list) + 1
    self.formId = list[self.formIndex]
  end

  local originalUpdate = PokedexMenu.update
  function PokedexMenu:update(dt)
    local entryView = self.view == "entry" and not self.newEntry
    local up, down = false, false
    if entryView then
      pcall(function()
        local input = self.game and self.game.input
        if not input then return end
        up, down = input:wasPressed("up"), input:wasPressed("down")
      end)
    end
    local wasView = self.view
    originalUpdate(self, dt)
    -- Opening an entry always starts on the base species.  Without this the
    -- selection is sticky across the whole session: browse to MEGA VENUSAUR,
    -- back out, and every later visit to BULBASAUR would open already showing
    -- the mega.  Gen 1's page gets this for free by rebuilding its form state
    -- in the constructor (src/dexpage.lua) -- Gold reuses one menu instance
    -- for every species, so the reset has to be explicit.
    if self.view == "entry" and wasView ~= "entry" then
      self.formBase, self.formList, self.formIndex, self.formId = nil, nil, 1, nil
    end
    -- After the engine's own pass, and only while the entry screen is still
    -- the live view -- so a press that closed the page cannot also move a
    -- form underneath it.
    if (up or down) and self.view == "entry" then
      pcall(cycleForm, self, up and -1 or 1)
    end
  end

  -- The selected form's own art, resolved by asking the engine's own lookup
  -- for the FORM's record -- which reuses its path cache and its Unown
  -- special case rather than reimplementing either.  Falls back to the base
  -- species whenever the form has no art of its own, so a form this mod
  -- registered without a picture shows its base rather than a blank box.
  local originalPicFor = PokedexMenu.picFor
  function PokedexMenu:picFor(species)
    local formId = self.formId
    if formId and formId ~= species and self.formBase == species then
      local ok, image = pcall(originalPicFor, self, formId)
      if ok and image then return image end
    end
    return originalPicFor(self, species)
  end

  -- A form's label goes where the base species' category sits.  Nothing else
  -- on the page moves: No., name, height, weight and the description stay the
  -- BASE species' own, because `entry` here is still the row's own dex record
  -- and this only ever replaces one string on a copy of it.  That is the same
  -- rule src/dexpage.lua holds to -- a form must never print its synthetic
  -- `dex` key -- and it holds here by construction, since nothing in this
  -- function can reach a form record's `dex` at all.
  local originalBody = PokedexMenu.drawEntryBody
  function PokedexMenu:drawEntryBody(row, entry)
    local formId = self.formId
    if formId and row and formId ~= row.species and self.formBase == row.species
      and type(entry) == "table" then
      local record = self.pokemon and self.pokemon[formId]
      local label = type(record) == "table" and record.form or nil
      if type(label) == "string" then
        local copy = {}
        for key, value in pairs(entry) do copy[key] = value end
        copy.kind = (label:gsub("_", " "))
        entry = copy
      end
    end
    return originalBody(self, row, entry)
  end

  installed = true
  return true
end

-- Kept beside newSpecies rather than inside install: both are list shaping
-- with no engine in them, and the tests drive them directly.
function M.appended(list, ids)
  if type(list) ~= "table" then return nil end
  local out = {}
  for index, value in ipairs(list) do out[index] = value end
  for _, id in ipairs(ids) do out[#out + 1] = id end
  return out
end

-- The added ids sorted by the name the screen actually prints, so the A-Z tail
-- reads alphabetically even though the ids themselves are not the display
-- names.  Falls back to the id when a record has no name, which is also what
-- PokedexMenu:monName does (line 397).
function M.byName(pokemon, ids)
  local out = {}
  for index, id in ipairs(ids) do out[index] = id end
  local function nameOf(id)
    local record = type(pokemon) == "table" and pokemon[id] or nil
    local name = type(record) == "table" and record.name or nil
    return type(name) == "string" and name:upper() or tostring(id)
  end
  table.sort(out, function(a, b)
    local na, nb = nameOf(a), nameOf(b)
    if na == nb then return a < b end
    return na < nb
  end)
  return out
end

setmetatable(M, { __call = function(_, generation, buildFormList)
  return M.install(generation, buildFormList)
end })

return M

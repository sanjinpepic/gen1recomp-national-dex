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
-- handle -- so tests exercise it with plain tables.  M.spriteArt, the last of
-- them, holds to that at file scope and reaches for one engine module only
-- from inside the closure it returns, once a draw has actually asked.
--
-- The pic is the second thing Gold's dex resolves for itself and never asks
-- about: see M.spriteArt for why the sprite mod cannot reach this screen, and
-- the drawPic patch for why the art also has to be drawn here rather than
-- handed back to the cart's own draw.

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

-- ------------------------------------------------- the sprite mod's art

-- The id of the neighbour this asks, and the export it asks through.
M.SPRITE_MOD = "universal_sprites"

-- Gold's dex draws the CART's pic and offers no seam to change it:
-- src/ui/gen2/PokedexMenu.lua:400 reads record.spriteFront through
-- Assets.image and raises no hook, which is why a sprite mod cannot reach
-- this screen from its own side and why the reach has to be made from here.
--
-- Returns a resolver -- (pokemon, speciesId, data) -> path, trueColor -- or
-- nil when there is nothing to ask.  The whole integration is OPTIONAL: no
-- neighbour, a disabled one, or one with no art for a species all answer nil
-- and Gold's own pic is drawn exactly as before.
--
-- TWO questions are asked, of two different places, because neither can
-- answer the other's:
--
--   * WHETHER, and WHICH art -- universal_sprites' own `resolveSprite`
--     export (dev/src/api.lua), the same activeRegistry():resolve call its
--     battle path makes.  nil means "we have nothing for this species", and
--     it is the only lookup that can say so: the engine's Sprites.path hands
--     back the vanilla path in that case, which is indistinguishable from a
--     mod answering with art that happens to be the cart's.
--   * HOW to draw it -- the trueColor flag off the engine's own
--     pokemon.sprite seam, which is where the sprite mod publishes its RENDER
--     STYLE decision (a four-shade NATIVE set answers false and MUST keep the
--     GBC palette; full-colour art answers true and must not).  No export
--     carries that, and guessing it wrong is visible either way round: a
--     shaded full-colour pic, or a grey one.
--
-- Resolved lazily and re-asked until it answers, the way
-- dev/src/compat_voxel.lua reaches its own neighbour: mod:find is nil until
-- the other mod has run, and load order between two mods is not ours to pin.
function M.spriteArt(find, formCandidates, sprites)
  if type(find) ~= "function" then return nil end
  local resolve
  local function export()
    if resolve then return resolve end
    local ok, handle = pcall(find, M.SPRITE_MOD)
    if not ok or type(handle) ~= "table" or type(handle.exports) ~= "table" then
      return nil
    end
    local fn = handle.exports.resolveSprite
    if type(fn) ~= "function" then return nil end
    resolve = fn
    return fn
  end

  -- The engine module is required HERE rather than at file scope: this file
  -- is loaded by every boot, Gen 1 included, and the pure half above is
  -- driven by tests that must never pull an engine module in.
  local loadedSprites = sprites
  local function spritesModule()
    if loadedSprites ~= nil then return loadedSprites or nil end
    local ok, value = pcall(require, "src.pokemon.Sprites")
    loadedSprites = (ok and type(value) == "table") and value or false
    return loadedSprites or nil
  end

  return function(pokemon, speciesId, data)
    local fn = export()
    if not fn then return nil, false end
    -- A FORM is asked for as "base species, wearing form X", never by its own
    -- compound id -- the registry keys form art underneath the BASE species,
    -- so CHARIZARD_MEGA_X matches no entry at all.  Same rule, and the same
    -- squashed-spelling retry, as src/dexpage.lua's own art lookup; sharing
    -- that function is what keeps the two games spelling a form alike.
    local record = type(pokemon) == "table" and pokemon[speciesId] or nil
    local lookupId, form, altForm = speciesId, nil, nil
    if type(formCandidates) == "function" then
      local ok, base, id, alt = pcall(formCandidates, record, speciesId)
      if ok and type(base) == "string" then
        lookupId, form, altForm = base, id, alt
      end
    end
    local function ask(formId)
      local ok, path = pcall(fn, { species = lookupId, side = "front",
        kind = "dex", form = formId })
      if not ok or type(path) ~= "string" or path == "" then return nil end
      return path
    end
    local path = ask(form)
    -- A form miss is silent -- it returns exactly what the base species
    -- alone returns -- so it is detected rather than guessed at.
    if altForm and path == ask(nil) then
      local alt = ask(altForm)
      if alt and alt ~= path then path, form = alt, altForm end
    end
    if not path then return nil, false end

    -- Full colour unless the sprite mod says otherwise.  Its own hook answers
    -- for the ctx it is given, so the form is passed on too and the flag
    -- describes the very art resolved above.  The flag is only read when the
    -- seam answered with a PATH: Sprites.path returns `nil, false` for a
    -- species it cannot resolve at all, and reading that as "shade it" would
    -- crush the art on exactly the species this feature exists for.  An
    -- unreadable answer therefore keeps the default -- art supplied for this
    -- is full colour, and the failure that costs a player something is
    -- shading it, not leaving it alone.
    local trueColor = true
    local module = spritesModule()
    if module and type(module.path) == "function" then
      local ok, resolved, flag = pcall(module.path, data, lookupId, "front",
        { kind = "dex", mon = form and { form = form } or nil })
      if ok and type(resolved) == "string" and flag == false then
        trueColor = false
      end
    end
    return path, trueColor
  end
end

-- ------------------------------------------------------------ engine patch

-- Required once, guarded exactly the way src/dexpage.lua guards its own
-- imports: a missing or reshaped module means this feature does not install
-- rather than taking the mod load down, and nothing here runs at file scope,
-- so a headless test that only wants the pure half above never touches love.
local function requireGen2Menu()
  local names = { "src.ui.gen2.PokedexMenu", "src.render.GbcPalette",
    "src.world.gen2.Palettes" }
  local mods = {}
  for _, name in ipairs(names) do
    local ok, value = pcall(require, name)
    if not ok or type(value) ~= "table" then return nil end
    mods[name] = value
  end
  return mods
end

-- installed guards against a second install patching the patch -- main.lua
-- calls this once, but the class is process-global and a reload would
-- otherwise stack wrappers until the call depth mattered.
local installed = false

-- `generation` is handed in rather than probed here.  See the file banner: the
-- one thing this must never do is decide it is on Gold because a Gold-shaped
-- method answered.  No `mod` handle is taken, unlike the siblings: everything
-- this installs reads the running game off the menu instance it patches, and
-- an argument it never used would only suggest otherwise -- `resolveArt` is
-- M.spriteArt's closure for the same reason, already holding whatever it
-- needed of the mod API.
function M.install(generation, buildFormList, resolveArt)
  if generation ~= 2 then return false end
  if installed then return false end
  local mods = requireGen2Menu()
  if not mods then return false end
  local PokedexMenu = mods["src.ui.gen2.PokedexMenu"]
  local GbcPalette = mods["src.render.GbcPalette"]
  local Palettes = mods["src.world.gen2.Palettes"]
  if type(PokedexMenu.rebuild) ~= "function"
    or type(PokedexMenu.update) ~= "function"
    or type(PokedexMenu.picFor) ~= "function"
    or type(PokedexMenu.drawPic) ~= "function"
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

  -- Which record's art the screen is actually showing: the browsed form while
  -- one is selected, the row's own species otherwise.  Both halves below read
  -- it, so the pic and the palette decision can never disagree about what is
  -- on screen.
  local function shownSpecies(self, species)
    local formId = self.formId
    if formId and formId ~= species and self.formBase == species then
      return formId
    end
    return species
  end

  -- The selected form's own art, resolved by asking the engine's own lookup
  -- for the FORM's record -- which reuses its path cache and its Unown
  -- special case rather than reimplementing either.  Falls back to the base
  -- species whenever the form has no art of its own, so a form this mod
  -- registered without a picture shows its base rather than a blank box.
  local originalPicFor = PokedexMenu.picFor
  function PokedexMenu:picFor(species)
    local shown = shownSpecies(self, species)
    if shown ~= species then
      local ok, image = pcall(originalPicFor, self, shown)
      if ok and image then return image end
    end
    return originalPicFor(self, species)
  end

  -- ------- the sprite mod's art on Gold's dex
  --
  -- Cached per menu instance and per species, image and all: Gold reuses one
  -- menu for every entry the player opens, and this is asked once per frame
  -- per drawn pic.  `false` is a remembered MISS -- a species the neighbour
  -- has nothing for must not be re-asked (and re-file-checked) every frame.
  local function modArt(self, species)
    if type(resolveArt) ~= "function" then return nil end
    local cache = self.nationalDexArt
    if not cache then cache = {} self.nationalDexArt = cache end
    local hit = cache[species]
    if hit == nil then
      hit = false
      local ok, path, trueColor = pcall(resolveArt, self.pokemon, species,
        self.game and self.game.data)
      if ok and type(path) == "string" and path ~= "" then
        -- love.graphics.newImage rather than Assets.image: Assets keys its
        -- cache by a path it resolves under the engine's own asset roots, and
        -- this one is absolute and inside another mod's directory.
        local loaded, image = pcall(love.graphics.newImage, path)
        if loaded and image then
          hit = { image = image, trueColor = trueColor and true or false }
        end
      end
      cache[species] = hit
    end
    return hit or nil
  end

  -- The 7x7 tile block Pokedex_PlaceFrontpicTopLeftCorner lays for the pic,
  -- in pixels (PokedexMenu.lua:436-452).
  local PIC_BOX = 7 * 8

  -- Run `body` with no shader bound, restoring whatever was bound before.
  --
  -- This is the palette bypass and the reason this whole draw is reimplemented
  -- rather than delegated.  Gold's drawPic wraps the pic in
  -- GbcPalette.with(colors, body) UNCONDITIONALLY (PokedexMenu.lua:480-484),
  -- and that shader is a shade substitution: it recovers a 0..3 shade index
  -- from the red channel and replaces it with one of four palette entries, so
  -- full-colour art comes back wearing two colours -- a full-colour Totodile
  -- rendered red.  The battle screen already has the opt-out this screen
  -- lacks (src/ui/gen2/BattleState.lua:631 skips the wrap for trueColor art);
  -- this is that same opt-out, on the one screen that never got one.
  --
  -- Captured and restored rather than merely cleared, exactly as
  -- GbcPalette.with does: a caller further up may have one bound.
  local function unshaded(body)
    local G = love.graphics
    local previous = G.getShader and G.getShader() or nil
    if G.setShader then G.setShader() end
    local ok, err = pcall(body)
    if G.setShader then G.setShader(previous) end
    if not ok then error(err, 0) end
  end

  -- Gold's own drawPic, for one image it cannot resolve itself.  The blank
  -- square is kept because the art is fitted INSIDE the block rather than
  -- filling it, and that fill (PokedexMenu.lua:470-472) is what puts a solid
  -- colour behind the pic instead of the panel; the palette it reads is
  -- picked the same way for the same reason (:459-467) -- the listing draws
  -- every mon through the question-mark palette, the entry screen through the
  -- species' own two colours.
  local function drawModPic(self, row, art, tx, ty, ownColors)
    local G = love.graphics
    local colors
    if ownColors then
      colors = self.palettes and Palettes.monColors(self.palettes, row.species)
    else
      colors = self.gfx and self.gfx.questionMarkPalette
    end
    -- The backdrop follows the same rule as the draw below: palette art keeps
    -- the cart's coloured square, full-colour art does not.  That square is
    -- lifted from the palette's own lightest entry, which behind a two-shade
    -- ROM pic reads as the pic's background and behind a full-colour sprite
    -- reads as a coloured card it has been placed on -- Totodile on a green
    -- tile.  Black instead, which is what the rest of the list panel already
    -- is, so the art sits on the panel rather than on a swatch.
    if art.trueColor then
      G.setColor(0, 0, 0, 1)
    else
      local blank = colors and GbcPalette.color(colors, 1) or { 255, 255, 255 }
      G.setColor(blank[1] / 255, blank[2] / 255, blank[3] / 255, 1)
    end
    G.rectangle("fill", tx * 8, ty * 8, PIC_BOX, PIC_BOX)

    local image = art.image
    local w, h = image:getWidth(), image:getHeight()
    if not (w and h and w > 0 and h > 0) then return end
    -- Fitted to the block, never enlarged.  The cart's own pics are 5x5, 6x6
    -- or 7x7 tiles and PadFrontpic centres them; a sprite set's are whatever
    -- the art dump ships (96px is ordinary), and the engine's answer to that
    -- -- battle_sprite_scales -- is a BATTLE registry keyed to a battle box,
    -- not to this one.  So the box itself decides: at 1:1 a 96px pic would
    -- cover the No./name/height/weight column beside it.
    local scale = math.min(PIC_BOX / w, PIC_BOX / h, 1)
    -- Centred both ways.  The cart's own pics stand on the block's bottom edge
    -- (PIC_PAD pads a 5x5 pic downward) so that a small mon shares a ground
    -- line with a big one, and this followed that at first -- but a sprite
    -- set's art is not drawn to that convention: it arrives already trimmed to
    -- its own bounds at whatever aspect the dump ships, so bottom-pinning it
    -- leaves a wide, short sprite sitting on the floor with all the empty
    -- space above it.  Centring is the honest fit for art whose framing this
    -- mod does not control.  Only ever applied here, to art this mod supplied;
    -- Gold's own pics never reach this function.
    local x = tx * 8 + math.floor((PIC_BOX - w * scale) / 2)
    local y = ty * 8 + math.floor((PIC_BOX - h * scale) / 2)
    G.setColor(1, 1, 1, 1)
    local function body() G.draw(image, x, y, 0, scale, scale) end
    -- A four-shade NATIVE set is art the palette is RIGHT for, and it comes
    -- through this same seam, so the flag decides rather than the source.
    if art.trueColor or not (colors and GbcPalette.available()) then
      unshaded(body)
    else
      GbcPalette.with(colors, body)
    end
  end

  local originalDrawPic = PokedexMenu.drawPic
  function PokedexMenu:drawPic(row, tx, ty, ownColors)
    -- An unseen species is the question mark, never a mon's art -- the dex
    -- must not leak what the player has not met.
    local art = row and row.seen
      and modArt(self, shownSpecies(self, row.species)) or nil
    if not art then return originalDrawPic(self, row, tx, ty, ownColors) end
    -- A failure here falls back to the cart's own pic rather than leaving the
    -- block empty: this is an optional integration and the screen behind it
    -- works without it.
    if pcall(drawModPic, self, row, art, tx, ty, ownColors) then return end
    originalDrawPic(self, row, tx, ty, ownColors)
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

setmetatable(M, { __call = function(_, generation, buildFormList, resolveArt)
  return M.install(generation, buildFormList, resolveArt)
end })

return M

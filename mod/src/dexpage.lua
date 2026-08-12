-- Pokédex STATS page and alternate-form browsing, patched onto the engine's
-- DexEntryMenu in memory.  game/src/ui/DexEntryMenu.lua is the engine's own
-- file and is never edited -- src/compat_monpic.lua and src/backoffset.lua
-- (the sprite mod) are the established pattern for this: the class is a
-- plain table, so replacing a few of its fields is an in-memory patch for
-- the life of the process, and an engine running without this mod is
-- untouched.
--
-- Page 1 is the engine's own entry page and stays exactly as it was: same
-- renderer (DexEntryMenu.render), same layout, same data.  Page 2 is new --
-- DOWN from page 1 reaches it, UP returns -- and shows the record's type(s)
-- next to its base stats, with the same sprite kept on screen so the art and
-- the numbers read together.  LEFT/RIGHT on *either* page cycles the
-- species' alternate forms (base first, then whatever this mod's own
-- national-dex data registered with a matching baseSpecies), which swaps
-- the sprite/types/stats -- name, kind, No., height/weight and the
-- description stay the base species' own throughout, exactly like the real
-- games never re-describe MEGA CHARIZARD X as its own dex entry.
--
-- A form's `dex` field is a synthetic id (build_national_dex.py's
-- FORM_DEX_BASE, 20000+) invented purely so a form can register without
-- colliding with its base species in PokedexMenu's byDex lookup -- it is
-- NEVER a real dex number and must never reach the screen.  Nothing here
-- reads it: self.def (what page 1's No. is drawn from) stays pinned to the
-- base species record for as long as the page is open, so that constraint
-- holds by construction rather than by a check that has to remember to fire.
--
-- The pure logic below (buildFormList / statRows) has no love/engine
-- dependency and no closure over `mod`, so tests/national_dex_test.lua loads
-- this file directly and exercises both without a running game.

local M = {}

-- ------------------------------------------------------------- pure logic

-- The ordered list LEFT/RIGHT cycles through for the species anchored at
-- `baseId`: the base species id first, then every record in `pokemon` whose
-- baseSpecies matches, sorted by id.  Sorted rather than left in whatever
-- order a `pairs` walk produces, because `pairs` over a hash part makes no
-- promise at all -- without a stable sort the LEFT/RIGHT order (and thus
-- what a saved key-press muscle memory lands on) could reshuffle between
-- one session and the next with nothing in the save file having changed.
function M.buildFormList(pokemon, baseId)
  local list = { baseId }
  if type(pokemon) ~= "table" or baseId == nil then return list end
  local forms = {}
  for id, record in pairs(pokemon) do
    if type(record) == "table" and record.baseSpecies == baseId then
      forms[#forms + 1] = id
    end
  end
  table.sort(forms)
  for _, id in ipairs(forms) do list[#list + 1] = id end
  return list
end

local function num(v) return type(v) == "number" and v or 0 end

-- The one place that decides whether a species/form record carries this
-- mod's Sp.Atk/Sp.Def split, and what the two values are.  statRows below
-- goes through here rather than reading record.spAttack/record.spDefense
-- itself, and so does the party summary's stats box
-- (src/summarystats.lua, wired to this exact function by main.lua) -- one
-- lookup shared by both screens means they cannot end up disagreeing about
-- which records have the split.
function M.splitStats(record)
  if type(record) == "table"
    and type(record.spAttack) == "number"
    and type(record.spDefense) == "number" then
    return record.spAttack, record.spDefense
  end
  return nil, nil
end

-- Ordered { label, value } stat rows for `record` under the mod's STATS
-- option ("gen1" | "modern"), TOTAL appended last and equal to the sum of
-- the rows actually shown.
--
-- "modern" needs BOTH spAttack and spDefense on the record to mean anything
-- -- a species/form the split never reached (any record from a source other
-- than this mod's build tool, or one built before the split existed)
-- degrades to the gen1 collapsed-SPC rows instead of printing a blank
-- number or throwing on a nil arithmetic operand.
function M.statRows(record, statsMode)
  local base = (type(record) == "table" and record.baseStats) or {}
  local spAttack, spDefense = M.splitStats(record)
  local split = statsMode == "modern" and spAttack ~= nil and spDefense ~= nil
  local rows
  if split then
    -- Speed last, so the two Special rows sit together and read as the pair
    -- they are.  Kept identical to the party summary's split layout
    -- (src/summarystats.lua) on purpose: the two screens show the same stats
    -- for the same mon, and a reader comparing them should not have to
    -- re-find a row that moved.  The gen1 rows below keep the ROM's own
    -- order, which is not ours to rearrange.
    rows = {
      { "HP", num(base.hp) }, { "ATK", num(base.attack) },
      { "DEF", num(base.defense) }, { "SP.A", num(spAttack) },
      { "SP.D", num(spDefense) }, { "SPD", num(base.speed) },
    }
  else
    rows = {
      { "HP", num(base.hp) }, { "ATK", num(base.attack) },
      { "DEF", num(base.defense) }, { "SPD", num(base.speed) },
      { "SPC", num(base.special) },
    }
  end
  local total = 0
  for _, row in ipairs(rows) do total = total + row[2] end
  rows[#rows + 1] = { "TOTAL", total }
  return rows
end

-- "MEGA_X" -> "MEGA X".  build_national_dex.py's `form` field is the raw
-- PokeAPI slug suffix (underscored, upper-cased); this is display-only.
-- Which species id to ask a sprite set for, and which form spelling(s) to
-- ask under, for `record`.  Returns lookupId, form, altForm -- altForm being
-- the underscore-squashed spelling older sets were built with (MEGAX for
-- MEGA_X), or nil when squashing changes nothing.  Pure so the ordering can
-- be asserted without a running game; see loadArt for why the alternate
-- exists at all.
function M.formCandidates(record, speciesId)
  if type(record) ~= "table" or type(record.baseSpecies) ~= "string"
    or type(record.form) ~= "string" then
    return speciesId, nil, nil
  end
  local squashed = record.form:gsub("_", "")
  if squashed == record.form then return record.baseSpecies, record.form, nil end
  return record.baseSpecies, record.form, squashed
end

local function prettyForm(form)
  return (form or ""):gsub("_", " ")
end

-- ------------------------------------------------------------ engine patch

-- Every module this needs is required once here, guarded exactly the way
-- compat_monpic.lua probes BattleState: a missing or reshaped module means
-- this feature quietly does not install rather than taking the mod load
-- down, and none of these calls happen at the top of the file, so a
-- headless test that only wants buildFormList/statRows never touches love
-- or src.* at all.
local function requireAll()
  local names = {
    "src.ui.DexEntryMenu", "src.render.Font", "src.core.Strings",
    "src.pokemon.Sprites", "src.battle.TypeChart", "src.render.PaletteFX",
  }
  local mods = {}
  for _, name in ipairs(names) do
    local ok, value = pcall(require, name)
    if not ok or type(value) ~= "table" then return nil end
    mods[name] = value
  end
  return mods
end

-- `generation` is the booting game (1 unless Gold said otherwise); it gates
-- the neighbour seam at the bottom of this function and nothing else, because
-- Gold's #DEX is its own class under its own screen id and never builds the
-- one this file patches.  nil means Gen 1, the same assumption main.lua makes
-- when it could not ask.
function M.install(mod, generation)
  local mods = requireAll()
  if not mods then return false end
  local DexEntryMenu = mods["src.ui.DexEntryMenu"]
  local Font = mods["src.render.Font"]
  local Strings = mods["src.core.Strings"]
  local Sprites = mods["src.pokemon.Sprites"]
  local TypeChart = mods["src.battle.TypeChart"]
  local PaletteFX = mods["src.render.PaletteFX"]
  if type(DexEntryMenu.new) ~= "function"
    or type(DexEntryMenu.draw) ~= "function"
    or type(DexEntryMenu.update) ~= "function" then
    return false
  end

  -- Resolve a form's own art through the same seam battle art uses, so the
  -- sprite mod's per-form art (or its fallback to the engine's own) applies
  -- here unchanged -- this page never picks an image path itself.
  -- A FORM must be asked for as "base species, wearing form X" -- never by
  -- its own compound id.  A sprite set keys form art at entry.forms[FORM]
  -- underneath the BASE species (universal_sprites' Registry:registerForm),
  -- so a lookup for CHARIZARD_MEGA_X matches no entry at all and falls
  -- through to this mod's placeholder, while CHARIZARD carrying form=MEGA_X
  -- finds art that is already built and sitting on disk.
  --
  -- ctx.mon.form is the engine's own route for saying so: Sprites.path
  -- forwards opts.mon to the hook untouched, and the registry reads
  -- ctx.form or ctx.mon.form when it walks its precedence steps.  Passing a
  -- one-field stand-in rather than a real mon is safe -- every other reader
  -- of ctx.mon guards its own field access.
  --
  -- Asking under the base species also improves the MISS case: a form with
  -- no art of its own now falls back to its base species' artwork, which is
  -- always present, instead of the "?" placeholder.  Mega Charizard X with
  -- no mega art shows a Charizard, which is the right answer.
  local function askArt(game, lookupId, form)
    local ok, path, trueColor = pcall(Sprites.path, game.data, lookupId,
      "front", { kind = "dex", mon = form and { form = form } or nil })
    if not ok then return nil, false end
    return path, trueColor and true or false
  end

  -- Sets built before the form ids settled carry their keys with the
  -- underscores squashed out -- MEGAX for MEGA_X, POMPOM for POM_POM,
  -- GALARZEN for GALAR_ZEN -- because the build tool derived them from
  -- filenames that omit the hyphen, and the registry's key cleaner
  -- uppercases and replaces punctuation but never INSERTS an underscore.
  -- The two spellings can therefore never meet, and the miss is SILENT: the
  -- lookup just falls through to the base species' own art, so Mega
  -- Charizard X quietly shows an ordinary Charizard.  Measured against the
  -- installed sets: 5 forms in gen5ani and 14 in gen5, including both
  -- Charizard and both Mewtwo megas -- the first things anyone checks.
  --
  -- A form miss is detectable rather than guessed at: it returns exactly
  -- what the base species alone returns.  When that happens, try the
  -- squashed spelling before giving up.
  local function loadArt(game, speciesId, record)
    local lookupId, form, altForm = M.formCandidates(record, speciesId)
    local path, trueColor = askArt(game, lookupId, form)
    if altForm then
      local basePath = askArt(game, lookupId, nil)
      if path == basePath then
        local altPath, altTrue = askArt(game, lookupId, altForm)
        if altPath and altPath ~= basePath then
          path, trueColor = altPath, altTrue
        end
      end
    end
    if not path then return nil, false end
    local ok2, img = pcall(love.graphics.newImage, path)
    if not ok2 or not img then return nil, false end
    return img, trueColor and true or false
  end

  -- Point `self` at forms[index]: swaps the sprite, types and stats to that
  -- entry's, and (for a non-base form) records its label.  Index 1 is
  -- always the base species and reuses the art the original constructor
  -- already loaded rather than resolving it a second time.
  local function applyForm(self, index)
    self.formIndex = index
    local id = self.forms[index]
    self.formId = id
    if id == self.baseSpeciesId then
      self.sprite = self.baseSprite
      self.spriteTrueColor = self.baseSpriteTrueColor
      self.formRecord = self.def
      self.formLabel = nil
      return
    end
    local pokemon = self.game.data and self.game.data.pokemon
    local record = pokemon and pokemon[id]
    -- A form id that no longer resolves (another mod's data changed under
    -- us mid-session) falls back to the base record rather than leaving
    -- formRecord nil -- statRows/type drawing both already tolerate a
    -- non-table record, but reusing the base keeps the page showing SOME
    -- real numbers instead of a blank stats column.
    self.formRecord = record or self.def
    self.formLabel = record and record.form or nil
    local sprite, trueColor = loadArt(self.game, id, record)
    self.sprite = sprite or self.baseSprite
    self.spriteTrueColor = sprite and trueColor or self.baseSpriteTrueColor
  end

  -- Is a Pokédex entry the screen being put together, or the screen already
  -- standing?  Both halves are needed and they are different moments: a
  -- replacement screen resolves its pic inside its own constructor, BEFORE
  -- anything is pushed, and again later when the player steps to another
  -- species with the screen already live.  Read by the Sprites.path seam at
  -- the bottom of this function; inert until a neighbour claims the screen.
  local building = false
  local stacked = 0

  local originalNew = DexEntryMenu.new
  function DexEntryMenu.new(game, speciesOrOpts, onDone)
    -- Set before the vanilla constructor rather than after, because a
    -- replacement screen delegates to it and then resolves its own art on
    -- the way back out -- the window has to already be open by then.
    building = true
    local self = originalNew(game, speciesOrOpts, onDone)
    -- Everything below is additive state for page 2 / form browsing.  A
    -- failure here must never take the vanilla page down with it, so it is
    -- entirely inside one pcall; on failure the page behaves exactly like a
    -- species with no forms (page 2 still works, just with nothing to
    -- cycle -- see the #5 constraint on degrading safely).
    local ok = pcall(function()
      if type(self) ~= "table" or type(self.def) ~= "table" then
        error("no species record", 0)
      end
      self.page = 1
      self.baseSpeciesId = self.def.baseSpecies or self.def.id
      self.baseSprite = self.sprite
      self.baseSpriteTrueColor = self.spriteTrueColor
      self.forms = M.buildFormList(game.data and game.data.pokemon,
        self.baseSpeciesId)
      applyForm(self, 1)
    end)
    if not ok and type(self) == "table" then
      self.page = self.page or 1
      self.forms = self.forms or {}
      self.formIndex = self.formIndex or 1
    end
    return self
  end

  -- DOWN/UP switch pages, LEFT/RIGHT cycle forms.  The engine's own A/B
  -- pop-the-stack handling must run completely untouched -- originalUpdate
  -- is called directly, unguarded, so a reshaped engine update still pops
  -- exactly like it always has even if everything below it fails.
  local originalUpdate = DexEntryMenu.update
  function DexEntryMenu:update(dt)
    local wasA, wasB = false, false
    pcall(function()
      local input = self.game.input
      wasA, wasB = input:wasPressed("a"), input:wasPressed("b")
    end)
    originalUpdate(self, dt)
    if wasA or wasB then return end
    pcall(function()
      local input = self.game.input
      if self.page == 1 and input:wasPressed("down") then
        self.page = 2
      elseif self.page == 2 and input:wasPressed("up") then
        self.page = 1
      end
      local forms = self.forms
      if forms and #forms > 1 then
        local n = #forms
        if input:wasPressed("left") then
          applyForm(self, ((self.formIndex - 2) % n) + 1)
        elseif input:wasPressed("right") then
          applyForm(self, (self.formIndex % n) + 1)
        end
      end
    end)
  end

  -- Small "<"/">" hint, only when there is anywhere to cycle to, plus the
  -- selected form's own label -- never shown for the base entry, which
  -- must look exactly like it did before this mod existed.
  local function drawFormChrome(self)
    love.graphics.setColor(0, 0, 0, 1)
    if self.forms and #self.forms > 1 then
      Font.draw("<", 0, 0)
      Font.draw(">", 152, 0)
    end
    if self.formLabel then
      Font.draw(prettyForm(self.formLabel), 16, 0)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- Page 2: sprite kept in the same spot page 1 draws it, TYPE1/TYPE2 in
  -- the space page 1 gives its description text, BASE STATS where page 1
  -- puts name/kind/No/HT/WT.  Reads self.formRecord (falling back to
  -- self.def), never self.def directly, so a selected form's own types and
  -- stats show even though self.def itself never moves off the base
  -- species (see the file banner on why that has to stay true).
  local function drawStatsPage(self)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    local sprite = self.sprite
    if sprite then
      local y = math.max(0, 60 - sprite:getHeight())
      love.graphics.draw(sprite, 8, y)
      if self.spriteTrueColor then
        PaletteFX.markTrueColor(8, y, sprite:getDimensions())
      end
    end
    love.graphics.setColor(0, 0, 0, 1)
    local record = self.formRecord or self.def
    local types = (type(record) == "table" and record.types) or {}
    local ty = 72
    if types[1] then
      Font.draw(Strings("TYPE1/"), 8, ty)
      Font.draw(TypeChart.displayName(types[1]), 8, ty + 10)
      ty = ty + 20
    end
    if types[2] then
      Font.draw(Strings("TYPE2/"), 8, ty)
      Font.draw(TypeChart.displayName(types[2]), 8, ty + 10)
    end
    Font.draw(Strings("BASE STATS"), 72, 8)
    local rows = M.statRows(record, mod.options:get("stats"))
    local ry = 20
    for _, row in ipairs(rows) do
      Font.draw(Strings(row[1]), 72, ry)
      local text = tostring(row[2])
      Font.draw(text, 152 - Font.width(text), ry)
      ry = ry + 10
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  local originalDraw = DexEntryMenu.draw
  function DexEntryMenu:draw()
    -- drawStatsPage failing for any reason (a shape this file did not
    -- anticipate, an image call throwing) falls back to the vanilla page
    -- rather than a broken one -- originalDraw fills the whole canvas
    -- white as its first act, so it cleanly covers whatever a half-drawn
    -- page 2 left behind.
    if self.page == 2 and pcall(drawStatsPage, self) then
      pcall(drawFormChrome, self)
      return
    end
    originalDraw(self)
    pcall(drawFormChrome, self)
  end

  -- ------------------------------------------- when a neighbour owns the page
  --
  -- Screens.resolve prefers the screens registry over src/ui/DexEntryMenu, so
  -- a mod that REGISTERS "DexEntryMenu" replaces the stacked screen outright
  -- instead of patching it.  Such a screen still builds a real DexEntryMenu
  -- underneath and delegates to it -- so everything above still runs -- but it
  -- draws its own pages and reads its own input, which means the STATS page
  -- and form browsing above are bypassed for as long as it is installed.
  -- That is its screen to own and nothing here fights it for the stack.
  --
  -- The PIC is a different matter, because neither side can see the whole of
  -- it.  A replacement screen resolves its own art and is free to ask under
  -- whatever ctx.kind it likes -- one shipped mod asks under "battle" so that
  -- battle-art hooks apply to its page.  A sprite mod grants full-colour art
  -- its opt-out from the four-shade SGB pass per KIND, keyed on a whitelist of
  -- still-image screens that has "dex" on it and deliberately not "battle" --
  -- withholding it there is what stops a voxel battle mod's billboard
  -- alternating shaded and unshaded frame to frame.  Put together, the entry
  -- asked for its pic under the one kind that is refused, and drew 96px colour
  -- art crushed to four shades on every open.  Both neighbours are right about
  -- the thing they can see; this mod is the one that can see both.
  --
  -- So correct the CONTEXT rather than the art: while a Pokédex entry is being
  -- built or is on the stack, a pic lookup is a dex lookup whoever asks for it
  -- and whatever they name it.  Relabelling in Sprites.path puts the answer
  -- ahead of every pokemon.sprite hook, so it does not matter which mod
  -- wrapped that hook first or whether one is installed at all.
  --
  -- Deliberately not a wider grant and not a kind blacklist: outside the
  -- window every lookup keeps exactly the answer it had before, and a kind
  -- nobody has invented yet is covered by where it is asked from rather than
  -- by a list somebody has to remember to extend.
  --
  -- Gen 1 only.  Gold's #DEX is its own class under its own screen id, builds
  -- this one never, and must not gain a seam it cannot use.
  if generation ~= 2 then
    local neighbourOwnsEntry = false

    local function dexWindow()
      return neighbourOwnsEntry and (building or stacked > 0)
    end

    -- Asked after every mod has registered and the screens registry has been
    -- merged into data.screens, so the answer does not depend on load order.
    -- A registry hit means some mod replaced the screen; the builtin is the
    -- require fallback and never appears there.
    mod.events:on("mods.loaded", function(payload)
      local screens = payload and payload.data and payload.data.screens
      neighbourOwnsEntry = screens ~= nil and screens.DexEntryMenu ~= nil
      if not neighbourOwnsEntry then return end
      mod.log:info("another mod owns the Pokédex entry screen -- its pages "
        .. "replace this mod's STATS page and form browsing; species data and "
        .. "dex art still come from here")
    end)

    -- screen.pushed/popped carry the state with the id Screens.build stamped
    -- on it, so this counts a neighbour's screen exactly as it counts the
    -- builtin.  The build window closes on the NEXT push whatever that push
    -- is: a construction that never reaches the stack (a screen that threw and
    -- degraded) must not leave the window propped open behind it.
    mod.events:on("screen.pushed", function(payload)
      local state = payload and payload.state
      if state and state.screenId == "DexEntryMenu" then
        stacked = stacked + 1
      end
      building = false
    end)
    mod.events:on("screen.popped", function(payload)
      local state = payload and payload.state
      if state and state.screenId == "DexEntryMenu" then
        stacked = math.max(0, stacked - 1)
      end
      building = false
    end)

    local function alreadyDex(opts)
      return type(opts) == "table" and opts.kind == "dex"
    end

    local originalPath = Sprites.path
    function Sprites.path(data, species, side, opts)
      if dexWindow() and not alreadyDex(opts) then
        -- a copy, never a write into the caller's table: a screen that keeps
        -- one options table around would otherwise be silently retyped for
        -- every lookup it ever makes, including the ones after it closes
        local relabelled = { kind = "dex" }
        if type(opts) == "table" then
          for key, value in pairs(opts) do relabelled[key] = value end
          relabelled.kind = "dex"
        end
        opts = relabelled
      end
      return originalPath(data, species, side, opts)
    end
  end

  -- :sgbPalettes is deliberately left untouched: it keys its zone off
  -- self.def.id, and self.def stays the base species for the page's whole
  -- lifetime by design (see the file banner) -- reusing that same read
  -- automatically keeps working with no code of ours in the path at all,
  -- for a display mode (Super Game Boy) narrow enough that duplicating the
  -- engine's own palette lookup here would only be one more place for the
  -- two to drift apart.

  return true
end

setmetatable(M, { __call = function(_, mod, generation)
  return M.install(mod, generation)
end })

return M

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

  -- Anchor the form list on whatever species `self.def` currently names, and
  -- select the base entry.  Both the list and the art LEFT/RIGHT falls back
  -- to are species-specific, so this has to run again every time something
  -- moves `self.def` -- a list left over from the previous species would
  -- cycle to the forms of a mon that is no longer on the page.
  local function captureForms(self)
    self.baseSpeciesId = self.def.baseSpecies or self.def.id
    self.baseSprite = self.sprite
    self.baseSpriteTrueColor = self.spriteTrueColor
    self.forms = M.buildFormList(self.game and self.game.data
      and self.game.data.pokemon, self.baseSpeciesId)
    applyForm(self, 1)
  end

  -- One LEFT/RIGHT step through self.forms, wrapping at both ends.  Returns
  -- true only when the selection actually moved, so a caller with its own
  -- per-form state to repair can tell a press apart from a quiet frame.
  local function cycleForms(self, input)
    local forms = self.forms
    if not forms or #forms < 2 then return false end
    local n = #forms
    if input:wasPressed("left") then
      applyForm(self, ((self.formIndex - 2) % n) + 1)
      return true
    elseif input:wasPressed("right") then
      applyForm(self, (self.formIndex % n) + 1)
      return true
    end
    return false
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
      captureForms(self)
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
      cycleForms(self, input)
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
  -- above is bypassed for as long as it is installed.  That is its screen to
  -- own and nothing here fights it for the stack.  Form browsing is a
  -- different case and comes back on keys the neighbour leaves free; see
  -- "borrowing LEFT/RIGHT back" below.
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

    -- ------------------------------------------ borrowing LEFT/RIGHT back
    --
    -- The pages are the neighbour's and stay the neighbour's, but the two
    -- directions form browsing needs are not in use.  useful_dex 1.3.0 reads
    -- exactly four buttons on the entry -- B pops, A cycles data/movelist,
    -- UP/DOWN page the movelist or step the seen species -- so LEFT and RIGHT
    -- can carry forms again without taking a key off a feature that has one.
    -- Rebinding a key a neighbour already used would be trading its feature
    -- for ours, which is not a trade this mod gets to make.
    --
    -- The instance is augmented, never the class and never the files: the
    -- registered factory is wrapped in memory for one boot, and everything
    -- below is written onto the object that wrap returns.  Registering the id
    -- a second time is not an alternative -- screens are a record registry
    -- and a duplicate register raises (src/mods/Registry.lua).
    -- ------------------------------- the numbers on the neighbour's page
    --
    -- Selecting a form has to move what the page PRINTS, not just its art.
    -- The neighbour draws its stat rows out of a table it built once for the
    -- species (useful_dex 1.3.0 caches it in setSpecies and prints it, total
    -- included, straight from the cache), and it reads its type rows off its
    -- own `def`.  Neither moves when LEFT/RIGHT selects a form, so both are
    -- substituted for the length of one draw call and restored immediately
    -- after -- see the draw wrap below for why that window is so tight.
    --
    -- Row key -> the field it comes from on a record's baseStats.  Only the
    -- five a Gen 1 page prints are listed, deliberately: an unrecognised key
    -- means the page is printing a number whose form value this cannot know,
    -- and the whole substitution is declined rather than applied to the rows
    -- it does recognise.  A column where some numbers moved to the form and
    -- the rest stayed the base species' would be a worse lie than a column
    -- where none of them moved.
    local STAT_FIELD = {
      HP = "hp", ATK = "attack", DEF = "defense",
      SPD = "speed", SPC = "special",
    }

    local statsDeclined = false
    local function declineStats()
      if statsDeclined then return end
      statsDeclined = true
      mod.log:info("the Pokédex entry screen another mod owns prints stat "
        .. "rows this mod cannot map onto a form -- its art and label still "
        .. "cycle, the numbers beside them stay the base species'")
    end

    -- `record`'s stats in the shape the neighbour built for the base species,
    -- or nil when that shape is not one this can move.  The rows keep the
    -- neighbour's own keys and order -- this is its page and its layout, and
    -- the STATS option's split rows are not ours to impose on it -- and every
    -- other field of its table is carried across untouched, since it may be
    -- read somewhere this cannot see.  The total is recomputed from the rows
    -- actually substituted rather than copied, or it would still be the base
    -- species' sum sitting under the form's numbers.
    local function formStats(cached, record)
      if type(cached) ~= "table" or type(cached.stats) ~= "table" then
        return nil
      end
      if #cached.stats == 0 then return nil end
      local base = record.baseStats
      if type(base) ~= "table" then return nil end
      local rows, total = {}, 0
      for i, row in ipairs(cached.stats) do
        if type(row) ~= "table" then return nil end
        local field = STAT_FIELD[row.key]
        local value = field and base[field]
        if type(value) ~= "number" then return nil end
        rows[i] = { key = row.key, value = value }
        total = total + value
      end
      local swapped = {}
      for key, value in pairs(cached) do swapped[key] = value end
      swapped.stats, swapped.bst = rows, total
      return swapped
    end

    -- A stand-in record for the same one draw: the base species' own fields
    -- with the types replaced, never the form record itself.  Name, kind,
    -- HT/WT, the owned lookup and above all the No. are read from this same
    -- table, and a form's `dex` is a synthetic key that must never be printed
    -- (see the file banner).  Copying the base rather than pointing at the
    -- form keeps that true by construction instead of by a check.
    local function formDef(baseDef, record)
      local swapped = {}
      for key, value in pairs(baseDef) do swapped[key] = value end
      if type(record.types) == "table" then swapped.types = record.types end
      return swapped
    end

    local function augmentable(screen)
      return type(screen) == "table"
        and type(screen.update) == "function"
        and type(screen.draw) == "function"
        and type(screen.vanilla) == "table"
        and type(screen.vanilla.def) == "table"
        and type(screen.vanilla.forms) == "table"
    end

    local function augment(screen)
      local delegate = screen.vanilla

      -- Re-anchor on the art the NEIGHBOUR resolved rather than on what the
      -- vanilla constructor loaded: a replacement screen looks the pic up a
      -- second time on the way out of its own constructor and writes the
      -- result onto the delegate, so the sprite captured during construction
      -- is already stale.  Cycling back to the base form has to land on the
      -- image the player was actually looking at, not on an earlier one.
      local function reanchor() pcall(captureForms, delegate) end
      reanchor()

      -- Stepping the seen species moves the delegate's def and sprite
      -- wholesale, and the form list anchored on the old species has to go
      -- with it.  Wrapped on the instance, so the neighbour's class keeps
      -- the method it shipped with for any other screen sharing it.
      if type(screen.setSpecies) == "function" then
        local originalSetSpecies = screen.setSpecies
        screen.setSpecies = function(s, ...)
          originalSetSpecies(s, ...)
          reanchor()
        end
      end

      local originalUpdate = screen.update
      screen.update = function(s, dt)
        originalUpdate(s, dt)
        pcall(function()
          -- Only over the page that shows a pic.  The movelist is built for
          -- one species and cycling underneath it would swap art nobody can
          -- see while leaving the rows describing the entry before.
          if s.view == "moves" then return end
          if not cycleForms(delegate, s.game.input) then return end
          -- A neighbour may be driving an ANIMATED base sprite, rewriting
          -- the delegate's sprite from another mod's frame files as it goes.
          -- Left running it would paint over a selected form frame by frame,
          -- so it is parked while one is shown and rebuilt by the
          -- neighbour's own code on the way back to the base entry.
          if delegate.formIndex ~= 1 then
            s.crystalAnimation = nil
          elseif type(s.setupCrystalAnimation) == "function" then
            pcall(s.setupCrystalAnimation, s)
          end
        end)
      end

      -- What the selected form's page needs, memoised.  The key is the
      -- identity of everything it was derived from, so it is rebuilt after a
      -- cycle AND after the neighbour rebuilds its own table for another
      -- species, while an unchanged frame costs one comparison.  Invalidating
      -- from the update wrap instead would have to guess at every route that
      -- can move the neighbour's state; this cannot go stale.
      local view, viewFrom = nil, nil

      local function substitution(s)
        local record = delegate.formRecord
        if delegate.formIndex == 1 or type(record) ~= "table" then return nil end
        if rawequal(record, delegate.def) then return nil end
        if type(s.stats) ~= "table" or type(s.def) ~= "table" then return nil end
        if view and rawequal(viewFrom.record, record)
          and rawequal(viewFrom.stats, s.stats)
          and rawequal(viewFrom.def, s.def) then
          return view
        end
        local stats = formStats(s.stats, record)
        if not stats then
          declineStats()
          return nil
        end
        view = { stats = stats, def = formDef(s.def, record) }
        viewFrom = { record = record, stats = s.stats, def = s.def }
        return view
      end

      local originalDraw = screen.draw
      screen.draw = function(s)
        local savedStats, savedDef = s.stats, s.def
        local swapped = false
        -- The movelist page is built for one species and prints no stats, so
        -- there is nothing there for a form to move: it draws untouched.
        if s.view ~= "moves" then
          local ok, substituted = pcall(substitution, s)
          if ok and substituted then
            s.stats, s.def = substituted.stats, substituted.def
            swapped = true
          end
        end
        local ok, err = pcall(originalDraw, s)
        -- Restored before anything else can run, the throwing path included.
        -- A swap left standing would not merely mis-draw one frame: the
        -- neighbour's own cached table would be gone and its `def` would be a
        -- stand-in, so every species the player stepped to afterwards would
        -- be captioned with one form's numbers.
        if swapped then s.stats, s.def = savedStats, savedDef end
        if not ok then error(err, 0) end
        if s.view ~= "moves" then pcall(drawFormChrome, delegate) end
      end
    end

    -- Swap `.new` on the record in place rather than putting a fresh table
    -- into data.screens: Screens.resolve caches the record TABLE and reads
    -- `.new` off it at every build, so an in-place swap takes effect whether
    -- or not something already resolved this id, while a replacement table
    -- would be ignored by an already-warmed cache.  A bare function is a
    -- legal record too (src/ui/Screens.lua resolve), and that one has no
    -- field to swap, so it is boxed instead.
    -- Whether form browsing actually came back cannot be known at load: the
    -- registry holds a factory, and only the screen it builds says whether
    -- there is anything to hang forms off.  So the load-time line reports the
    -- part that is already settled -- the STATS page is the neighbour's now --
    -- and the first entry the player opens reports the rest, once, whichever
    -- way it went.
    local announced = false
    local function announce(message)
      if announced then return end
      announced = true
      mod.log:info(message)
    end

    local function wrapEntryFactory(screens)
      local record = screens.DexEntryMenu
      local originalNew
      if type(record) == "table" and type(record.new) == "function" then
        originalNew = record.new
      elseif type(record) == "function" then
        originalNew = record
      else
        return false
      end
      local function wrapped(...)
        local screen = originalNew(...)
        -- A factory that throws is degraded to the builtin screen
        -- (src/ui/Screens.lua build), which would drop the neighbour's whole
        -- feature set on the floor.  Nothing added here may be the reason
        -- that happens, so the augmentation is guarded end to end.
        if augmentable(screen) then
          pcall(augment, screen)
          announce("form browsing is back on LEFT/RIGHT over the Pokédex "
            .. "entry screen another mod owns -- the two directions it reads "
            .. "nowhere itself")
        else
          announce("the Pokédex entry screen another mod supplies is not "
            .. "shaped to carry form browsing -- leaving it as it is")
        end
        return screen
      end
      if type(record) == "table" then
        record.new = wrapped
      else
        screens.DexEntryMenu = { new = wrapped }
      end
      return true
    end

    -- Asked after every mod has registered and the screens registry has been
    -- merged into data.screens, so the answer does not depend on load order.
    -- A registry hit means some mod replaced the screen; the builtin is the
    -- require fallback and never appears there.  It is also the one moment
    -- the factory can be wrapped: every registration is in, and nothing has
    -- opened a Pokédex yet.
    mod.events:on("mods.loaded", function(payload)
      local screens = payload and payload.data and payload.data.screens
      neighbourOwnsEntry = screens ~= nil and screens.DexEntryMenu ~= nil
      if not neighbourOwnsEntry then return end
      mod.log:info("another mod owns the Pokédex entry screen -- its pages "
        .. "replace this mod's STATS page; species data and dex art still "
        .. "come from here")
      local ok, wrapped = pcall(wrapEntryFactory, screens)
      if not (ok and wrapped) then
        announce("that mod supplies no entry factory this one can extend -- "
          .. "form browsing stays off while it is installed")
      end
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

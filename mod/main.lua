-- National dex mod: registers the 1025-species national dex (PokeAPI-derived
-- data built by tools/build_national_dex.py) and the modern type chart its
-- typing needs, entirely through the engine's content registries.
--
-- Data-only mod: no hooks, no engine seam.  Every registration is guarded
-- individually (src/nationaldex.lua), so one bad record can never fail the
-- load.  The generated files are the mod's payload, so they ship with it
-- (they are text data, not artwork).

local function loadSibling(mod, name)
  local source = mod:read(name)
  assert(source, "missing required module: " .. name)
  local chunk, err = load(source, "@" .. mod.path .. "/" .. name)
  assert(chunk, err)
  return chunk()
end

local function loadOptionalSibling(mod, name)
  local source = mod:read(name)
  if not source then return nil end
  local chunk, err = load(source, "@" .. mod.path .. "/" .. name)
  assert(chunk, err)
  return chunk()
end

return function(mod)
  mod.options:define({
    { key = "national_dex", label = "NATIONAL DEX", type = "choice",
      default = "off", choices = { { "OFF", "off" }, { "ON", "on" } } },
    { key = "type_chart", label = "TYPE CHART", type = "choice",
      default = "gen1", choices = { { "GEN 1", "gen1" }, { "MODERN", "modern" } } },
    -- DISPLAY ONLY -- mirrors TYPE_CHART's shape but gates nothing here.
    -- Every species/form record already carries BOTH the collapsed Gen 1
    -- `baseStats.special` the engine's battle math reads (unchanged,
    -- non-negotiable) AND the raw spAttack/spDefense split (see
    -- src/nationaldex.lua's docs and dev/reports/forms_inventory.txt for
    -- the split's provenance).  This option exists so a future dex UI page
    -- can ask mod.options:get("stats") to decide whether to SHOW one
    -- Special number or two -- it must never be read anywhere that feeds
    -- a registered record or battle math.  Do not wire it into
    -- src/nationaldex.lua's registration path.
    { key = "stats", label = "STATS", type = "choice",
      default = "gen1", choices = { { "GEN 1", "gen1" }, { "MODERN", "modern" } } },
  })

  local nationalDex = mod.options:get("national_dex") == "on"
  local chart = loadOptionalSibling(mod, "data/species/generated/type_chart_modern.lua")
  local national = nationalDex
    and loadOptionalSibling(mod, "data/species/generated/national.lua") or nil
  if (mod.options:get("type_chart") == "modern" or nationalDex) and chart then
    -- src/gen2shape.lua answers which generation is booting and reshapes a
    -- record for it.  Handed in rather than required from nationaldex.lua
    -- because a mod's own files load as chunks through mod:read, not through
    -- package.path -- require() cannot see a sibling of this mod.
    local gen2shape = loadSibling(mod, "src/gen2shape.lua")
    loadSibling(mod, "src/nationaldex.lua")(mod, chart, national, gen2shape)
  end

  -- mod.exports: the integration surface for another mod (a Showdown-style
  -- battle engine is the known first consumer) that wants the real
  -- Sp.Atk/Sp.Def split without re-parsing our generated files or
  -- re-fetching PokeAPI itself.  Read-only, always present regardless of
  -- the NATIONAL DEX/TYPE CHART/STATS options above -- it just answers nil
  -- for any species this mod never touched or that failed to register.
  mod.exports.hasSplitStats = true
  -- speciesId: any engine pokemon id, base species or alternate form
  -- (e.g. "CHARIZARD" or "CHARIZARD_MEGA_X").  Returns
  -- { spAttack = n, spDefense = n } or nil.  Guarded to keep working
  -- whichever way the split data ended up attached to the record (extra
  -- top-level fields, the route this build actually took -- see
  -- dev/reports/forms_inventory.txt -- or, if a future schema change ever
  -- forces it, a sidecar table this function would fall back to reading).
  mod.exports.splitStats = function(speciesId)
    local record = mod.content.pokemon:get(speciesId)
    if type(record) == "table"
      and type(record.spAttack) == "number"
      and type(record.spDefense) == "number" then
      return { spAttack = record.spAttack, spDefense = record.spDefense }
    end
    return nil
  end

  -- STATS page (DOWN from the entry page) and LEFT/RIGHT alternate-form
  -- browsing, patched onto the engine's DexEntryMenu in memory (never onto
  -- disk -- see src/dexpage.lua).  Unconditional: it reads whatever species
  -- record the player already opened, national-dex species and the ROM's
  -- own 151 alike, and simply has nothing to cycle through when a species
  -- has no forms registered.  Captured (rather than the usual
  -- loadSibling(...)(mod) one-liner) so its splitStats lookup can be
  -- handed to the party summary patch below -- one shared helper, not a
  -- second copy of the same field reads.
  local Dexpage = loadSibling(mod, "src/dexpage.lua")
  Dexpage(mod)

  -- Party summary stats box (src/summarystats.lua): same treatment as the
  -- dex page, and unconditional for the same reason -- it reads whatever
  -- mon the player already opened the STATUS screen for.  Passed
  -- Dexpage.splitStats directly so the two screens can never disagree
  -- about which records carry the Sp.Atk/Sp.Def split.
  loadSibling(mod, "src/summarystats.lua")(mod, Dexpage.splitStats)

  -- The cross-mod read API (src/api.lua): statsByDex / statsBySpecies /
  -- listSpecies / formsOf, published on mod.exports for any other loaded mod
  -- to call in process.  Installed LAST so the two screens above are already
  -- wired if this ever fails, and unconditionally -- a consumer asking this
  -- mod what it knows should get an answer regardless of which display
  -- options the player happens to have set.
  loadSibling(mod, "src/api.lua")(mod)
end

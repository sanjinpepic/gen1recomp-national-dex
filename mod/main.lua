-- National dex mod: registers the 1025-species national dex (PokeAPI-derived
-- data built by tools/build_national_dex.py) and the modern type chart its
-- typing needs, entirely through the engine's content registries.
--
-- Mostly data: every registration is guarded individually
-- (src/nationaldex.lua), so one bad record can never fail the load.  Two
-- engine seams on top of that, both in-memory patches over Gen 1 menu classes
-- and both optional -- src/dexpage.lua and src/summarystats.lua, which is what
-- the manifest's engine_internals permission is for.  The generated files are
-- the mod's payload, so they ship with it (they are text data, not artwork).

-- A sibling that fails to read or compile returns nil rather than raising.
-- An assert inside a mod callback takes the whole load down with it, and every
-- caller below can degrade to something a player can still use -- so the
-- failure is reported with the file that broke and what would fix it, and the
-- load carries on.  The loader prefixes [national_dex] already.
local function compileSibling(mod, name, source)
  local chunk, err = load(source, "@" .. mod.path .. "/" .. name)
  if not chunk then
    mod.log:error("%s failed to compile (%s) -- reinstall the mod zip; a "
      .. "partial extract is the usual cause", name, tostring(err))
    return nil
  end
  local ok, result = pcall(chunk)
  if not ok then
    mod.log:error("%s errored while loading (%s) -- reinstall the mod zip",
      name, tostring(result))
    return nil
  end
  return result
end

local function loadSibling(mod, name)
  local source = mod:read(name)
  if not source then
    mod.log:error("%s is missing -- reinstall the mod zip; the features it "
      .. "provides are skipped", name)
    return nil
  end
  return compileSibling(mod, name, source)
end

local function loadOptionalSibling(mod, name)
  local source = mod:read(name)
  if not source then return nil end
  return compileSibling(mod, name, source)
end

return function(mod)
  mod.options:define({
    { key = "national_dex", label = "NATIONAL DEX", type = "choice",
      default = "off", choices = { { "OFF", "off" }, { "ON", "on" } } },
    -- Which ERA's effectiveness chart to play with, not merely whether to
    -- add the three modern types.  Each of the three ships as its own
    -- generated table and is applied so it WINS over whatever the cart
    -- supplied; picking the era the running game already is costs nothing
    -- and changes nothing.
    { key = "type_chart", label = "TYPE CHART", type = "choice",
      default = "gen1", choices = { { "GEN 1", "gen1" }, { "GEN 2", "gen2" },
                                    { "MODERN", "modern" } } },
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

  -- src/gen2shape.lua answers which generation is booting and reshapes a
  -- record for it.  Handed in rather than required from nationaldex.lua
  -- because a mod's own files load as chunks through mod:read, not through
  -- package.path -- require() cannot see a sibling of this mod.
  local gen2shape = loadSibling(mod, "src/gen2shape.lua")
  -- Assume Gen 1 when it could not be loaded: that is what every build before
  -- Gold did, and it is the shape the Red/Blue/Yellow records already have.
  -- Guessing 2 here would reshape records for a schema that is not running.
  local generation = gen2shape and gen2shape.generation(mod) or 1

  -- The era the cart already plays by.  Applying that same era over the top
  -- would register a few hundred rows to say what the game already says, so
  -- it is skipped -- EXCEPT with the national dex on, which needs all 18
  -- type records to exist whatever the multipliers between them are, or
  -- every species past #151 carries a type the chart cannot resolve and
  -- fails to register at all.
  local ERAS = { gen1 = true, gen2 = true, modern = true }
  local era = mod.options:get("type_chart")
  if not ERAS[era] then era = "gen1" end
  local nativeEra = generation == 2 and "gen2" or "gen1"
  local chart = (nationalDex or era ~= nativeEra)
    and loadOptionalSibling(mod,
      "data/species/generated/type_chart_" .. era .. ".lua") or nil

  local national = nationalDex
    and loadOptionalSibling(mod, "data/species/generated/national.lua") or nil
  if chart then
    local register = loadSibling(mod, "src/nationaldex.lua")
    -- gen2shape may be nil and nationaldex.lua reads that as "assume Gen 1";
    -- without the registration module there is nothing to run at all, and the
    -- cart's own species stay exactly as it supplied them.
    if register then
      register(mod, chart, national, gen2shape, generation, era)
    end
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
  if Dexpage then Dexpage(mod) end

  -- Party summary stats box (src/summarystats.lua): same treatment as the
  -- dex page, and unconditional for the same reason -- it reads whatever
  -- mon the player already opened the STATUS screen for.  Passed
  -- Dexpage.splitStats directly so the two screens can never disagree
  -- about which records carry the Sp.Atk/Sp.Def split.
  local Summary = loadSibling(mod, "src/summarystats.lua")
  if Summary then Summary(mod, Dexpage and Dexpage.splitStats) end

  -- The cross-mod read API (src/api.lua): statsByDex / statsBySpecies /
  -- listSpecies / formsOf, published on mod.exports for any other loaded mod
  -- to call in process.  Installed LAST so the two screens above are already
  -- wired if this ever fails, and unconditionally -- a consumer asking this
  -- mod what it knows should get an answer regardless of which display
  -- options the player happens to have set.
  local Api = loadSibling(mod, "src/api.lua")
  -- hasSplitStats/splitStats above are published whatever happens here, so a
  -- consumer that only wants the split still gets an answer.
  if Api then Api(mod) end
end

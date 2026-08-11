# Using the National Dex API

This mod publishes a read-only API that any other Gen1Recomp mod can call to get
species data: stats, typing, learnsets, evolutions, alternate forms and more, for
all 1025 species plus 326 alternate forms.

It works the same way on Red, Blue, Yellow and Pokémon Gold — see
[Reading a reply on Gold](#reading-a-reply-on-gold) below for the one place a
reply's shape actually differs between them.

**Nothing is hosted.** There is no server, no port and no network call. The API
is a plain Lua table the engine hands to other mods in the same process. The only
requirement is that a player has this mod installed and enabled.

---

## Getting a handle

```lua
local dex = mod:find("national_dex")
if not dex then
  -- The player does not have this mod. Carry on without it.
  return
end

if (dex.exports.apiVersion or 0) < 1 then
  -- Older build than this code expects.
  return
end
```

`mod:find` returns `{ id, version, exports }`, or `nil` when the mod is absent,
disabled, or failed to load. **Always handle `nil`** — a mod that hard-errors
because an optional dependency is missing is a mod that breaks someone's game.

Check `apiVersion` with `>=`, never `==`. It rises only when an existing field
changes meaning or disappears; new fields are added without bumping it.

---

## The calls

### `statsByDex(number)`

Everything about the species holding that national dex number, with its
alternate forms nested underneath.

```lua
local zard = dex.exports.statsByDex(6)
zard.name          --> "Charizard"
zard.stats.attack  --> 84
zard.types         --> { "FIRE", "FLYING" }
#zard.forms        --> 3   (Mega X, Mega Y, Gigantamax)
```

Returns `nil` for a number no species claims.

### `statsBySpecies(id)`

The same reply, addressed by species id — the only way to reach an alternate
form directly.

```lua
local megaY = dex.exports.statsBySpecies("CHARIZARD_MEGA_Y")
megaY.form      --> "MEGA_Y"
megaY.baseDex   --> 6
```

### `listSpecies()`

The directory: every dex number with its name and form ids, ascending. Use it to
build a menu or resolve a name without asking for full records one at a time.

```lua
for _, row in ipairs(dex.exports.listSpecies()) do
  -- row.dex, row.id, row.name, row.forms (count), row.formIds (list)
end
```

### `formsOf(idOrDex)`

Just one species' alternate forms, by id or dex number. Returns an empty list —
never `nil` — for a species with none.

### `splitStats(id)`

A narrow helper predating the rest: `{ spAttack, spDefense }` or `nil`. Prefer
`statsBySpecies(id).stats`, which carries the same numbers alongside everything
else.

---

## What a reply contains

The reply is the species record in full, plus a normalised view on top. Rather
than a fixed list this mod curates, it is everything the data carries — so
fields added later reach you without this API being changed to let them through.

| field | meaning |
| --- | --- |
| `id` | species id, e.g. `"CHARIZARD"`, `"CHARIZARD_MEGA_Y"` |
| `dex` | the record's own dex number — **see the warning below for forms** |
| `baseDex` | the number to DISPLAY. For a form, its base species' number |
| `name` | display name |
| `types` | `{ "FIRE", "FLYING" }` |
| `stats` | see below |
| `hasSplit` | whether the Sp.Atk/Sp.Def split is real for this record |
| `total` | sum of the stats actually present |
| `baseStats` | the raw stat block, untouched — shape follows the schema: `special` on Red/Blue/Yellow, `specialAttack`/`specialDefense` on Gold |
| `learnset` | level-up moves **filtered to moves this engine knows** (Red/Blue/Yellow; Gold has one `levelMoves` table instead — see [Reading a reply on Gold](#reading-a-reply-on-gold)) |
| `level1Moves` | starting moveset, same filtering (Red/Blue/Yellow only, same note as `learnset`) |
| `evolutions` | evolution data — target species key is `species` on Red/Blue/Yellow, `into` on Gold |
| `growthRate` | engine growth-rate id |
| `catchRate`, `baseExp` | as the engine reads them |
| `dexEntry` | `kind`, height, weight, and the id of its description text |
| `form`, `baseSpecies` | present only on an alternate form |
| `forms` | nested form records, present only on a base species |

### Stats

```lua
reply.stats = {
  hp, attack, defense, speed,
  special,             -- the ROM's single collapsed stat
  spAttack, spDefense, -- the real Gen 6 split (only when hasSplit)
}
```

`special` is what this engine's damage maths actually reads on Red, Blue and
Yellow, and is reported unchanged — on Gold it is always `nil` instead, for
reasons covered in [Reading a reply on Gold](#reading-a-reply-on-gold) below.
`spAttack`/`spDefense` are the true modern split, present wherever this mod
supplies them, on both games. `hasSplit` tells you which of the two worlds
you are in rather than making you infer it from a `nil`.

### Extended data

Records also carry the complete modern data, well beyond what this engine can
execute — the point is that it is there for you to build on:

| field | meaning |
| --- | --- |
| `movesFull` | the COMPLETE level-up learnset, unfiltered |
| `movesByMethod` | `machine` (TM/HM), `egg`, `tutor`, `other` |
| `abilities` | `{ name, slot, hidden }` — a form's own, not its base's |
| `evYield` | EV yield per stat |
| `eggGroups`, `baseHappiness`, `genderRate`, `growthRateName` | as PokeAPI reports them |

Move entries look like this:

```lua
{ level = 4, move = "PLAYNICE", name = "Play Nice", slug = "play-nice" }
```

`move` follows the id convention used by the Showdown-derived battle engine
work: the display name uppercased with every non-alphanumeric character removed,
except where this engine already knows the move, in which case the engine's own
spelling wins (`THUNDER_SHOCK`, not `THUNDERSHOCK`). `name` and `slug` are
carried alongside so you can reconcile against any other naming scheme rather
than being stuck with ours.

Most of these moves have no implementation in this engine. That is expected and
intended: the data is complete so that a battle engine built on top of it does
not have to re-source it.

---

## Reading a reply on Gold

The API itself does not change on Pokémon Gold — same calls, same
`apiVersion`, same deep-copy guarantee. What changes is the shape of the
record underneath, because Gold validates species against Gen1Recomp's Gen 2
schema rather than its Gen 1 one, and a reply is a copy of whatever actually
got registered:

- **`stats.special` is always `nil` on Gold.** The Gen 2 schema has no
  collapsed Special field to begin with — `baseStats` carries
  `specialAttack`/`specialDefense` in place of `special`, so there is nothing
  for the normalised block to read. `spAttack`, `spDefense` and `hasSplit`
  behave exactly as documented above on both games; only `special` (and the
  raw `baseStats.special` it comes from) goes missing. Read the split fields
  instead of `special` and this is invisible.
- **`levelMoves` replaces `learnset` and `level1Moves`.** Gold keeps one
  level-up table instead of two. `movesFull` and `movesByMethod` — the
  unfiltered modern data — are unaffected either way; they never depended on
  which of those shapes the record used.
- **An evolution's target is `into`, not `species`.** `method`, and `level`
  or `item` where they apply, are unchanged.

None of this touches `movesFull`, `movesByMethod`, `abilities`, `evYield`, or
the rest of the extended data above — those are this mod's own fields,
attached the same way regardless of which game is running.

---

## Two things to get right

**Never display a form's `dex`.** A form registers under a synthetic key far
above the real roster (Mega Charizard Y is `30035`) purely so it can exist
without colliding with its base species. It is not a dex number. Use `baseDex`
— Mega Charizard X and Y are both **No. 006**, exactly as in the real games.

**The reply is yours.** Every call returns a deep copy, nested tables included.
Write to it freely; you cannot reach the data this engine reads. The reverse
also holds — hold a reply as long as you like, it will not change under you.

---

## Worked example: a mega evolution

```lua
local dex = mod:find("national_dex")
if not dex or (dex.exports.apiVersion or 0) < 1 then return end

local function megaFormOf(speciesId)
  for _, form in ipairs(dex.exports.formsOf(speciesId)) do
    if form.form and form.form:find("^MEGA") then return form end
  end
end

local mega = megaFormOf("CHARIZARD")
if mega then
  -- mega.stats            the mega's own stats
  -- mega.types            its own typing
  -- mega.abilities        Drought, not Blaze
  -- mega.baseDex          6, the number to show the player
end
```

---

## Data source and credits

Species data is derived from [**PokeAPI**](https://pokeapi.co) — an open,
community-run Pokémon API. Stats, typing, learnsets, abilities, evolutions, egg
groups and EV yields all originate there. Thank you to PokeAPI's maintainers and
contributors for making it freely available.

The type chart and dex text are likewise PokeAPI-derived. This mod ships that
data as generated Lua tables; `tools/build_national_dex.py` is the tool that
produces them, and it can regenerate everything from PokeAPI directly.

Pokémon and Pokémon character names are trademarks of Nintendo, Creatures Inc.
and GAME FREAK Inc. This is an unofficial fan project, not affiliated with or
endorsed by any of them.

# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

## 0.11.0

### Added

- Species past #251 now appear in the Pokedex list on Pokemon Gold. The list
  is widened by patching Gold's own `#DEX` class in memory and handing it a
  private augmented copy of the dex table -- never a write into the cart's
  own table, which the Pokegear shares by reference.
- Alternate-form browsing on Gold's dex entry screen, bound to UP/DOWN.
  LEFT/RIGHT already move that screen's action bar across PAGE/AREA/CRY/PRNT,
  and claiming them would make three of those four unreachable. On Gen 1 the
  binding stays LEFT/RIGHT, where nothing else uses them.

### Fixed

- `dexSize` never reached Gold. The `constants` registry routes to
  `gen2Constants` on a Gen 2 boot, so the patch landed on a key Gold's
  constant schema does not define and merged silently without raising. It
  would not have helped either way: Gold's dex screen never reads `dexSize`,
  which the engine consults at exactly one place -- Gen 1's own menu.

### Notes

- With `NATIONAL DEX` off, nothing is added and Gold keeps its own 251.
- The STATS page and the party summary split-stats box remain Gen 1 only.


## 0.10.1


### Added

- `tests/national_dex_gen2_test.lua`. `manifest.games` claims Gold, and the
  loader gates on that claim, so the suite asserts the mod's *state* rather
  than its error count — a gate skip is deliberately not an error, and a mod
  that never ran a line reports zero of them. Its own file because the
  engine's builtin registries register once per process.
- `tests/national_dex_test.lua`, which loads the mod through the headless
  loader with the dex switched on and asserts what it registers: the
  1025-species roster, Charizard's megas reporting No. 006 rather than the
  synthetic keys they register under, the DARK row a Gen 1 chart cannot
  express, and the deep-copy guarantee the export API promises callers.
  Writing it turned up that three matchups never take: `content.type_chart`
  `:register` refuses an id the engine registered first, so GHOST>PSYCHIC,
  POISON>BUG and BUG>POISON keep their Gen 1 values and the modern chart
  really lands in 321 of its 324 rows. The suite pins them as they behave, so
  correcting the registration will fail it and name what moved.
- `mod.card` carries the full sharing schema — tags, the `differences`
  tri-ledger, credit to PokeAPI for the species data, and a `compat` range.

### Changed

- `mod.card.author` names `sanjinpepic`. 0.8.0 shipped the card under a
  different handle, and the author is what the manager and the showcase both
  surface.
- `manifest.category` is now `CONTENT`. `GAMEPLAY` is a grandfathered alias
  for `TWEAK`, which means small data edits; a mod that registers 1025
  species and 326 forms was being filed, sorted and searched as a numbers
  tweak in both the gallery and the manager.
- The load tally goes through `mod.log` instead of `print`, so it carries the
  `[national_dex]` prefix and reaches the launcher's log pane — where a player
  is sent when a mod misbehaves, and where a bare `print` never arrives. The
  skipped count now gets its own `warn` line naming the first cause, because a
  record the schema refused is a species the player will not find.
- A missing or broken sibling module is reported and skipped rather than
  asserted. `assert` inside a mod callback takes the whole load down with it;
  each of the five call sites can degrade to something still usable, so they
  do, and the message names the file and what reinstalling would fix.
- `manifest.github` points at the release repo, which is what the launcher's
  auto-update and *Other versions* panes read.

### Fixed

- The header comment claimed "no hooks, no engine seam" while `src/dexpage.lua`
  and `src/summarystats.lua` patch two menu classes in memory — which is what
  the manifest's `engine_internals` permission is for.

## 0.10.0

### Added

- `TYPE CHART` offers `GEN 1`, `GEN 2` and `MODERN`, each a generated table
  derived from PokeAPI's own per-generation damage relations rather than typed
  out by hand. They differ exactly where the real games do: Gen 1 to Gen 2
  moves Ghost/Psychic 0x to 2x, Bug/Poison 2x to 0.5x, Poison/Bug 2x to 1x and
  Ice/Fire 1x to 0.5x; Gen 2 to modern only lifts Steel's resistance to Ghost
  and Dark.

### Fixed

- The chart you pick is now the chart you play. Rows were registered with
  `:register`, which throws on an id the engine has already claimed, and every
  throw was swallowed by the same guard that stops one bad record failing the
  load. Since the engine registers its own chart first, every matchup between
  two types the cart already knew kept its original multiplier — under MODERN,
  Ghost against Psychic stayed at Gen 1's 0x rather than 2x, and only the ~99
  rows touching DARK, STEEL or FAIRY ever took. Rows now claim an existing id
  with `:override`, taking applied matchups from 318 of 324 to all 324.
- Choosing the era the cart already is costs nothing — it is skipped — except
  with the national dex on, where all 18 type records must exist regardless or
  every species past #151 carries a type the chart cannot resolve.

## 0.9.0

### Added

- Gold. The dex now loads on Pokémon Gold as well as Red, Blue and Yellow,
  and `manifest.games` says so. Gold is not Gen 1 spelled differently: the
  engine validates the same `pokemon` registry against a second schema there,
  one that splits `baseStats.special` into `specialAttack`/`specialDefense`,
  folds `level1Moves` into `levelMoves`, renames `frontSize` to `picSize` and
  points an evolution at `into` rather than `species`. A Gen 1 record offered
  to that schema fails on the missing `special`, and because every
  registration here is guarded, the mod would have loaded on Gold with no
  species and no complaint. `src/gen2shape.lua` reshapes each record first.

### Changed

- Gold's cart describes #1–251 itself, and registering an id the ROM import
  already holds throws rather than being skipped, so those species receive
  their modern typing as patches instead — deliberately without their base
  stats, which on Gen 2 are live battle numbers the engine reads directly and
  replacing them would quietly rebalance a playthrough. A Gold boot patches
  251 and registers 1,100 where a Red boot patches 151 and registers 1,200.
- Which game is running is read from the `generation` constant the ROM import
  stamps, never from a version allow-list.
- The Pokédex STATS page and the party summary box do not install on Gold,
  whose screens are different classes entirely. They detect that and stand
  down, so the dex data, the type chart and the read API all work there while
  those two displays wait for a Gen 2 equivalent.

## 0.8.0

### Added

- Species 1–1025: names, dex entries, typing, base stats, level-up
  learnsets, evolutions, growth rates and catch rates.
- The modern 18-type chart — 324 matchups, and the DARK, STEEL and FAIRY
  types a national-dex roster cannot be typed without.
- 326 alternate forms (megas, gigantamax, regional variants) nested inside
  their base species. Mega Charizard X and Y are both No. 006, as in the
  real games, rather than taking dex rows of their own.
- Sp.Atk and Sp.Def carried alongside the ROM's single collapsed Special
  stat rather than replacing it, so the engine's damage maths is untouched.
- A Pokédex STATS page with left/right form browsing, and the same split on
  the party summary screen.
- `apiVersion`, `statsByDex`, `statsBySpecies`, `listSpecies`, `formsOf`,
  `splitStats` and `hasSplitStats` on `mod.exports`, for mods built on this
  data — a battle engine being the first expected consumer.
- `NATIONAL DEX`, `TYPE CHART` and `STATS` options, each defaulting to the
  vanilla behaviour so enabling the mod changes nothing until asked.

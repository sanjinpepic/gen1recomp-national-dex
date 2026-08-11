# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

## Unreleased

### Added

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

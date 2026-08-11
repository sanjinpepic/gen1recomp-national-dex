# National Dex

A Pokédex backend for [Gen1Recomp](https://github.com/ChrisMcElroy/gen1recomp):
all 1025 species with modern typing, the 18-type chart, 326 alternate forms, and
a read API other mods can call for the data.

**Data and code only. No Pokémon artwork ships here** — see
[Assets](#assets) below.

## What it does

- **Species 1–1025.** Names, dex entries, typing, base stats, level-up
  learnsets, evolutions, growth and catch rates.
- **The modern 18-type chart**, with 324 matchups. DARK, STEEL and FAIRY cannot
  exist on a Gen 1 chart, and national-dex typing needs them.
- **326 alternate forms** — megas, gigantamax, regional variants — as forms
  *inside* their base species' entry, never as separate dex rows. Mega Charizard
  X and Y are both No. 006, exactly as in the real games.
- **Split Sp.Atk / Sp.Def**, carried alongside the ROM's single collapsed
  Special stat rather than replacing it. The engine's damage maths is untouched.
- **A Pokédex STATS page** with left/right form browsing, and a party summary
  that shows the split when you want it.
- **A read API for other mods** — see **[INSTRUCTION.md](INSTRUCTION.md)**.

## For mod developers

If you are building on this — a battle engine, a mega evolution mod, a team
builder — start with **[INSTRUCTION.md](INSTRUCTION.md)**. In short:

```lua
local dex = mod:find("national_dex")
if dex and (dex.exports.apiVersion or 0) >= 1 then
  local charizard = dex.exports.statsByDex(6)
  local megaY     = dex.exports.statsBySpecies("CHARIZARD_MEGA_Y")
end
```

Nothing is hosted. It is a plain Lua table in the same process, and every reply
is a deep copy you can freely write to.

Records carry the complete modern data — full unfiltered learnsets, TM/egg/tutor
moves, abilities, EV yields — including everything this engine cannot execute,
so an engine built on top does not have to re-source any of it.

## Installing

Download the `.zip` from [Releases](../../releases) and import it through the
launcher: **MODS → Import mod .zip**.

Then enable it and set its options:

- `NATIONAL DEX: ON`
- `TYPE CHART: MODERN` — required for beyond-151 typing to make sense
- `STATS: GEN 1 | MODERN` — display only; MODERN splits Special into Sp.Atk and
  Sp.Def on the dex and party screens

## Assets

**This repository contains no Pokémon artwork, and never will.** Sprites are not
ours to redistribute. The only images here are two 922-byte flat-grey `?`
placeholders we generated, which exist because the engine throws when a species'
art file is missing.

Species art comes from the player's own copy. The companion
[Universal Sprite Registry](https://github.com/sanjinpepic) mod resolves art from
a local dump you supply yourself. Without it, beyond-151 species show the
placeholder — the dex, stats, forms and API all work regardless.

## What is in here

`mod/` is the mod itself, exactly as it ships — the Lua source and the generated
species data. The `.zip` at the root is that same folder packaged for the
launcher's importer. Nothing else: no build scripts, no tests, no examples.

## Credits

Species data is derived from [**PokeAPI**](https://pokeapi.co), an open,
community-run Pokémon API. Stats, typing, learnsets, abilities, evolutions, egg
groups and EV yields all originate there. Thank you to its maintainers and
contributors for making it freely available.

Built for [Gen1Recomp](https://github.com/ChrisMcElroy/gen1recomp), a LÖVE2D
recompilation of Pokémon Red.

## Licence

[MIT](LICENSE) — use it, change it, ship it, commercially or otherwise. Keep the
copyright notice.

The MIT licence covers **this project's own code and generated data files**. It
does not and cannot grant rights to Pokémon itself. Pokémon and Pokémon character
names are trademarks of Nintendo, Creatures Inc. and GAME FREAK Inc. This is an
unofficial fan project, not affiliated with or endorsed by any of them.

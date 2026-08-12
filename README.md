# National Dex

A Pokédex backend for [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp), on
Red, Blue, Yellow and Pokémon Gold: all 1025 species with modern typing, the
18-type chart, 326 alternate forms, and a read API other mods can call for the
data.

**Data and code only. No Pokémon artwork ships here** — see
[Assets](#assets) below.

## What it does

- **Species 1–1025.** Names, dex entries, typing, base stats, level-up
  learnsets, evolutions, growth and catch rates. Gold's own cart already
  describes #1–251, so those receive modern typing as a patch instead of a
  fresh registration — deliberately without new base stats, since on Gen 2
  those are live battle numbers the engine reads directly, and overwriting
  them would silently rebalance a playthrough already in progress. Species
  #252 onward, and every alternate form, register in full on both games.
- **A GEN 1 / GEN 2 / MODERN type chart**, 324 matchups each, derived from
  PokeAPI's per-generation damage relations. The era you pick wins over the
  cart's own chart, so under MODERN Ghost really is 2x on Psychic. DARK,
  STEEL and FAIRY cannot exist on a Gen 1 chart, and national-dex typing
  needs them.
- **326 alternate forms** — megas, gigantamax, regional variants — as forms
  *inside* their base species' entry, never as separate dex rows. Mega Charizard
  X and Y are both No. 006, exactly as in the real games.
- **Split Sp.Atk / Sp.Def**, carried alongside whatever Special stat the cart's
  own battle math already reads — Red, Blue and Yellow's single collapsed
  value, Gold's own native split — rather than replacing it. The engine's
  damage maths is untouched either way.
- **A Pokédex STATS page** with LEFT/RIGHT form browsing, and a party summary
  that shows the split when you want it — **Red, Blue and Yellow only.** Gold
  shows SPCL.ATK and SPCL.DEF natively, so it needs neither.
- **Every ability a species can have**, on both dex screens — not just the
  first. The label is plural on purpose: slots 1 and 2 are alternatives, so an
  individual has one of them, and a singular label over three rows would say
  something untrue. The hidden ability is marked in the margin and always
  listed last.
- **A page strip under every dex entry** — DOWN walks from the entry through
  STATS, the evolution line and the full movelist by section, and LEFT/RIGHT
  keep cycling forms on every page, each one showing that form's own data. A
  section with nothing in it produces no page at all. The evolution page is a
  single page for all 341 chains: the line indented by stage, the species
  you're looking at marked, and the evolution trigger beside each name as a
  short token — `L16`, `LEAF`, `TRADE` — with a trailing `?` where the method
  carries a condition the token doesn't name. On the Gen 1 listing, START
  cycles between numerical, A-Z and seen-only, naming both the mode and the
  key on the title row.
- **Holding UP/DOWN accelerates** on either game's list, on one shared clock.
  Gold used to run faster to make up for having no page jumps; now that it has
  them, both games scroll at the same tiers.
- **On Gold specifically**: the dex lists every species past #251, with
  LEFT/RIGHT page jumps (seven rows a step) and alternate forms browsing on
  UP/DOWN. The dex entry's action bar carries a STATS slot and an LVL slot —
  LVL opens a paged view of its own, the evolution line on one page and the
  level-up learnset on the next, switched with UP/DOWN, with LEFT/RIGHT still
  cycling forms and A or B returning to the entry screen. Both the dex and the
  party summary draw the art you picked in the sprite mod rather than the
  cart's own pics. Without that mod, or with it disabled, both screens look
  exactly as they did.
- **All 833 modern moves**, registered with their real name, type, power,
  accuracy and PP. `MOVES: ALL` widens level-up learnsets to the ones this
  engine can execute honestly — 191 on Gen 1, 272 on Gold. A move needing
  state the engine does not have (recharge, charge turns, held items,
  abilities, weather, hazards, screens, spread targeting) is registered but
  never taught: an approximated move is worse than an absent one.
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

Download the `.zip` and import it through the
launcher: **MODS → Import mod .zip**.

Then enable it and set its options:

- `NATIONAL DEX: ON`
- `TYPE CHART: GEN 1 | GEN 2 | MODERN` — the effectiveness era to play by
- `STATS: GEN 1 | MODERN` — display only; MODERN splits Special into Sp.Atk and
  Sp.Def on the dex and party screens. Red, Blue and Yellow only: Gold splits
  Special natively and shows both already, so the option does nothing there
- `MOVES: GEN-NATIVE | ALL` — GEN-NATIVE, the default, leaves learnsets as the
  cart has them. ALL widens them to the modern moves this engine can execute.
  Every move is registered either way, whatever this is set to: the engine
  drops move ids it cannot find when a save loads, so a move that existed only
  under a setting would vanish from your party when you turned it off

## Assets

**This repository contains no Pokémon artwork, and never will.** Sprites are not
ours to redistribute. The only images here are two 922-byte flat-grey `?`
placeholders we generated, which exist because the engine throws when a species'
art file is missing.

Species art comes from the player's own copy. Without it, species beyond the
cart's own roster — 151 on Red, Blue and Yellow, 251 on Gold, which ships its
own Johto sprites — show the placeholder. The dex, stats, forms and API all
work regardless.

## What is in here

`mod/` is exactly what the `.zip` installs — the Lua source, the generated
species, move and evolution data, and the two placeholder art files, all
picked by this project's own packaging tool from an explicit allow-list.
Nothing else ships: no `CHANGELOG.md`, no tests, no build scripts. Those live
in the mod's development tree, which this repository is published from but
does not include.

## Credits

Species data is derived from [**PokeAPI**](https://pokeapi.co), an open,
community-run Pokémon API. Stats, typing, learnsets, abilities, evolutions, egg
groups and EV yields all originate there. Thank you to its maintainers and
contributors for making it freely available.

Built for [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp), a LÖVE2D
recompilation of Pokémon Red.

## Licence

[PolyForm Noncommercial 1.0.0](LICENSE) — free to use, change and share for any
**noncommercial** purpose, personal use included. Commercial use needs a separate
licence from the copyright holder. Keep the copyright notice.

That makes this project source-available rather than *open source* in the Open
Source Initiative's sense of the term, which does not allow a licence to restrict
a field of endeavour. The distinction matters if you are choosing a dependency.

The licence covers **this project's own code and generated data files**. It does
not and cannot grant rights to Pokémon itself. Pokémon and Pokémon character names
are trademarks of Nintendo, Creatures Inc. and GAME FREAK Inc. PokeAPI is its own
entity. This is an unofficial fan project, not affiliated with or endorsed by any
of them.

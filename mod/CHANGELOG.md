# Changelog

Format: [keep a changelog](https://keepachangelog.com/en/1.1.0/).
Version headings match `manifest.json`'s `version`.

## 0.27.3

### Fixed

- **A Pokemon that had ALREADY learned one of those broken moves keeps it broken, and 0.27.2 did nothing about that.** The previous fix stopped new learnset rows naming a move the game cannot resolve; it could not help a Pokemon that learned one first, because a move slot is save data -- `id`, `pp` and `maxPp` are written into the save when the move is learned and nothing re-derives them afterwards. A real Silver save still showed `ROLYCOLY  RAPIDSPIN 0/0` after updating, and a boxed `TOGEPI  SWEETKISS 0/0` beside it. Those slots are now repaired when the save loads: an id the merged move table cannot resolve is matched by its normalised form against the one real move that claims it, rewritten to that id, and given the record's full PP -- full rather than preserved because a broken slot's PP was zero and stayed zero, so there is no spent PP to respect.
- **The repair is deliberately the narrowest thing that can work, because it edits a player's save on load.** A slot whose id already resolves is never touched, whoever registered it -- a move this mod itself supplies is left exactly alone. An id whose normalised form matches nothing is left alone too: it may belong to another mod that has not loaded yet, and a guess would be worse than the 0/0 it replaced. An id whose normalised form matches more than one real move is refused rather than picked between. Party and storage are both walked, in both box shapes, because a broken slot follows the Pokemon into a box and a player who stored theirs before the fix is exactly who this has to reach. Running twice changes nothing the second time.
- **Not a migration, though it looks like one.** `SaveData.runMigrations` only runs a mod's chain when the save carries a `modData` slice for that mod, and this mod writes none -- a real save's `modData` holds one entry and it belongs to another mod. Adding a slice purely to unlock a migration would mean writing to every save that loads in order to fix the few that need it.

## 0.27.2

### Fixed

- **On Gold and Silver, 1388 level-up moves across 869 species arrived at 0/0 PP and could never be used.** A real save had a level 6 ROLYCOLY holding `RAPIDSPIN 0/0` while every other move in the party -- `WATER_GUN`, `QUICK_ATTACK`, `POISON_STING` -- worked fine. The difference is spelling. Gold and Silver register 116 of their 253 move ids with underscores, so the cart owns Rapid Spin as `RAPID_SPIN`; this mod's own payload spells it `RAPIDSPIN`, `normaliseId` strips the punctuation, the two match, and registration is correctly SKIPPED -- the cart's Rapid Spin is a real implementation with the ROM's own animation and index, and overwriting it would be this mod rewriting the base game to say what it already says. That half was right and is unchanged. What was missing is that the learnset shards still said `RAPIDSPIN`, and nothing translated it into the id the game actually holds, so a widened species got a move slot naming a record that does not exist -- which the Gen 2 mon builder reads as `pp = moveDef and moveDef.pp or 0`. `existingIds` now answers WHICH id the cart registered rather than merely that it did, and the widening path maps this mod's spelling onto it before adding the row. The translation happens before the duplicate check, so a species that already knew the cart's spelling does not also gain this mod's -- one move listed twice, one of them dead.
- **Gen 1 was never affected, and the reason is worth recording.** Red owns 165 moves to Gold's 253, and the extra ones are precisely the Gen 2 additions -- Rapid Spin, Scary Face, Giga Drain, Metal Claw, Baton Pass -- that this mod otherwise registers itself. On Red they collide with nothing, every id resolves, and the identical code is silent. The translation table this fix builds is empty there, so nothing about a Gen 1 boot changes.

## 0.27.1

### Fixed

- **Every species this mod adds past #251 was invisible to Pokemon Gold's
  save editor -- not merely absent from its species picker, but never
  reaching `data.pokemon` at all under that boot.** `src/gen2shape.lua`'s
  generation read, `mod.content.constants:get("generation")`, answers
  correctly on a real Gold boot -- `Game2.lua` stamps `data.gen2Constants`
  before any mod loads -- but the save editor's own bootstrap
  (`tools/save-editor/Gen.lua`'s `bindGoldData`) never binds that table; it
  binds `gen2Maps`, `gen2Tilesets`, `gen2Palettes` and a few others, but not
  this one, so the read came back nil there and `gen2shape.generation()`
  fell back to Gen 1. The pokemon registry itself was still built against
  the Gen 2 schema the whole time -- the loader's own generation was
  correct -- so every one of the roughly 1,140 registrations this mod
  attempted arrived Gen 1-shaped against a schema requiring
  `specialAttack`/`specialDefense`, and every one was rejected. Nothing
  crashed and nothing warned visibly: each registration is guarded
  individually so one bad record can never fail the load, and the tally
  line naming the failure goes out through `mod.log`, which reaches a
  `print()` the packaged launcher discards. `gen2shape.lua` now has a
  second signal for when the first comes back empty -- whether an existing,
  ROM-owned species (Bulbasaur) already carries the Gen 2 stat split, which
  survives the editor's gap because Gold's own cart is Gen 2-shaped no
  matter which tables its bootstrap happened to bind. Items and moves were
  never affected, since neither of those registries' schemas differ between
  generations.

## 0.27.0

### Added

- **Six of the sixteen modern moves 0.26.1's own `national_dex_effectmodeled_test.lua`
  found unreachable now have a route.** `tools/build_moves.py` builds a
  general TM pipeline off PokeAPI's own `machine` learn-method bucket, which
  this mod's `extras/` shards already carried for display but nothing ever
  taught from: every `effectModeled = true` move with no level-up route and
  at least one species PokeAPI actually lists as machine-taught gets an
  invented item (TM172 onward, continuing past `battle_forms`'s TM171),
  registered by the new `src/machinemoves.lua` and teaching the move through
  the engine's real machine-item path (`game/src/inventory/ItemEffects.lua`)
  -- the same mechanism `battle_forms`'s TM171 proved for Tera Blast. This
  build closes GRASSYGLIDE, LASHOUT, METEORBEAM, MISTYEXPLOSION, POLTERGEIST
  and SCORCHINGSANDS (TM172-TM177). Every one of these items is BYTELESS on
  purpose: Gen 1's item space is a single byte and this project has three
  real ones left system-wide, but `game/src/inventory/Bag.lua` keys a save's
  inventory by item id rather than by byte, so a byteless TM still buys,
  holds and teaches on this engine's own save and only loses a round trip
  through a real Game Boy `.sav` export, which nothing this pipeline invents
  needs to survive. Sold on the Celadon department store's stone floor,
  gated behind MOVES=ALL like every other learnset widening this mod does,
  so GEN-NATIVE stays exactly as it was. `KNOWN_UNREACHABLE` in the
  effectmodeled test now names the remaining ten instead of sixteen: six are
  tutor-only in PokeAPI's own data (the Let's Go partner Pikachu/Eevee's own
  signature moves) with no engine mechanism to reach them at all -- nothing
  under `game/src` implements a move tutor of any kind -- and four are
  level-up moves this mod's single-canonical-version-group snapshot still
  misses in an older game, a version-group-selection policy question
  reported rather than fixed in this pass.

## 0.26.1

### Fixed

- **A totally untouched install produced 105 load errors on every single
  boot.** `src/moves.lua` registers the full modern move roster
  unconditionally, on purpose -- turning the MOVES option back off must never
  delete an already-learned move off a save, so the ids always have to be
  there. Over a hundred of those moves carry a `type` of DARK, STEEL or
  FAIRY, and the only thing that ever taught the engine those three type ids
  was the NATIONAL DEX/TYPE CHART-gated block those same moves never waited
  for -- with both options left at their defaults (OFF and GEN 1), that block
  never ran, so every DARK/STEEL/FAIRY move registered a `type` nothing had
  registered, and `Schemas.crossValidate` turned each into a hard
  "unresolved reference to type_chart" error, attributed to this mod, listed
  on every mod's own error page in the manager. `main.lua` now registers
  just the three bare type id records (never their matchup rows -- Gen 1
  still decides every multiplier a player's battle actually rolls) whenever
  the modern move roster registers, independently of whether NATIONAL DEX or
  TYPE CHART changed anything else.

### Added

- **Two new test suites pin promises this mod's own code already made in
  words but nothing had checked.** `national_dex_defaults_test.lua` boots
  the real mod against the real engine data with nothing configured -- the
  install a player gets who never opened the settings screen -- and demands
  zero errors, which is the fix above's own regression guard.
  `national_dex_effectmodeled_test.lua` boots it again with MOVES=ALL and
  checks both directions of `src/api.lua`'s own stated policy: a move
  flagged `effectModeled = false` must never reach a real learnset or tmhm
  list, and a move flagged `true` ought to be reachable by one of those two
  routes or explicitly written down as a known gap. Sixteen modern moves
  (`BADDYBAD`, `FLOATYFALL`, `FREEZYFROST`, `GLITZYGLOW`, `GRASSYGLIDE`,
  `HEALORDER`, `HEARTSTAMP`, `LASHOUT`, `METEORBEAM`, `MISTYEXPLOSION`,
  `NEEDLEARM`, `POLTERGEIST`, `SCORCHINGSANDS`, `SPARKLYSWIRL`,
  `SPLISHYSPLASH`, `STEAMROLLER`) turned up unreachable by either route in
  the current data and are now named in the test as a documented gap rather
  than a silent one: each is a move whose source shard carries no
  version-group where any species learns it by level-up, and this mod has no
  modern-TM or tutor/egg-move pipeline to reach it any other way. Not a
  registration bug -- a real hole in what a fresh install can teach -- and
  now it is one a future data rebuild cannot silently widen without the test
  noticing.

## 0.26.0

### Added

- **Genesect's four Drives -- Douse, Shock, Burn and Chill -- are now browsable
  forms of their own.** They were the one alternate-form family this mod had
  no record for at all, Arceus and Silvally's payload-less shape but with a
  twist: fetching the live pokemon-form resource for each Drive shows nothing
  different from base Genesect, not even typing (in the games a Drive changes
  the type of Techno Blast only, a per-move property no dex record can hold).
  So each is derived from Genesect's own record with only its name, dex
  number and form label overridden -- stats, typing, abilities and moveset
  all stay the base's -- registering as `GENESECT_DOUSE`, `GENESECT_SHOCK`,
  `GENESECT_BURN` and `GENESECT_CHILL`.

## 0.25.0

### Added

- **Arceus and Silvally now carry their seventeen type forms, browsable from
  their dex entries like every other form.** They were the two species this
  mod knew only one shape of, because they are the two the data source
  describes without giving any form a record of its own: Charizard's megas
  each arrive as their own stat line and ability list, while Arceus's Plates
  and Silvally's Memories arrive as eighteen names over a single stat block.
  There was nothing for the build tool to read, so it read nothing and
  emitted nothing. Each form is derived from its base species instead --
  which is the only reading the source allows, since the type is the whole
  of the difference it records -- and registers under `ARCEUS_FIRE`,
  `SILVALLY_DRAGON` and their fifteen siblings apiece, sharing the base's
  stats, moves, size and dex text. The Normal form is deliberately absent:
  that is the Pokémon holding nothing, and the base record already is it.
  Dark, Steel and Fairy among them exist only while a type chart carrying
  those three is registered, which this mod does whenever the national dex
  is on. Battle art is looked up by the form's type name, so any set that
  files a picture under that name is found without further wiring.

## 0.24.3

### Fixed

- **A dex entry for a species this mod adds printed its description as one
  line running off the right of the screen, and its height and weight in
  German.** All three are printed only for a species the player OWNS -- a
  seen-only entry says "Data unknown." and nothing else -- so the whole fault
  was invisible until a national-dex species was caught. The entry page draws
  a description one screen row per line break and wraps nothing, because the
  cart's own 151 entries arrive already broken and this mod's prose did not;
  it is broken now as each entry registers, to the nineteen columns the row
  physically holds and the seven rows the page has, with the font's ellipsis
  where a longer entry is cut. Nineteen rather than the eighteen of the
  cart's own widest line: the text starts eight pixels in on a screen a
  hundred and sixty wide, so the last column is there to be used, and using it
  carries seventy-five more entries inside the page. The two numbers beside
  it were unit
  mismatches: `dexEntry.heightM` is how a record tells that page it measures
  in metres, and the page answers with the German GR./GEW. labels and a
  decimal comma, so the metric pair is no longer registered; and `weight` is
  tenths of a pound to the engine while the payload carried whole pounds, so
  every species this mod adds weighed a tenth of what it should -- Groudon
  read 209.4 lb where it should read 2094.4.

## 0.24.1

### Fixed

- **Species and moves this mod adds print in capitals now, the way the cart
  prints its own.** The generated payload spells a name the way its source
  does -- `Chikorita`, `Aqua Jet` -- and the engine draws a record's `name`
  straight onto the dex list, the entry page, the battle HUD and the FIGHT
  menu, so everything from #152 up read as a different game to the 151 beside
  it. The casing is applied as each record is registered rather than written
  into the generated data, which is what makes it reach the screens this mod
  never patches; the dex pages it does own case the move and family names they
  read from their own shards at the point of drawing them. Only `a-z` moves:
  Flabébé and Sirfetch'd keep their accents and their apostrophe, because the
  ROM font has a lowercase é and no capital one, and a character the font
  cannot draw is drawn as a blank rather than refused. A mod matching this
  mod's records on `name` rather than `id` will need the new spelling -- the
  read API reports what the registry holds.

## 0.24.0

### Changed

- **One key opens the search in both games: START, which is Escape on a
  keyboard.** Gold's #DEX has always opened its own search with START, and Gen
  1's opened with SELECT, so the same feature answered to Escape in one game
  and Tab in the other depending on which had booted. Gen 1's listing now
  reads START for the search, and its NUM / A-Z / SEEN view modes moved to
  SELECT -- the tag on the title row names the new key. START closes the
  screen as well as opening it, which is what Gold's cartridge already did.
- Inside the search, SELECT still swaps a term that could be read two ways --
  typing `fly` finds Flygon by name, and SELECT re-reads it as the move. The
  listing and the search are different screens, so the key means one thing on
  each without either having to give way.
- The swap has a second benefit worth naming: nothing binds the listing's
  `onSelectKey` any more. That is the field `useful_dex` uses for its own view
  cycling, so the search now works alongside it whatever else is installed --
  only the view modes stand down. A convenience going quiet next to a
  neighbour is a fair trade; a search that could not be opened would not have
  been.

## 0.23.0

### Changed

- **Gold's search takes a keyboard directly, the way Gen 1's already did.**
  Typing into it used to walk the cursor around the menu instead of entering
  text, leaving the on-screen keyboard as the only way to search on a machine
  that has a real one. The two games reach the keyboard by different roads:
  Gen 1 runs on `Game`, whose `keypressed` offers the open screen first
  refusal before anything becomes a button, while Gold runs on `Game2`, whose
  own does not -- it checks the host hotkeys and goes straight to the button
  map, so a letter arrived as a d-pad press because W, A, S and D are the
  d-pad. Gold's dex now gives an open screen that same first refusal. Only a
  screen that asks for raw keys is affected, and only while it is asking;
  every other key reaches the button map exactly as before. A key is either
  text or handed back, never both, which is what keeps DOWN, A and B working
  while the field has focus.

## 0.22.3

### Fixed

- **Gold's search only covered the first 151 species.** The listing behind it
  held all 1025, but the search described a Kanto-sized dex and quietly found
  nothing past #151. The length has two homes and the search read the wrong
  one: `src/nationaldex.lua` patches the `dexSize` constant, and on a Gen 2
  boot the constants registry is routed to `gen2Constants`, so the value lands
  at `data.gen2Constants.dexSize` while `data.constants.dexSize` is never
  written at all. The lookup missed, a literal 151 answered in its place, and
  no error was raised. This mod's own notes had already recorded that the
  patch "succeeds and means nothing" because nothing read it back -- the
  search is the thing that now reads it.

## 0.22.2

### Fixed

- **The search returned species the player had never seen.** A row with no
  record prints as five dashes, and this mod's own listing already refuses to
  sort those by name because doing so leaks, in position, exactly what the
  dashes withhold -- but the search matched them anyway, so typing `chari`
  confirmed that something beginning with those letters sat at #006, and
  typing `fire` counted the Fire types. Searching now reaches recorded species
  only, which is also what the screen it replaced did: Gold's cartridge search
  reads seen species alone. An empty field still lists everything, dashes
  included, because that is the listing standing still rather than a search.
- The empty field prints NAME OR TYPE rather than nothing. A blank row beside
  a cursor was the one element on the screen that gave no sign of being a text
  field at all. The prompt shows only while the field is genuinely empty, so
  it cannot be mistaken for something already typed.

## 0.22.1

### Fixed

- **Gold's search keyboard could not be closed.** Pressing A on the field
  opened the naming screen and END never dismissed it, stranding the player
  with no way back to the dex. The two games' naming screens disagree about
  who owns the stack: Gen 1's pops itself and then calls back, while Gold's
  `accept` only invokes the callback and never touches the stack, so a caller
  written against Gen 1's contract leaves the keyboard up for ever. The search
  now pops it the way Gold's own name-entry screens do.
- **The search opened on what looked like a broken screen.** With nothing yet
  typed the field was blank, the reading row empty and the result list empty,
  so all a player met was a cursor and the number 0 -- indistinguishable from a
  search that had run and found nothing. An empty query now matches every row,
  so the screen opens on the listing and typing narrows it, which is both what
  a search is and the only state that explains itself.
- Both search screens print a key legend. The screen they replaced named its
  own controls and this one named none, so nothing on it indicated that A
  opened a keyboard or that B left. SELECT is named only while a term actually
  has a second reading, since naming a key that does nothing invites a press
  that changes nothing.

## 0.22.0

### Added

- **A free-text search for both dex listings.** SELECT on Gen 1's dex list
  and START on Gold's now open a field that filters the 1025-row listing
  live as it is typed, against name, type, ability and move. `fire/flying`
  finds species holding both types, `earthquake` finds what learns it,
  `levitate` finds what has it, and `chari` finds Charizard before the name
  is finished. Terms split on `+`, `,` or `/` -- all three, because neither
  game's naming keyboard carries a `+`, and a pad player reaches the field
  through that same keyboard. Ability and move terms are answered by a
  reverse index generated at build time, and a form's abilities and moves
  fold into its base species, so `tough claws` finds Charizard rather than
  only Mega Charizard X.
- A word that means two things is read one way and says so on the row under
  the field; SELECT swaps it to the other reading. `psychic` is both a type
  and a move, and the field has to pick one to filter on -- naming the guess
  it made beats filtering on it silently.

### Changed

- Gold's cartridge type-wheel search is retired. Its two wheels only ever
  expressed what a query like `fire/flying` now says in passing, and one
  field reachable from the same list replaces both.

## 0.21.0

### Added

- Gold's dex entry screen gains a sixth action-bar slot, LVL, opening a paged
  view of its own: page 1 is the evolution line, then the level-up learnset.
  Inside it, UP/DOWN page between the two, LEFT/RIGHT still cycle forms, and
  A or B return to the entry screen; nothing on the entry screen itself was
  rebound. Gold's box gives 14 content rows against Gen 1's 12, so a learnset
  that is one page there can split across as many as four on Gold's own view
  -- Gallade's 33-row list is the worst case; 207 records have a single
  evolution chain and 85 have no level-up moves at all. The evolution mark on
  this view is Gold's own cursor tile rather than a `>` glyph, since Gold's
  charmap has no `>` and an unknown glyph encodes as a space. MACHINE, EGG,
  TUTOR and OTHER are deliberately not included.

### Fixed

- The cart's own `PRNT` label bled into this mod's action-bar row. The cart
  clears only 18 columns and relies on its own 19-cell string to cover the
  last one, so an 18-cell redraw window here left its trailing "T" standing
  beside the row. The redraw now clears the full 19 columns. That narrower
  window is also why the new slot reads LVL rather than LEVEL: the six
  actions show through a four-slot window, and with the sixth slot selected
  `" CRY PRNT STAT LEVEL"` is 20 cells against the console's 19-cell width,
  where `LVL` fits at 18.

### Changed

- `levelUpSection` was split out of `moveSections` in `src/dexpage.lua` so
  Gold's LVL view can ask for the level-up section by name instead of taking
  `moveSections`' first entry, which would have silently handed it the
  MACHINE section for the 85 records with no level-up moves. Gen 1's own
  movelist output is unchanged.


## 0.20.1

### Fixed

- The hidden-ability mark ran into the name it qualifies, so the two read as
  one word: HSNIPER, HSHEER FORCE. A blank cell separates them now. On the
  Gen 1 page the mark moved a cell left into the margin, costing no name a
  character; on Gold column 0 is the box border, so the names moved right
  instead and every name is indented equally, marked or not, to keep the
  column straight.


## 0.20.0

### Added

- Both dex screens list every ability a species can have, not just the first,
  with the hidden one marked and always last. The label is plural on purpose:
  slots 1 and 2 are alternatives, so an individual has one of them, and a
  singular label over three rows would say something untrue.

### Fixed

- Three on-screen markers were invisible. `<` and `>` appear in none of the
  four character maps, and the font encoder turns an unknown glyph into a
  space, so the evolution page's current-species mark and both form-cycling
  arrows had never once reached the screen. They now use the engine's own
  cursor tile. A test sweeps every string these pages draw against the real
  map, since a character silently becoming a space is invisible to any
  assertion that checks strings rather than encoded output.

### Changed

- The evolution pages are one page. The line, the marked species, and the
  trigger beside each name as a short token -- `L16`, `LEAF`, `TRADE` -- so
  all 341 chains still fit a single page where the full sentences split the
  eight-branch families the page exists to show whole. A token followed by
  `?` means the method carries a condition the token does not name.


## 0.19.0

### Added

- The evolution page shows the WHOLE line, indented by stage, with the
  species you are looking at marked. Branches indent under the species that
  produces them, because depth is the only thing that says which one that
  is. Trigger text is deliberately absent from this page: names only means
  every one of the 341 chains fits a single page, where adding the sentences
  splits Eevee -- the family the page exists to show whole.
- Gold's dex list gains LEFT/RIGHT page jumps, seven rows a step, the same
  timing Gen 1 uses. Ends clamp rather than wrap: at six pages a second a
  wrapping jump would cycle the list forever.

### Changed

- Held UP/DOWN is slower again on both games, and Gold now shares Gen 1's
  clock exactly. Gold was quicker because a held direction was its only way
  across 1025 rows; the page jump above removes that reason. A ten-second
  hold on Gold covered 267 rows and now covers 133.


## 0.18.0

### Added

- A strip of pages under each dex entry, walked with DOWN and retraced with
  UP: stats, then evolutions, then the full movelist by section. LEFT/RIGHT
  still cycle forms on every page, and every page shows the selected form's
  own data. A section with nothing in it produces no page at all.
- List views on the Gen 1 listing, cycled with START: numerical, A-Z, and
  seen-only. The mode is named on the title row along with the key, and the
  cursor stays on the same species across a change.
- A STATS entry on Gold's dex action bar, showing base stats, typing and the
  ability. The bar scrolls rather than growing, because five slots do not fit
  a 160px row and an overflowing cell would print outside the console frame.

### Fixed

- Gold's type search never matched PSYCHIC, on the stock cart as much as
  here: the wheel holds a display name and records hold a constant id.
- FAIRY was missing from that wheel, leaving 59 species unfindable by their
  primary type.
- A second search filtered the first one's results instead of the full list,
  with no way back except changing sort mode or closing the dex.

### Changed

- Held UP/DOWN scrolls more slowly. The rate a tier names is also the
  overshoot it costs: a player releases about twelve frames after seeing the
  row go past, which was a dozen rows of backtracking at the old top speed.
- Holding LEFT/RIGHT now repeats the page jump, on its own slower clock so a
  tap cannot double-jump.


## 0.17.0

### Added

- The STATS page shows the species' ability, under the type block on the
  left. It follows the form you are looking at rather than the base species,
  so cycling to Mega Charizard Y reads Drought where Charizard reads Blaze.

### Notes

- One name is shown: the lowest-numbered ordinary ability. Most species also
  have a second and a hidden one, but there is room for one name and none for
  the word that would distinguish them -- printing two under one label would
  claim a slot-2 ability and a hidden ability are the same kind of thing.
  Hidden abilities are skipped rather than ranked last, so a record carrying
  only a hidden one prints nothing instead of promoting an ability no wild
  Pokemon has.
- The line flows with the type block instead of sitting at a fixed row: a
  form can gain a type its base species lacks, and an anchored line would
  leave a gap on one of the two.
- Abilities do not ride on the registered record -- they are read through
  this mod's own published API, the same surface any other mod would use,
  and memoised per species because each call deep-copies a whole record.


## 0.16.0

### Added

- Holding UP or DOWN on the dex list accelerates, on both games. The engine
  already had a held-input counter on its list menu, switched off for the
  dex; it is enabled with tiers on top rather than reimplemented. Gold had
  none at all, so it gained one. A single tap still moves exactly one row,
  and LEFT/RIGHT keep the page jump they already had on Gen 1.
- Evolution data for every species: what it evolves from and into, the
  trigger in readable form, and the whole chain so a page can walk it.
  `evolutionsOf(idOrDex)` and `listEvolutions()` on the read API,
  `API_VERSION` is now 3.

### Notes

- Evolutions are DISPLAY data and are never registered. The engine's
  `evolutions` field takes a method from a fixed vocabulary, and most modern
  triggers -- friendship, held item, time of day, a known move -- have no
  honest id in it. The registered field stays empty, as asserted by tests.
- Branching chains are kept whole: Eevee carries all eight, and Magnezone
  keeps seven distinct location methods with the current one first.
- A regional form with its own line gets its own record -- Galarian Yamask
  evolves into Runerigus and is not folded into Yamask's chain. A form with
  no evolution of its own gets no record rather than an invented one.


## 0.15.0

### Added

- All 833 modern moves are registered, with their real name, type, power,
  accuracy and PP. Registration is unconditional and not tied to the new
  option: `SaveData` strips move ids missing from `data.moves` on load, so a
  move that existed only under a setting would vanish from a player's party
  the moment they turned it off.
- `MOVES: GEN-NATIVE | ALL`. GEN-NATIVE is the default and leaves today's
  level-up learnsets exactly as they were. ALL widens them to the moves this
  engine can execute honestly -- 191 on Gen 1, 272 on Gen 2.
- `moveById` and `listMoves` on the read API, carrying the complete data for
  all 833 including the ones this engine cannot execute, so a battle engine
  built on top does not have to re-source them. `API_VERSION` is now 2.

### Notes

- A move is only learnable if its behaviour is real here. Anything needing
  state the engine lacks -- recharge, charge turns, held items, abilities,
  weather, hazards, screens, spread targeting -- is registered but never
  taught, and carries `effectModeled = false` so a consumer can tell.
- That marker is not cosmetic: on Gold, Metronome builds its pool by walking
  every move record with a `power` field, which would have let it roll a
  placeholder nothing had learnt. Its pool builder is filtered so it rolls
  only moves that behave. Red is unaffected -- it rolls the cart's own list.
- The modded move roster changes the link fingerprint, so two players
  trading or battling must run the same mod.


## 0.14.1

### Fixed

- A form selected inside `useful_dex` showed the BASE species' base stats,
  BST and typing. That mod caches its stat rows on its own screen object
  rather than reading the record each draw, so cycling a form never reached
  them. Its cached table and a stand-in record are now substituted for the
  duration of its draw and restored immediately after, on the error path too.
- The total is re-summed from the rows actually substituted rather than
  copied, so the column adds up.

### Notes

- The stand-in is a shallow copy of the BASE record with only `types`
  replaced, so the page keeps printing the base species' dex number, name and
  entry -- a form's own `dex` is a synthetic key and must never be rendered.
- If the neighbour's table is not shaped as expected, the substitution
  declines entirely -- types included, so the page is never half-changed --
  and says so once in the log.
- The movelist page still lists the base species' moves while a form is
  selected. That is unchanged and deliberate: it is built outside the draw.


## 0.14.0

### Added

- Alternate-form browsing works again when `useful_dex` is installed. That mod
  replaces the dex screen and owns its update and draw, so LEFT/RIGHT never
  reached this mod's handler even though the form state was already sitting on
  the vanilla screen it delegates to. Its registered factory is now wrapped in
  memory after it loads, augmenting the instance it builds rather than
  competing for the screen id -- registering the same id errors outright.
  LEFT and RIGHT are unbound on that screen, so no key was taken from it.

### Notes

- Its files and class are never touched; everything is instance-level and
  lasts one boot. If its shape is not what this expects -- no delegate, or
  either method missing -- the augmentation declines and says so, and the
  whole of it is guarded so a throw cannot make the engine fall back to the
  builtin screen, which would cost that mod every one of its own features.
- The entry page still prints the BASE species' dex number on a form, the
  same rule this mod's own page follows.


## 0.13.1

### Fixed

- The Pokedex no longer renders art miscoloured when `useful_dex` is enabled.
  That mod replaces the dex screen and re-resolves the pic under a `battle`
  kind, which the sprite mod deliberately excludes from its full-colour
  answer, so 96px colour art was drawn through the four-shade pass. While a
  dex entry is being built or is on the stack, a pic lookup is now relabelled
  as a dex lookup whoever asks -- at `Sprites.path`, ahead of every hook, so
  the fix does not depend on mod load order.

## 0.13.0

### Added

- Gold's party summary shows the art chosen in the `universal_sprites` mod,
  through the same seam and the same `resolveSprite` export the Pokedex uses.
  The resolver is shared between both screens rather than copied, and is
  handed the live mon, so a shiny in the party gets its shiny art.

### Notes

- With `useful_dex` installed it owns the dex screen, so this mod's STATS page
  and form browsing are replaced by its own pages. Registering the same screen
  id would error outright, so this is not a conflict to win; the species data
  still feeds its screens. The stand-down is logged rather than silent.
- On Gold the summary backdrop keeps the cart's square rather than going black
  as the dex does: that panel is white, so black would be a box on a white
  page. A party Unown keeps the cart's pic, since the page shows its own
  letter and the sprite sets carry no per-letter art.


## 0.12.1

### Changed

- Sprite art in Gold's dex is centred in its box rather than stood on the
  bottom edge. The cart pads its own pics downward so a small mon shares a
  ground line with a big one; a sprite set's art arrives trimmed to its own
  bounds at whatever aspect the dump ships, so bottom-pinning left a wide
  sprite on the floor with the space above it empty.
- The blank square behind supplied art is black, matching the rest of the
  list panel, instead of the palette's lightest entry. That colour reads as a
  background behind a two-shade ROM pic and as a coloured card behind a
  full-colour sprite. Palette art keeps the cart's square unchanged.

## 0.12.0

### Added

- Gold's Pokedex draws the art chosen in the `universal_sprites` mod, asked
  for across the mod boundary through that mod's own `resolveSprite` export.
  A species it has no answer for keeps the cart's pic, so this is optional:
  without the sprite mod, or with it disabled, Gold's dex is unchanged.
- `universal_sprites` is named in `optional_dependencies`. That is a
  load-order edge rather than a requirement -- this mod's priority would
  otherwise put it first.

### Fixed

- Full-colour art no longer renders miscoloured in Gold's dex. That screen
  wraps its draw in the Game Boy Color palette unconditionally, without the
  opt-out the battle screen has. The palette is now bypassed for the single
  draw showing supplied art, with the previous shader restored immediately
  after; the cart's own pics still go through it untouched.

### Notes

- Which of the two applies is read from the engine's own true-colour seam,
  not from the fact that art came from a mod: a four-shade NATIVE set is art
  the palette is right for, and drawing it unshaded would render it grey.
- In CLASSIC colour mode Gold lays a whole-screen zone over the finished
  frame and nothing on Gen 2 marks a true-colour exemption, so supplied art
  takes the green ramp there -- as Gold's battle art already does.


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

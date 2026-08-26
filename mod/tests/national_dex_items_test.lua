-- The item catalogue, against the REAL built payload rather than a fixture.
--
-- The promise this suite guards is the one that separates items from
-- everything else the dex carries: it DESCRIBES them and never REGISTERS them.
-- Species, moves and abilities cannot be made real by being described --
-- registering an item can, because that is what puts one in a player's bag.
-- So the check that matters most here is not a field's shape, it is that
-- nothing in this mod ever calls content.items:register.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local MOD = arg[0]:gsub("[/\\]tests[/\\][^/\\]+$", "")

local index = dofile(MOD .. "/data/items/generated/api/index.lua")
local shards = {}
local function itemFor(id)
  local number = index[id]
  if not number then return nil end
  shards[number] = shards[number]
    or dofile(string.format("%s/data/items/generated/api/%03d.lua", MOD, number))
  return shards[number][id]
end

local function strip(text)
  return (tostring(text):upper():gsub("[^A-Z0-9]", ""))
end

-- --- the payload is real ----------------------------------------------------
local count = 0
for _ in pairs(index) do count = count + 1 end
T.check(count > 2000, "the item index carries the whole catalogue (" .. count .. ")")

-- --- this mod registers NOTHING ---------------------------------------------
-- The load-bearing check. A dex that registered Charizardite X would put a Mega
-- Stone into the bag of a player running the dex WITHOUT battle_forms -- an
-- item that does nothing and cannot be used. Describing is free; registering is
-- not, and this mod does only the first.
local registers = {}
for _, name in ipairs({ "main.lua", "src/api.lua", "src/nationaldex.lua" }) do
  local handle = io.open(MOD .. "/" .. name, "r")
  if handle then
    local body = handle:read("*a")
    handle:close()
    if body:find("content%.items:register") then registers[#registers + 1] = name end
  end
end
T.eq(#registers, 0, "this mod registers no items ("
  .. (#registers > 0 and table.concat(registers, ", ") or "nothing does") .. ")")

-- --- the record's shape -----------------------------------------------------
local leftovers = itemFor("LEFTOVERS")
T.check(leftovers ~= nil, "LEFTOVERS has a record")
if leftovers then
  T.eq(leftovers.id, "LEFTOVERS", "the id is the key")
  T.eq(leftovers.slug, "leftovers", "with PokeAPI's own slug")
  T.eq(leftovers.name, "Leftovers", "and a display name a page can print")
  T.eq(type(leftovers.itemId), "number", "PokeAPI's own number is carried")
  T.eq(leftovers.category, "held-items", "with its category")
  T.check(#leftovers.shortEffect > 0, "and what it does")
end

-- --- the attribute vocabulary -----------------------------------------------
-- PokeAPI's attributes are already a closed set, which is why they are carried
-- as-is rather than curated: they answer "can this be held", "does it work in
-- battle", "is it consumed" without reading a sentence.
local ATTRS = {
  countable = true, consumable = true, ["usable-overworld"] = true,
  ["usable-in-battle"] = true, holdable = true, ["holdable-passive"] = true,
  ["holdable-active"] = true, underground = true,
}
local badAttr, holdable, battle = {}, 0, 0
for id in pairs(index) do
  local record = itemFor(id)
  local isHoldable = false
  for _, attr in ipairs((record and record.attributes) or {}) do
    if not ATTRS[attr] then badAttr[#badAttr + 1] = id .. ":" .. attr end
    if attr == "holdable" then isHoldable = true end
    if attr == "usable-in-battle" then battle = battle + 1 end
  end
  if isHoldable then holdable = holdable + 1 end
end
T.eq(#badAttr, 0, "every attribute is inside PokeAPI's own closed set ("
  .. (#badAttr > 0 and table.concat(badAttr, ", "):sub(1, 80) or "all clean") .. ")")
T.check(holdable > 100, "a real number of items are holdable (" .. holdable .. ")")
T.check(battle > 20, "and usable in battle (" .. battle .. ")")

-- --- the ids battle_forms will actually ask for ------------------------------
-- Every item that mod registers itself should be describable here, so it can
-- read one line of display text instead of carrying a second copy.
for _, id in ipairs({ "CHARIZARDITEX", "LIFEORB", "TERAORB", "DYNAMAXBAND" }) do
  T.check(itemFor(id) ~= nil, id .. " is in the catalogue")
end

-- --- the --held split -------------------------------------------------------
-- PokeAPI models a Z-Crystal as TWO records: the bag item (category "unused")
-- and the held one (category "z-crystals"). A caller naming the item means the
-- held one essentially always, which is why the API retries a bare miss with
-- HELD appended -- and why the bare id must genuinely be absent, or that
-- fallback would be papering over a real record rather than reaching the right
-- one.
T.eq(itemFor("ELECTRIUMZ"), nil, "the bare Z-Crystal id is NOT a record")
local held = itemFor("ELECTRIUMZHELD")
T.check(held ~= nil, "the held one is")
if held then
  T.eq(held.category, "z-crystals", "under the z-crystals category")
  T.check(#held.shortEffect > 0, "carrying what it does")
end
local bagForm = itemFor("ELECTRIUMZBAG")
T.check(bagForm ~= nil, "and the bag form exists too, separately")
if bagForm then
  T.eq(bagForm.category, "unused", "as an unused entry, which is why it is not the one to read")
end

-- Every crystal battle_forms names resolves one way or the other, or its shop
-- shelf would show a name this mod could have corrected and did not.
local crystals = dofile(MOD .. "/../battle_forms_mod/data/crystals.lua")
local unresolved = {}
for key in pairs(crystals) do
  local id = strip(key)
  if not (itemFor(id) or itemFor(id .. "HELD")) then
    unresolved[#unresolved + 1] = key
  end
end
T.eq(#unresolved, 0, "every Z-Crystal battle_forms registers is describable here ("
  .. (#unresolved > 0 and table.concat(unresolved, ", ") or "all 18") .. ")")

-- --- blank effect text is admitted, not invented ----------------------------
-- PokeAPI carries no English effect prose for a great many legacy items, and an
-- empty string is how this payload says so. It must stay an empty string: a
-- fabricated description would be worse than a blank one, and a consumer can
-- only tell the difference if this never fabricates.
local blank = 0
for id in pairs(index) do
  local record = itemFor(id)
  if not record or record.shortEffect == "" then blank = blank + 1 end
end
T.check(blank > 0, "some items genuinely have no English effect text (" .. blank .. ")")
T.check(blank < count, "but far from all of them (" .. (count - blank) .. " do)")

-- --- ids follow the same convention as moves and abilities ------------------
local badKeys = {}
for id in pairs(index) do
  if id ~= strip(id) then badKeys[#badKeys + 1] = id end
end
T.eq(#badKeys, 0, "every id is separator-free uppercase ("
  .. (#badKeys > 0 and table.concat(badKeys, ", "):sub(1, 70) or "all clean") .. ")")

T.finish("national_dex_items")

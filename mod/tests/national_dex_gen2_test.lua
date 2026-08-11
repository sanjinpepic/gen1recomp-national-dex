-- Standalone: luajit mods/national_dex/tests/national_dex_gen2_test.lua
--
-- Run from the root of a gen1recomp checkout with this mod installed (or
-- symlinked) at mods/national_dex.
--
-- manifest.games claims gen1 AND gen2, and the loader gates on that claim: a
-- mod that does not name the running game is skipped, which is deliberately
-- not an error.  So this asserts the mod's STATE -- an error count of zero
-- passes just as happily for a mod that never ran a line.
--
-- Its own file rather than a block in national_dex_test.lua because the
-- engine's builtin registries are registered once per process; a second
-- loader.load in the same run raises on `statuses already registered` before
-- the mod is reached.
--
-- What this does NOT cover: the Gold code path itself.  The merge target here
-- is Red's dataset, so gen2shape.lua reports generation 1 and its reshaping
-- stays untaken.  Only a real Gold boot exercises that.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local FsIo = require("tests.fs_io")
-- The real dataset, not the SDK's fixture: the fixture carries a handful of
-- moves, so 1025 species' learnsets resolve to thousands of unresolved
-- references that say nothing about Gen 2.  Safe in this file because it is
-- the only load in the process.
local Data = require("src.core.Data")
Data:load()

local ID = "national_dex"
local PATH = "mods/" .. ID

local OPTIONS = [[return {
  mods = { national_dex = true },
  modOptions = { national_dex = { national_dex = "on", type_chart = "modern" } },
}]]

local function optionsFs()
  local inner = FsIo.new(".")
  local fs = { root = inner.root }

  function fs.read(path)
    if path == "options.lua" then return OPTIONS end
    return inner.read(path)
  end

  function fs.load(path)
    if path == "options.lua" then return load(OPTIONS, "@options.lua") end
    return inner.load(path)
  end

  function fs.getInfo(path)
    if path == "options.lua" then return { type = "file" } end
    return inner.getInfo(path)
  end

  function fs.getDirectoryItems(path)
    if path == "mods" then return { ID } end
    return inner.getDirectoryItems(path)
  end

  function fs.write() return true end

  return fs
end

local run = T.sdk.loadMod(PATH, { data = Data, fs = optionsFs(), generation = 2 })

T.eq(run.mod and run.mod.state, "loaded",
  "the gen2 claim gets it past the gate: "
    .. tostring(run.mod and run.mod.skipReason))
T.eq(#run.errors, 0,
  "and it boots clean under a Gen 2 loader (" .. tostring(run.errors[1]) .. ")")

-- The read API is published regardless of options or generation, so a
-- consumer mod on Gold still gets an answer.
local exports = run.loader.exports[ID]
T.check(type(exports) == "table", "exports are published on a Gen 2 boot")
T.check((exports.apiVersion or 0) >= 1, "including the apiVersion consumers gate on")

run.release()
T.finish("national_dex_gen2")

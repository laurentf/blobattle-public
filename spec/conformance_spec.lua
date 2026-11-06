local lfs = require("lfs")
local runner = require("conformance.runner")

local function vector_names()
  local names = {}
  for file in lfs.dir("spec/vectors") do
    local name = file:match("^(.+)%.lua$")
    if name then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

describe("🧮 conformance vectors (D-12)", function()
  it("🧮 finds at least the three vectors of the run", function()
    assert.is_true(#vector_names() >= 3)
  end)

  it("🧮 fails instead of hanging on a check after the end of the game", function()
    local duel = require("vectors.duel")
    local last = duel.checks[#duel.checks]
    local vector = { seed = duel.seed, settings = duel.settings, script = duel.script }
    vector.checks = { last + 300 }
    assert.has_error(function()
      runner.run(vector)
    end, "the game ended at tick " .. last .. ", before the check at tick " .. last + 300)
  end)

  it("🧮 the quake vector goes through quakes: its sums cover shakes and cracks", function()
    local world = require("shared.sim.world")
    local vector = require("vectors.quake")
    local w = assert(world.new(vector.seed, vector.settings))
    local by_tick = {}
    for _, entry in ipairs(vector.script) do
      local list = by_tick[entry.at] or {}
      list[#list + 1] = entry.input
      by_tick[entry.at] = list
    end
    local seen = { quaked = 0, shook = 0, cracked = 0 }
    while w.tick < vector.checks[#vector.checks] do
      assert.are_not.equal("ended", w.turn.state, "ended at tick " .. w.tick)
      for _, e in ipairs(world.step(w, by_tick[w.tick])) do
        if seen[e.type] then
          seen[e.type] = seen[e.type] + 1
        end
      end
    end
    assert.is_true(
      seen.quaked >= 2 and seen.shook >= 6 and seen.cracked >= 3,
      seen.quaked .. " quakes"
    )
    assert.is_true(#w.cracks >= 2)
  end)

  it("🧮 the dynamite vector places one: it goes off 5 s later and hurts blobs", function()
    local world = require("shared.sim.world")
    local vector = require("vectors.dynamite")
    local w = assert(world.new(vector.seed, vector.settings))
    local by_tick, placed = {}, nil
    for _, entry in ipairs(vector.script) do
      local list = by_tick[entry.at] or {}
      list[#list + 1] = entry.input
      by_tick[entry.at] = list
      if entry.input.weapon == "dynamite" then
        placed = entry.at
      end
    end
    assert.is_number(placed)
    local exploded, hurt = nil, 0
    while w.tick < vector.checks[#vector.checks] do
      assert.are_not.equal("ended", w.turn.state, "ended at tick " .. w.tick)
      for _, e in ipairs(world.step(w, by_tick[w.tick])) do
        if e.type == "exploded" and exploded == nil and w.tick > placed then
          exploded = w.tick
        elseif e.type == "damaged" and w.tick == exploded then
          hurt = hurt + 1
        end
      end
    end
    assert.are.same({ placed + 5 * 30, 2 }, { exploded, hurt })
  end)

  it("📦 the crates vector picks crates up and plays the four weapons in them", function()
    local world = require("shared.sim.world")
    local vector = require("vectors.crates")
    local w = assert(world.new(vector.seed, vector.settings))
    local by_tick = {}
    for _, entry in ipairs(vector.script) do
      local list = by_tick[entry.at] or {}
      list[#list + 1] = entry.input
      by_tick[entry.at] = list
    end
    local seen = { crate_dropped = 0, crate_landed = 0, crate_picked = 0, jet_started = 0 }
    local fired, bits, shells, set_off = {}, 0, 0, 0
    while w.tick < vector.checks[#vector.checks] do
      assert.are_not.equal("ended", w.turn.state, "ended at tick " .. w.tick)
      local inputs = by_tick[w.tick]
      local flying = w.turn.state == "flight"
      for _, e in ipairs(world.step(w, inputs)) do
        if seen[e.type] then
          seen[e.type] = seen[e.type] + 1
        elseif e.type == "fired" then
          fired[e.weapon] = true
        elseif e.type == "exploded" and flying and inputs then
          set_off = set_off + 1
        end
      end
      for _, p in ipairs(w.projectiles) do
        bits = bits + (p.weapon == "cluster_bit" and p.age == 1 and 1 or 0)
        shells = shells + (p.weapon == "airstrike_shell" and p.age == 1 and 1 or 0)
      end
    end
    assert.is_true(
      seen.crate_dropped >= 4 and seen.crate_landed >= 4,
      seen.crate_dropped .. " drops"
    )
    assert.is_true(seen.crate_picked >= 4, seen.crate_picked .. " picked")
    assert.are.same({ true, true, true }, { fired.cluster, fired.airstrike, fired.waddler })
    assert.is_true(seen.jet_started >= 1 and bits >= 5 and shells >= 5 and set_off >= 1)
  end)

  for _, name in ipairs(vector_names()) do
    it("🧮 " .. name .. " gives its recorded checksums", function()
      local vector = require("vectors." .. name)
      assert.are.same(vector.expected, runner.run(vector))
    end)

    it("🧮 " .. name .. " gives its recorded team and member names", function()
      local vector = require("vectors." .. name)
      assert.is_table(vector.names)
      assert.are.same(vector.names, runner.names(vector))
    end)
  end
end)

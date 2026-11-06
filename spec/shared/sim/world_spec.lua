local cat = require("shared.sim.cat")
local mapgen = require("shared.sim.mapgen")
local maps = require("spec.support.maps")
local projectile = require("shared.sim.projectile")
local terrain = require("shared.sim.terrain")
local terrains = require("spec.support.terrains")
local weapons = require("shared.sim.weapons.registry")
local world = require("shared.sim.world")

local function sums(w)
  return { world.checksum(w) }
end

local function scripted(w, ticks)
  local trail = {}
  for i = 1, ticks do
    local inputs
    if w.turn.state == "aiming" and w.turn.ticks == 5 then
      inputs =
        { { team = w.turn.team, kind = "fire", weapon = "grenade", angle = 200, power = 55 } }
    elseif w.turn.state == "aiming" and w.turn.ticks == 1 then
      inputs = { { team = w.turn.team, kind = "move", direction = -1 } }
    end
    world.step(w, inputs)
    if i % 30 == 0 then
      trail[#trail + 1] = sums(w)
    end
  end
  return trail
end

local function until_aiming(w)
  for _ = 1, 200 do
    if w.turn.state == "aiming" then
      return
    end
    world.step(w)
  end
end

local function duel()
  return world.from_terrain({
    terrain = terrains.flat(),
    liquid = terrains.LIQUID,
    settings = { teams = 2, cats_per_team = 2, wind_max = 10 },
    spawns = {
      { team = 1, index = 1, x = 30, y = terrains.GROUND - 1 },
      { team = 1, index = 2, x = 70, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 120, y = terrains.GROUND - 1 },
      { team = 2, index = 2, x = 170, y = terrains.GROUND - 1 },
    },
  })
end

describe("🌍 the world", function()
  it("🌍 resolves every setting to its default", function()
    assert.are.same({
      teams = 4,
      cats_per_team = 4,
      wind_max = 10,
      turn_seconds = 45,
      map = "random",
      bot_level = "medium",
    }, world.resolve_settings({}))
  end)

  it("🌍 refuses each setting out of its bounds with its own reason", function()
    local cases = {
      { { teams = 1 }, "invalid_teams" },
      { { teams = 9 }, "invalid_teams" },
      { { teams = 2.5 }, "invalid_teams" },
      { { teams = "4" }, "invalid_teams" },
      { { cats_per_team = 0 }, "invalid_cats_per_team" },
      { { cats_per_team = 7 }, "invalid_cats_per_team" },
      { { wind_max = 11 }, "invalid_wind_max" },
      { { wind_max = -1 }, "invalid_wind_max" },
      { { turn_seconds = 50 }, "invalid_turn_seconds" },
      { { map = "desert" }, "invalid_map" },
      { { bot_level = "god" }, "invalid_bot_level" },
    }
    for _, case in ipairs(cases) do
      local settings, err = world.resolve_settings(case[1])
      assert.is_nil(settings)
      assert.are.equal(case[2], err)
    end
    assert.are.same(
      {
        teams = 8,
        cats_per_team = 6,
        wind_max = 0,
        turn_seconds = 90,
        map = "volcano",
        bot_level = "hard",
      },
      world.resolve_settings({
        teams = 8,
        cats_per_team = 6,
        wind_max = 0,
        turn_seconds = 90,
        map = "volcano",
        bot_level = "hard",
      })
    )
  end)

  it("🌍 refuses a seed outside 1..2147483646", function()
    for _, seed in ipairs({ 0, -5, 1.5, 2147483647, "7" }) do
      local w, err = world.new(seed, { teams = 2, cats_per_team = 1 })
      assert.is_nil(w)
      assert.are.equal("invalid_seed", err)
    end
  end)

  it("🌍 generates a map, places every cat and starts with the map's first team", function()
    local settings = { teams = 3, cats_per_team = 2 }
    local w = world.new(12345, settings)
    assert.are.equal(6, #w.cats)
    assert.are.equal("turn_start", w.turn.state)
    for _, c in ipairs(w.cats) do
      assert.is_true(c.alive and c.grounded)
    end
    local map = mapgen.generate(12345, world.resolve_settings(settings))
    assert.are.equal(map.first_team, w.turn.team)
  end)

  it("🌍 starts every cat in the open sky on 10 seeds × 7 settings (§5.3)", function()
    for _, settings in ipairs(maps.SETTINGS) do
      for seed = 1, 10 do
        local w = assert(world.new(seed * 104729, settings))
        for _, c in ipairs(w.cats) do
          local px, py = cat.pixel(c)
          assert.is_true(
            maps.open_sky(w.terrain, px, py),
            "cat " .. c.id .. " under soil with seed " .. seed * 104729
          )
        end
      end
    end
  end)
end)

describe("🌍 the state of the world", function()
  it("🌍 replays identically from the same seed and inputs", function()
    assert.are.same(
      scripted(world.new(777, { teams = 2, cats_per_team = 2 }), 1500),
      scripted(world.new(777, { teams = 2, cats_per_team = 2 }), 1500)
    )
  end)

  it("🌍 changes its checksum with every field of the state", function()
    local w = duel()
    until_aiming(w)
    world.step(
      w,
      { { team = w.turn.team, kind = "fire", weapon = "grenade", angle = 200, power = 30 } }
    )
    assert.are.equal(1, #w.projectiles)
    local base = sums(w)
    local function differs(label, change, undo)
      change()
      assert.are_not.same(base, sums(w), label)
      undo()
      assert.are.same(base, sums(w), label .. " undo")
    end
    local c, p = w.cats[2], w.projectiles[1]
    for _, key in ipairs({
      "x",
      "y",
      "vx",
      "vy",
      "hp",
      "facing",
      "walk",
      "walk_clock",
      "nudge",
      "gauge",
      "anchor_x",
      "anchor_y",
      "rope",
      "climb",
      "dig",
      "dig_angle",
      "jet",
    }) do
      differs("cat " .. key, function()
        c[key] = c[key] + 1
      end, function()
        c[key] = c[key] - 1
      end)
    end
    for _, key in ipairs({ "alive", "grounded", "hurt", "hanging" }) do
      differs("cat " .. key, function()
        c[key] = not c[key]
      end, function()
        c[key] = not c[key]
      end)
    end
    for _, key in ipairs({ "id", "owner", "x", "y", "vx", "vy", "age", "fuse", "facing" }) do
      differs("projectile " .. key, function()
        p[key] = p[key] + 1
      end, function()
        p[key] = p[key] - 1
      end)
    end
    for _, key in ipairs({ "resting", "alive" }) do
      differs("projectile " .. key, function()
        p[key] = not p[key]
      end, function()
        p[key] = not p[key]
      end)
    end
    differs("projectile weapon", function()
      p.weapon = "bazooka"
    end, function()
      p.weapon = "grenade"
    end)
    for _, key in ipairs({ "ticks", "team", "cat", "timer" }) do
      differs("turn " .. key, function()
        w.turn[key] = w.turn[key] + 1
      end, function()
        w.turn[key] = w.turn[key] - 1
      end)
    end
    differs("turn state", function()
      w.turn.state = "retreat"
    end, function()
      w.turn.state = "flight"
    end)
    differs("wind", function()
      w.wind = w.wind + 1
    end, function()
      w.wind = w.wind - 1
    end)
    differs("liquid level", function()
      w.liquid.level = w.liquid.level - 2
    end, function()
      w.liquid.level = w.liquid.level + 2
    end)
    differs("rounds", function()
      w.rounds = w.rounds + 1
    end, function()
      w.rounds = w.rounds - 1
    end)
    differs("team turns", function()
      w.teams[1].turns = w.teams[1].turns + 1
    end, function()
      w.teams[1].turns = w.teams[1].turns - 1
    end)
    local ammo = w.teams[1].ammo[1]
    differs("ammo", function()
      w.teams[1].ammo[1] = ammo - 1
    end, function()
      w.teams[1].ammo[1] = ammo
    end)
    differs("terrain log", function()
      w.terrain.log.a = w.terrain.log.a + 1
    end, function()
      w.terrain.log.a = w.terrain.log.a - 1
    end)
    differs("sim stream", function()
      w.rng.sim.state = w.rng.sim.state + 1
    end, function()
      w.rng.sim.state = w.rng.sim.state - 1
    end)
    differs("tick", function()
      w.tick = w.tick + 1
    end, function()
      w.tick = w.tick - 1
    end)
    differs("next slot", function()
      w.teams[2].next_slot = w.teams[2].next_slot + 1
    end, function()
      w.teams[2].next_slot = w.teams[2].next_slot - 1
    end)
    differs("next projectile", function()
      w.next_projectile = w.next_projectile + 1
    end, function()
      w.next_projectile = w.next_projectile - 1
    end)
    differs("terrain log b", function()
      w.terrain.log.b = w.terrain.log.b + 1
    end, function()
      w.terrain.log.b = w.terrain.log.b - 1
    end)
    differs("result", function()
      w.result = { winner = nil }
    end, function()
      w.result = nil
    end)
    differs("winner", function()
      w.result = { winner = 2 }
    end, function()
      w.result = nil
    end)
  end)

  it("🌍 hands each team the ammunition of rules.AMMO when a game starts (§8.2)", function()
    local rules = require("shared.sim.rules")
    local w = assert(world.new(5, { teams = 3, cats_per_team = 1 }))
    for _, team in ipairs(w.teams) do
      for i, weapon in ipairs(weapons.list) do
        assert.are.equal(rules.AMMO[weapon.id], team.ammo[i], weapon.id)
      end
    end
  end)

  it("🎒 a grenade refused for its fuse is not spent", function()
    local w = duel()
    until_aiming(w)
    local slot = weapons.index_of("grenade")
    local before = w.teams[w.turn.team].ammo[slot]
    world.step(w, {
      { team = w.turn.team, kind = "fire", weapon = "grenade", angle = 64, power = 50, fuse = 9 },
    })
    assert.are.same(
      { before, "aiming", 0 },
      { w.teams[w.turn.team].ammo[slot], w.turn.state, #w.projectiles }
    )
  end)

  it("🌍 keeps the bots' random stream out of the world", function()
    local w = world.new(5, { teams = 2, cats_per_team = 1 })
    assert.is_nil(w.rng.bots)
    assert.is_nil(w.rng.map)
    assert.is_nil(world.snapshot(w).rng_bots)
  end)

  it("🌍 reports a shot as fired, exploded and damaged, in that order", function()
    local w = duel()
    local kinds = {}
    for _ = 1, 600 do
      local inputs
      if w.turn.state == "aiming" and w.turn.team == 1 and #w.projectiles == 0 and #kinds == 0 then
        inputs = { { team = 1, kind = "fire", weapon = "bazooka", angle = 60, power = 45 } }
      end
      for _, e in ipairs(world.step(w, inputs)) do
        if e.type == "fired" or e.type == "exploded" or e.type == "damaged" then
          kinds[#kinds + 1] = e.type
        end
      end
    end
    assert.are.equal("fired", kinds[1])
    assert.are.equal("exploded", kinds[2])
  end)

  it("🌍 restores a snapshot with the same checksum and the same cells", function()
    local w = world.new(4242, { teams = 2, cats_per_team = 3 })
    scripted(w, 700)
    local copy = assert(world.restore(world.snapshot(w)))
    assert.are.same(sums(w), sums(copy))
    assert.are.same(w.terrain.cells, copy.terrain.cells)
    assert.are.same({ terrain.cells_hash(w.terrain) }, { terrain.cells_hash(copy.terrain) })
    assert.are.same(scripted(w, 900), scripted(copy, 900))
  end)

  local function round_trip(w, ticks)
    local s = world.snapshot(w)
    local copy = assert(world.restore(s))
    assert.are.same(sums(w), sums(copy))
    assert.are.same(w.terrain.cells, copy.terrain.cells)
    local a, b = {}, {}
    for _ = 1, ticks do
      world.step(w)
      world.step(copy)
      a[#a + 1] = sums(w)
      b[#b + 1] = sums(copy)
    end
    assert.are.same(a, b)
    return s
  end

  local function crated()
    local w = duel()
    for _ = 1, 20000 do
      if #w.crates > 0 and w.crates[1].chute then
        return w
      end
      local inputs = nil
      if w.turn.state == "aiming" then
        inputs = { { team = w.turn.team, kind = "skip" } }
      end
      world.step(w, inputs)
    end
    error("no crate came down")
  end

  it("🌍 restores a crate under its chute and carries on identically", function()
    local w = crated()
    for _ = 1, 10 do
      world.step(w)
    end
    assert.is_true(w.crates[1].chute and w.crates[1].alive)
    local copy = assert(world.restore(world.snapshot(w)))
    assert.are.same(w.crates, copy.crates)
    assert.are_not.equal(w.crates[1], copy.crates[1])
    round_trip(w, 200)
  end)

  it("🌍 changes its checksum with every field of a crate", function()
    local w = crated()
    world.step(w)
    local k = w.crates[1]
    local base = sums(w)
    for _, key in ipairs({ "id", "x", "y", "vx", "vy", "fuse" }) do
      k[key] = k[key] + 1
      assert.are_not.same(base, sums(w), key)
      k[key] = k[key] - 1
      assert.are.same(base, sums(w), key .. " undo")
    end
    for _, key in ipairs({ "chute", "alive" }) do
      k[key] = not k[key]
      assert.are_not.same(base, sums(w), key)
      k[key] = not k[key]
    end
    local weapon = k.weapon
    k.weapon = weapon == "cluster" and "jetpack" or "cluster"
    assert.are_not.same(base, sums(w), "weapon")
    k.weapon = weapon
    w.next_crate = w.next_crate + 1
    assert.are_not.same(base, sums(w), "next crate")
    w.next_crate = w.next_crate - 1
    assert.are.same(base, sums(w))
  end)

  it("🌍 restores a live bouncing grenade and carries on identically", function()
    local w = duel()
    until_aiming(w)
    world.step(
      w,
      { { team = w.turn.team, kind = "fire", weapon = "grenade", angle = 170, power = 45 } }
    )
    local bounced = false
    for _ = 1, 60 do
      for _, e in ipairs(world.step(w)) do
        if e.type == "bounced" then
          bounced = true
        end
      end
      if bounced then
        break
      end
    end
    assert.is_true(bounced)
    assert.are.equal(1, #w.projectiles)
    assert.is_true(w.projectiles[1].age > 0 and w.projectiles[1].fuse > 0)
    round_trip(w, 200)
  end)

  it("🌍 restores a cat mid-walk and mid-jump and carries on identically", function()
    local w = duel()
    until_aiming(w)
    world.step(w, { { team = w.turn.team, kind = "move", direction = 1 } })
    world.step(w)
    world.step(w)
    local walker = w.cats[w.turn.cat]
    assert.is_true(walker.walk ~= 0 and walker.walk_clock > 0)
    round_trip(w, 60)
    world.step(w, { { team = w.turn.team, kind = "jump", direction = -1 } })
    world.step(w)
    assert.is_false(w.cats[w.turn.cat].grounded)
    round_trip(w, 60)
  end)

  it("🌍 restores a cat swinging on its tentacle and carries on identically", function()
    local w = duel()
    for x = 0, w.terrain.width - 1 do
      for y = 40, 44 do
        terrain.set(w.terrain, x, y, terrain.SOIL)
      end
    end
    until_aiming(w)
    local team = w.turn.team
    local swinger = w.cats[w.turn.cat]
    world.step(w, { { team = team, kind = "fire", weapon = "tentacle", angle = 200, power = 50 } })
    world.step(w, { { team = team, kind = "climb", direction = -1 } })
    for _ = 1, 20 do
      world.step(w)
    end
    world.step(w, { { team = team, kind = "move", direction = 1 } })
    world.step(w)
    assert.is_true(swinger.hanging and swinger.climb == -1 and not swinger.grounded)
    round_trip(w, 90)
  end)

  it("🌍 a utility spends its ammunition when it acts, like any weapon (§8)", function()
    local w = duel()
    for x = 0, w.terrain.width - 1 do
      for y = 40, 44 do
        terrain.set(w.terrain, x, y, terrain.SOIL)
      end
    end
    until_aiming(w)
    local team = w.teams[w.turn.team]
    local slot = weapons.index_of("tentacle")
    team.ammo[slot] = 1
    local throw = { team = w.turn.team, kind = "fire", weapon = "tentacle", angle = 256, power = 1 }
    world.step(w, { throw })
    assert.are.equal(0, team.ammo[slot])
    world.step(w, { { team = w.turn.team, kind = "jump", direction = 1 } })
    world.step(w, { throw })
    assert.is_false(w.cats[w.turn.cat].hanging)
    assert.are.equal(0, team.ammo[slot])
  end)

  it("🌍 restores a game that ended in a draw", function()
    local w = duel()
    for _, c in ipairs(w.cats) do
      c.hp = 0
    end
    until_aiming(w)
    world.step(w, { { team = w.turn.team, kind = "skip" } })
    for _ = 1, 400 do
      world.step(w)
    end
    assert.are.equal("ended", w.turn.state)
    assert.is_nil(w.result.winner)
    local copy = assert(world.restore(world.snapshot(w)))
    assert.is_not_nil(copy.result)
    assert.is_nil(copy.result.winner)
    assert.are.same(sums(w), sums(copy))
  end)

  it("🌍 refuses a snapshot whose cells disagree with its terrain", function()
    local s = world.snapshot(duel())
    s.cells[1] = s.cells[1] + 1
    local w, err = world.restore(s)
    assert.is_nil(w)
    assert.are.equal("snapshot_cells", err)
  end)

  it("🌍 writes snapshots of plain data only", function()
    local function plain(v, path)
      local kind = type(v)
      if kind == "table" then
        for k, item in pairs(v) do
          assert.is_true(type(k) == "string" or type(k) == "number", path)
          plain(item, path .. "." .. tostring(k))
        end
      else
        assert.is_true(
          kind == "number" or kind == "string" or kind == "boolean",
          path .. " is " .. kind
        )
      end
    end
    plain(world.snapshot(duel()), "snapshot")
    local w = duel()
    until_aiming(w)
    world.step(
      w,
      { { team = w.turn.team, kind = "fire", weapon = "grenade", angle = 170, power = 45 } }
    )
    for _ = 1, 10 do
      world.step(w)
    end
    plain(world.snapshot(w), "snapshot in flight")
  end)

  it("🌍 snapshots every field a cat or a projectile is born with", function()
    local w = duel()
    until_aiming(w)
    world.step(
      w,
      { { team = w.turn.team, kind = "fire", weapon = "grenade", angle = 200, power = 30 } }
    )
    local s = world.snapshot(w)
    for key in pairs(cat.new({ id = 1, team = 1, index = 1, px = 0, py = 0 })) do
      assert.is_not_nil(s.cats[1][key], "cat field " .. key .. " is not in the snapshot")
    end
    local born =
      projectile.new({ id = 1, weapon = "grenade", owner = 1, x = 0, y = 0, vx = 0, vy = 0 })
    for key in pairs(born) do
      assert.is_not_nil(
        s.projectiles[1][key],
        "projectile field " .. key .. " is not in the snapshot"
      )
    end
  end)

  it("🌍 refuses a snapshot whose terrain is corrupt", function()
    local s = world.snapshot(duel())
    s.terrain[6] = -4
    local w, err = world.restore(s)
    assert.is_nil(w)
    assert.are.equal("snapshot_terrain", err)
  end)

  it("🌍 refuses a snapshot of another version", function()
    local s = world.snapshot(duel())
    s.version = 99
    local w, err = world.restore(s)
    assert.is_nil(w)
    assert.are.equal("snapshot_version", err)
  end)
end)

describe("📦 the largest snapshot (§6.6, H-06)", function()
  it("📦 stays under 27 KB in JSON for 8 teams of 6 after 15 600 ticks of bots", function()
    local json = require("dkjson")
    local driver = require("shared.bots.driver")
    local w = assert(world.new(4242, { teams = 8, cats_per_team = 6, bot_level = "hard" }))
    local d = driver.new({ seed = 4242, teams = { 1, 2, 3, 4, 5, 6, 7, 8 }, level = "hard" })
    while w.tick < 15600 and w.turn.state ~= "ended" do
      world.step(w, driver.inputs(d, w))
    end
    assert.are.equal(15600, w.tick)
    local size = #json.encode(world.snapshot(w))
    assert.is_true(size >= 24000 and size <= 27000, size .. " bytes")
  end)

  it(
    "📦 stays under 34 KB in a cracked forest: 8 teams of 6, 19 rounds, 10 cracks, 3 crates",
    function()
      local json = require("dkjson")
      local driver = require("shared.bots.driver")
      local w =
        assert(world.new(2, { teams = 8, cats_per_team = 6, bot_level = "easy", map = "forest" }))
      local d = driver.new({ seed = 2, teams = { 1, 2, 3, 4, 5, 6, 7, 8 }, level = "easy" })
      while w.tick < 30000 and w.turn.state ~= "ended" do
        world.step(w, driver.inputs(d, w))
      end
      assert.are.same({ 30000, 19, 10, 3 }, { w.tick, w.rounds, #w.cracks, #w.crates })
      local size = #json.encode(world.snapshot(w))
      assert.is_true(size >= 29000 and size <= 34000, size .. " bytes")
    end
  )
end)

describe("📦 the snapshot cache (§6.6)", function()
  it("📦 reuses the terrain encoding until a crater changes the terrain", function()
    local w = assert(world.new(1234, { teams = 2, cats_per_team = 1 }))
    local cache = {}
    local first = world.snapshot(w, cache)
    local second = world.snapshot(w, cache)
    assert.are.equal(first.terrain, second.terrain)
    assert.are.same({ terrain.cells_hash(w.terrain) }, second.cells)
    while w.turn.state ~= "aiming" do
      world.step(w)
    end
    world.step(
      w,
      { { team = w.turn.team, kind = "fire", weapon = "bazooka", angle = 768, power = 5 } }
    )
    local craters = 0
    while w.turn.state == "flight" do
      for _, e in ipairs(world.step(w)) do
        if e.type == "exploded" then
          craters = craters + 1
        end
      end
    end
    assert.are.equal(1, craters)
    local third = world.snapshot(w, cache)
    assert.are_not.equal(first.terrain, third.terrain)
    assert.are.same({ terrain.cells_hash(w.terrain) }, third.cells)
    assert.are.same({ world.checksum(w) }, { world.checksum(assert(world.restore(third))) })
    assert.are.same(world.snapshot(w), third)
  end)
end)

describe("🌍 wells and cracks in the state (§5.9)", function()
  local quake = require("shared.sim.quake")

  local function cracked_field()
    local w = world.from_terrain({
      terrain = terrains.flat(),
      liquid = terrains.LIQUID,
      wells = { { x = 150, width = 10 } },
      settings = { teams = 2, cats_per_team = 1, wind_max = 0 },
      spawns = {
        { team = 1, index = 1, x = 20, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 180, y = terrains.GROUND - 1 },
      },
    })
    quake.open(w, 60)
    return w
  end

  it("🌍 keeps the generated wells in the world", function()
    local w = assert(world.new(4242, { teams = 2, cats_per_team = 2, map = "forest" }))
    local map = mapgen.generate(
      4242,
      world.resolve_settings({ teams = 2, cats_per_team = 2, map = "forest" })
    )
    assert.are.same(map.wells, w.wells)
    assert.are.same({}, w.cracks)
  end)

  it("🌍 changes its checksum with every field of a well and of a crack", function()
    local w = cracked_field()
    local base = sums(w)
    local function differs(label, change, undo)
      change()
      assert.are_not.same(base, sums(w), label)
      undo()
      assert.are.same(base, sums(w), label .. " undo")
    end
    local well, crack = w.wells[1], w.cracks[1]
    for _, record in ipairs({
      { "well", well, { "x", "width" } },
      { "crack", crack, { "x", "width", "top" } },
    }) do
      for _, key in ipairs(record[3]) do
        differs(record[1] .. " " .. key, function()
          record[2][key] = record[2][key] + 1
        end, function()
          record[2][key] = record[2][key] - 1
        end)
      end
    end
    for k = 1, #crack.path do
      differs("crack offset " .. k, function()
        crack.path[k] = crack.path[k] + 1
      end, function()
        crack.path[k] = crack.path[k] - 1
      end)
    end
    differs("one more offset", function()
      crack.path[#crack.path + 1] = 0
    end, function()
      crack.path[#crack.path] = nil
    end)
    differs("one more well", function()
      w.wells[2] = { x = 0, width = 0 }
    end, function()
      w.wells[2] = nil
    end)
    differs("one more crack", function()
      w.cracks[2] = { x = 0, width = 0, top = 0, path = {} }
    end, function()
      w.cracks[2] = nil
    end)
  end)

  it("🌍 snapshots its wells and cracks as copies, version 11", function()
    local w = cracked_field()
    local s = world.snapshot(w)
    assert.are.equal(11, s.version)
    assert.are.same(w.wells, s.wells)
    assert.are.same(w.cracks, s.cracks)
    local copy = assert(world.restore(s))
    assert.are.same(w.wells, copy.wells)
    assert.are.same(w.cracks, copy.cracks)
    for _, pair in ipairs({ { s, w }, { copy, w }, { copy, s } }) do
      assert.are_not.equal(pair[1].cracks[1].path, pair[2].cracks[1].path)
      assert.are_not.equal(pair[1].cracks[1], pair[2].cracks[1])
      assert.are_not.equal(pair[1].wells[1], pair[2].wells[1])
    end
    copy.cracks[1].path[1] = 5
    copy.wells[1].x = 1
    assert.are.same(w.cracks, s.cracks)
    assert.are.same(w.wells, s.wells)
  end)

  local function skipping(w, ticks)
    local trail = {}
    for _ = 1, ticks do
      local inputs = nil
      if w.turn.state == "aiming" then
        inputs = { { team = w.turn.team, kind = "skip" } }
      end
      local kinds = {}
      for _, e in ipairs(world.step(w, inputs)) do
        kinds[#kinds + 1] = e.type
      end
      trail[#trail + 1] = { sums(w), kinds }
    end
    return trail
  end

  it(
    "🌍 restores a forest mid-quake and quakes on identically, cracks and wells included",
    function()
      local w = assert(world.new(31, { teams = 2, cats_per_team = 1, map = "forest" }))
      assert.are.equal("water", w.liquid.kind)
      for _ = 1, 20000 do
        if w.turn.state == "quake" and w.turn.ticks == 5 then
          break
        end
        skipping(w, 1)
      end
      assert.are.same({ "quake", 5, 1 }, { w.turn.state, w.turn.ticks, #w.cracks })
      local copy = assert(world.restore(world.snapshot(w)))
      assert.are.same(sums(w), sums(copy))
      assert.are.same(w.wells, copy.wells)
      local a, b = skipping(w, 600), skipping(copy, 600)
      assert.are.same(a, b)
      assert.is_true(#w.cracks >= 2)
      assert.are.same(w.terrain.cells, copy.terrain.cells)
    end
  )
end)

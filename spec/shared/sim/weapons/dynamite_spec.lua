local cat = require("shared.sim.cat")
local rules = require("shared.sim.rules")
local terrains = require("spec.support.terrains")
local turn = require("shared.sim.turn")
local weapons = require("shared.sim.weapons.registry")
local world = require("shared.sim.world")

local FUSE = 5 * rules.TICKS_PER_SECOND

local function field(spawns, t)
  return world.from_terrain({
    terrain = t or terrains.flat(),
    liquid = terrains.LIQUID,
    settings = { teams = 2, cats_per_team = #spawns / 2, wind_max = 0 },
    spawns = spawns,
  })
end

local function my_turn(w, team)
  for _ = 1, 3000 do
    if w.turn.state == "aiming" and w.turn.team == team then
      return true
    end
    local inputs = nil
    if w.turn.state == "aiming" then
      inputs = { { team = w.turn.team, kind = "skip" } }
    end
    world.step(w, inputs)
  end
  return false
end

local function place(w, fields)
  local input = { team = w.turn.team, kind = "fire", weapon = "dynamite", angle = 0, power = 1 }
  for k, v in pairs(fields or {}) do
    input[k] = v
  end
  local placed = false
  for _, e in ipairs(world.step(w, { input })) do
    placed = placed or (e.type == "fired" and e.weapon == "dynamite")
  end
  return placed
end

local function find(events, kind)
  for _, e in ipairs(events) do
    if e.type == kind then
      return e
    end
  end
  return nil
end

describe("🧨 the dynamite (§8.2)", function()
  it("🧨 uses §8.2's figures", function()
    local d = weapons.get("dynamite")
    assert.are.same({
      kind = "placed",
      aim = "none",
      timer = 5,
      wind = 0,
      bounce = { restitution = 20, friction = 50 },
      explosion = { carve = 20, radius = 30, damage = 75, push = 2304 },
      ammo = 1,
    }, {
      kind = d.kind,
      aim = d.aim,
      timer = d.timer,
      wind = d.wind_percent,
      bounce = d.bounce,
      explosion = d.explosion,
      ammo = rules.AMMO.dynamite,
    })
    assert.is_true(weapons.ends_turn("dynamite"))
  end)

  it(
    "🧨 placed at the blob's feet, goes off 5 s later, while the blob walks away all along",
    function()
      local w = field({
        { team = 1, index = 1, x = 60, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 180, y = terrains.GROUND - 1 },
      })
      assert.is_true(my_turn(w, 1))
      local blob = w.cats[1]
      local start_x = cat.pixel(blob)
      local placed_at = w.tick
      assert.is_true(place(w))
      assert.are.same({ "retreat", 1 }, { w.turn.state, #w.projectiles })
      local x, y = cat.pixel(blob)
      local p = w.projectiles[1]
      assert.are.same({ blob.x, y }, { p.x, math.floor(p.y / 256) })
      assert.are.equal(x, math.floor(p.x / 256))
      world.step(w, { { team = 1, kind = "move", direction = 1 } })
      local blast = nil
      while blast == nil and w.tick - placed_at < FUSE + 5 do
        assert.are.equal("retreat", w.turn.state)
        blast = find(world.step(w), "exploded")
      end
      assert.are.equal(FUSE, w.tick - placed_at)
      assert.are.same({ start_x, terrains.GROUND - 1, 20 }, { blast.x, blast.y, blast.radius })
      assert.is_true(cat.pixel(blob) - start_x >= 60, "walked " .. cat.pixel(blob) - start_x)
      assert.are.same({ rules.CAT_HP, "settling" }, { blob.hp, w.turn.state })
    end
  )

  it("🧨 costs the blob that stays on it at least 65 HP, and its neighbour dearly too", function()
    local w = field({
      { team = 1, index = 1, x = 60, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 66, y = terrains.GROUND - 1 },
    })
    assert.is_true(my_turn(w, 1))
    assert.is_true(place(w))
    for _ = 1, FUSE do
      world.step(w)
    end
    local on, next_to = w.cats[1], w.cats[2]
    assert.is_true(on.hp <= rules.CAT_HP - 65, "on it: " .. on.hp)
    assert.is_true(
      next_to.hp <= rules.CAT_HP - 55 and next_to.hp > on.hp,
      "next to it: " .. next_to.hp
    )
  end)

  it("🧨 one per team and per game", function()
    local w = field({
      { team = 1, index = 1, x = 40, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 180, y = terrains.GROUND - 1 },
    })
    local slot = weapons.index_of("dynamite")
    assert.is_true(my_turn(w, 1))
    assert.is_true(place(w))
    assert.are.equal(0, w.teams[1].ammo[slot])
    world.step(w, { { team = 1, kind = "move", direction = 1 } })
    assert.is_true(my_turn(w, 1))
    assert.is_false(place(w))
    assert.are.same({ "aiming", 0 }, { w.turn.state, #w.projectiles })
  end)

  it("🧨 placed in the air, falls to the ground through the blobs, and rests there", function()
    local w = field({
      { team = 1, index = 1, x = 60, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 180, y = terrains.GROUND - 1 },
    })
    assert.is_true(my_turn(w, 1))
    world.step(w, { { team = 1, kind = "jump", direction = 1 } })
    for _ = 1, 6 do
      world.step(w)
    end
    assert.is_false(w.cats[1].grounded)
    assert.is_true(place(w))
    local p = w.projectiles[1]
    for _ = 1, 60 do
      world.step(w)
    end
    assert.are.same({ true, terrains.GROUND - 1 }, { p.resting, math.floor(p.y / 256) })
    assert.is_true(p.alive)
  end)

  it("🧨 mirrored placings, facing either way, give mirrored blasts", function()
    local function blast(x, side)
      local w = field({
        { team = 1, index = 1, x = x, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = x + 6 * side, y = terrains.GROUND - 1 },
      }, terrains.flat(300))
      assert.is_true(my_turn(w, 1))
      world.step(w, {
        { team = 1, kind = "move", direction = side },
        { team = 1, kind = "move", direction = 0 },
      })
      assert.are.equal(side, w.cats[1].facing)
      assert.is_true(place(w))
      for _ = 1, FUSE do
        local e = find(world.step(w), "exploded")
        if e then
          local on, next_to = w.cats[1], w.cats[2]
          return { e.x, on.hp, on.vx, on.vy, next_to.hp, next_to.vx, next_to.vy }
        end
      end
    end
    local right, left = blast(60, 1), blast(240, -1)
    assert.are.same(
      { 300 - 1 - right[1], right[2], -right[3], right[4], right[5], -right[6], right[7] },
      left
    )
  end)

  it("🧨 ignores a fuse sent with it: it still goes off 5 s later", function()
    local w = field({
      { team = 1, index = 1, x = 60, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 180, y = terrains.GROUND - 1 },
    })
    assert.is_true(my_turn(w, 1))
    local placed_at = w.tick
    assert.is_true(place(w, { fuse = 1 }))
    local blast = nil
    while blast == nil and w.tick - placed_at < FUSE + 5 do
      blast = find(world.step(w), "exploded")
    end
    assert.are.equal(FUSE, w.tick - placed_at)
  end)

  it("🧨 is not placed with an angle or a power out of bounds, and not spent", function()
    local w = field({
      { team = 1, index = 1, x = 60, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 180, y = terrains.GROUND - 1 },
    })
    assert.is_true(my_turn(w, 1))
    local slot = weapons.index_of("dynamite")
    assert.is_false(place(w, { angle = 1024 }))
    assert.is_false(place(w, { power = 0 }))
    assert.are.same({ "aiming", 0, 1 }, { w.turn.state, #w.projectiles, w.teams[1].ammo[slot] })
  end)

  it("⏱️ a blob hurt during the retreat ends it, and the turn waits for the fuse", function()
    local w = field({
      { team = 1, index = 1, x = 94, y = terrains.GROUND - 71 },
      { team = 2, index = 1, x = 180, y = terrains.GROUND - 1 },
    }, terrains.cliff(70))
    assert.is_true(my_turn(w, 1))
    local placed_at = w.tick
    assert.is_true(place(w))
    world.step(w, { { team = 1, kind = "move", direction = 1 } })
    while w.turn.state == "retreat" and w.tick - placed_at < FUSE do
      world.step(w)
    end
    assert.is_true(w.cats[1].hp < rules.CAT_HP, "unhurt")
    assert.are.equal("settling", w.turn.state)
    assert.is_true(w.tick - placed_at < FUSE - 30, "hurt at " .. w.tick - placed_at)
    local blast = nil
    while blast == nil and w.tick - placed_at < FUSE + 5 do
      assert.are.equal("settling", w.turn.state)
      blast = find(world.step(w), "exploded")
    end
    assert.are.equal(FUSE, w.tick - placed_at)
  end)

  it("🧨 fills the gauge: a blob that walked its gauge dry can still walk away", function()
    local w = field({
      { team = 1, index = 1, x = 40, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 380, y = terrains.GROUND - 1 },
    }, terrains.flat(400))
    assert.is_true(my_turn(w, 1))
    local blob = w.cats[1]
    world.step(w, { { team = 1, kind = "move", direction = 1 } })
    for _ = 1, 400 do
      world.step(w)
    end
    assert.is_true(blob.gauge < 20, "gauge " .. blob.gauge)
    local start_x = cat.pixel(blob)
    assert.is_true(place(w))
    assert.are.equal(rules.GAUGE, blob.gauge)
    world.step(w, { { team = 1, kind = "move", direction = -1 } })
    for _ = 1, FUSE do
      world.step(w)
    end
    assert.is_true(start_x - cat.pixel(blob) >= 60, "walked " .. start_x - cat.pixel(blob))
    assert.are.equal(rules.CAT_HP, blob.hp)
  end)

  it("⏱️ goes from aiming straight to the retreat, whose timer counts down the fuse", function()
    local w = field({
      { team = 1, index = 1, x = 60, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 180, y = terrains.GROUND - 1 },
    })
    assert.is_true(my_turn(w, 1))
    world.step(w, { { team = 1, kind = "move", direction = 1 } })
    assert.are.equal(1, w.cats[1].walk)
    assert.is_true(place(w))
    assert.are.equal(0, w.cats[1].walk)
    assert.are.same({ "retreat", FUSE - 1 }, { w.turn.state, w.turn.timer })
    assert.is_true(turn.accepts(w, "move") and turn.accepts(w, "jump"))
    assert.is_false(turn.accepts(w, "fire"))
  end)
end)

local rules = require("shared.sim.rules")
local terrain = require("shared.sim.terrain")
local terrains = require("spec.support.terrains")
local turn = require("shared.sim.turn")
local weapons = require("shared.sim.weapons.registry")
local world = require("shared.sim.world")

local TIMER = 10 * rules.TICKS_PER_SECOND
local G = terrains.GROUND

local function air(t, x0, x1, y0, y1)
  for y = y0, y1 do
    for x = x0, x1 do
      terrain.set(t, x, y, terrain.AIR)
    end
  end
  return t
end

local function soil(t, x0, x1, y0, y1)
  for y = y0, y1 do
    for x = x0, x1 do
      terrain.set(t, x, y, terrain.SOIL)
    end
  end
  return t
end

local function field(spawns, t)
  return world.from_terrain({
    terrain = t or terrains.flat(300),
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

local FIRE = { team = 1, kind = "fire", weapon = "waddler", angle = 0, power = 1 }

local function placed(t, x, facing, stock, enemy)
  local w = field({
    { team = 1, index = 1, x = x, y = terrains.GROUND - 1 },
    { team = 2, index = 1, x = enemy or 10, y = terrains.GROUND - 1 },
  }, t)
  assert.is_true(my_turn(w, 1))
  if facing then
    world.step(w, {
      { team = 1, kind = "move", direction = facing },
      { team = 1, kind = "move", direction = 0 },
    })
  end
  w.teams[1].ammo[weapons.index_of("waddler")] = stock or 1
  local events = world.step(w, { FIRE })
  assert.are.same({ "fired", "waddler" }, { events[1].type, events[1].weapon })
  return w, w.projectiles[1]
end

local function pixel(p)
  return math.floor(p.x / 256), math.floor(p.y / 256)
end

local function find(events, kind)
  for _, e in ipairs(events) do
    if e.type == kind then
      return e
    end
  end
  return nil
end

describe("🐑 the Waddler (§8.1, §8.2)", function()
  it("🐑 uses §8.2's figures", function()
    local d = weapons.get("waddler")
    assert.are.same({
      kind = "walker",
      aim = "none",
      timer = 10,
      trigger = true,
      explosion = { carve = 16, radius = 24, damage = 70, push = 2048 },
      ammo = 0,
    }, {
      kind = d.kind,
      aim = d.aim,
      timer = d.timer,
      trigger = d.trigger,
      explosion = d.explosion,
      ammo = rules.AMMO.waddler,
    })
    assert.are.same(
      { 4, 24, 256, -512 },
      { rules.WADDLER_HEIGHT, rules.WADDLER_HOP_TICKS, rules.WADDLER_HOP_VX, rules.WADDLER_HOP_VY }
    )
    assert.is_true(weapons.ends_turn("waddler"))
  end)

  it(
    "🐑 placed at its feet, walks off alone a column a tick, through a blob, the turn in flight",
    function()
      local w, p = placed(terrains.flat(300), 60, 1, 1, 70)
      local slot = weapons.index_of("waddler")
      assert.are.same({ "flight", 1, 0 }, { w.turn.state, p.facing, w.teams[1].ammo[slot] })
      local x0 = pixel(p)
      for _ = 1, 20 do
        world.step(w)
      end
      local x, y = pixel(p)
      assert.are.same({ x0 + 20, terrains.GROUND - 1 }, { x, y })
      assert.are.same({ rules.CAT_HP, "flight" }, { w.cats[2].hp, w.turn.state })
    end
  )

  it("🐑 climbs a 3 px step, and turns back from a wall", function()
    local ws, ps = placed(terrains.stairs(3), 92, 1)
    for _ = 1, 20 do
      world.step(ws)
    end
    local x, y = pixel(ps)
    assert.are.same({ true, terrains.GROUND - 4 }, { x > 100, y })
    local ww, pw = placed(terrains.wall(4, 20), 110, 1)
    for _ = 1, 20 do
      world.step(ww)
    end
    assert.are.equal(-1, pw.facing)
    assert.is_true(pixel(pw) < 119, "against the wall at " .. pixel(pw))
  end)

  it("🐑 hops every 24 ticks on the ground, and lands to walk on", function()
    local w, p = placed(terrains.flat(300), 60, 1)
    local hops = 0
    for _ = 1, 70 do
      local before = p.vy
      world.step(w)
      if before == 0 and p.vy < 0 then
        hops = hops + 1
        assert.are.equal(0, p.age % 24)
      end
    end
    assert.are.equal(2, hops)
  end)

  it("🐑 walks the mirror path facing the other way", function()
    local wr, right = placed(terrains.flat(300), 100, 1)
    local wl, left = placed(terrains.flat(300), 200, -1)
    for _ = 1, 60 do
      world.step(wr)
      world.step(wl)
      local rx, ry = pixel(right)
      local lx, ly = pixel(left)
      assert.are.same({ 299 - rx, ry }, { lx, ly })
    end
  end)

  it(
    "🐑 Fire while it walks sets it off at once, spending nothing, then comes the retreat",
    function()
      local w, p = placed(terrains.flat(300), 60, 1, 1)
      for _ = 1, 40 do
        world.step(w)
      end
      assert.is_true(turn.accepts(w, "fire"))
      local x = pixel(p)
      local blast = find(world.step(w, { FIRE }), "exploded")
      assert.are.same({ x, 16 }, { blast and blast.x, blast and blast.radius })
      assert.are.same({ 0, 0 }, { #w.projectiles, w.teams[1].ammo[weapons.index_of("waddler")] })
      world.step(w)
      assert.are.equal("retreat", w.turn.state)
      assert.is_false(turn.accepts(w, "fire"))
    end
  )

  it("🐑 left alone, it goes off by itself 10 s after it was placed", function()
    local w = placed(terrains.flat(600), 100, 1)
    local placed_at = w.tick - 1
    local blast = nil
    while blast == nil and w.tick - placed_at <= TIMER + 2 do
      blast = find(world.step(w), "exploded")
    end
    assert.are.equal(TIMER, w.tick - placed_at)
  end)

  it("🐑 walked into the water, it is gone without a blast", function()
    local w, p = placed(terrains.shore(), 90, 1)
    local blasts = 0
    while w.turn.state == "flight" do
      if find(world.step(w), "exploded") then
        blasts = blasts + 1
      end
      assert.is_true(w.tick < 2000)
    end
    assert.are.same({ 0, false, "retreat" }, { blasts, p.alive, w.turn.state })
  end)

  it("🐑 in flight, Fire with nothing to set off is not accepted", function()
    local w = field({
      { team = 1, index = 1, x = 60, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 200, y = terrains.GROUND - 1 },
    })
    assert.is_true(my_turn(w, 1))
    world.step(w, { { team = 1, kind = "fire", weapon = "bazooka", angle = 200, power = 80 } })
    assert.are.equal("flight", w.turn.state)
    assert.is_false(turn.accepts(w, "fire"))
    world.step(w, { FIRE })
    for _, p in ipairs(w.projectiles) do
      assert.are.equal("bazooka", p.weapon)
    end
  end)
end)

describe("🐑 the Waddler, at the edges (§8.1)", function()
  it("🐑 Fire sets it off exactly where it stands", function()
    local w, p = placed(terrains.flat(300), 60)
    for _ = 1, 10 do
      world.step(w)
    end
    local x, y = pixel(p)
    local blast = find(world.step(w, { FIRE }), "exploded")
    assert.are.same({ x, y }, { blast.x, blast.y })
  end)

  it("🐑 a 4 px body does not fit under a 3 px gap: it turns back", function()
    local w, p = placed(soil(terrains.flat(), 70, 199, G - 6, G - 4), 60)
    for _ = 1, 20 do
      world.step(w)
    end
    assert.are.equal(-1, p.facing)
    assert.is_true(pixel(p) < 70)
  end)

  it("🐑 walks down a 3 px step without losing a tick", function()
    local w, p = placed(air(terrains.flat(), 100, 199, G, G + 2), 92)
    local x0 = pixel(p)
    for _ = 1, 20 do
      world.step(w)
    end
    assert.are.same({ x0 + 20, G + 2 }, { pixel(p) })
  end)

  it("🐑 a hop into a wall sends it back, turned, through the air", function()
    local w, p = placed(terrains.wall(4, 20), 92)
    local bumped = nil
    while p.age < 60 do
      world.step(w)
      if bumped == nil and p.facing == -1 then
        bumped = { pixel(p) }
        bumped.age = p.age
      end
    end
    assert.is_not_nil(bumped)
    assert.is_true(p.vy == 0 or p.age > 50)
    assert.are.equal(-1, p.facing)
    assert.is_true(pixel(p) <= bumped[1] - (p.age - bumped.age) + 2, "x " .. pixel(p))
  end)

  it("🐑 a hop under a low roof keeps going forward", function()
    local w, p = placed(soil(terrains.flat(), 70, 140, G - 7, G - 6), 60)
    local x0 = pixel(p)
    for _ = 1, 30 do
      world.step(w)
    end
    assert.are.same({ x0 + 30, G - 1 }, { pixel(p) })
  end)

  it("🐑 a hop into a lip lower than its head bounces off", function()
    local w, p = placed(soil(terrains.flat(), 100, 199, G - 5, G - 3), 76)
    while p.age < 24 do
      world.step(w)
    end
    assert.are.same({ 99, -1 }, { pixel(p), p.facing })
  end)

  it("🐑 dropped from a jump, it falls straight, lands on a whole pixel, then walks", function()
    for airborne = 3, 12 do
      local w = field({
        { team = 1, index = 1, x = 60, y = G - 1 },
        { team = 2, index = 1, x = 10, y = G - 1 },
      }, terrains.flat(300))
      assert.is_true(my_turn(w, 1))
      w.teams[1].ammo[weapons.index_of("waddler")] = 1
      world.step(w, { { team = 1, kind = "jump", direction = 1 } })
      for _ = 1, airborne do
        world.step(w)
      end
      world.step(w, { FIRE })
      local p = w.projectiles[1]
      local landed = false
      while p.age < 70 do
        local x, vy = pixel(p), p.vy
        world.step(w)
        if not landed then
          assert.are.equal(x, pixel(p), "moved sideways in the air, airborne " .. airborne)
        end
        if vy > 0 and p.vy == 0 then
          landed = true
          assert.are.equal(0, p.y % 256, "landed between two pixels, airborne " .. airborne)
        end
      end
      assert.is_true(landed)
    end
  end)
end)

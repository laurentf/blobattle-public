local rules = require("shared.sim.rules")
local terrain = require("shared.sim.terrain")
local terrains = require("spec.support.terrains")
local weapons = require("shared.sim.weapons.registry")
local world = require("shared.sim.world")

local function field(t, x)
  return world.from_terrain({
    terrain = t,
    liquid = terrains.LIQUID,
    settings = { teams = 2, cats_per_team = 1, wind_max = 0 },
    spawns = {
      { team = 1, index = 1, x = x, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 190, y = terrains.GROUND - 1 },
    },
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

local TENTACLE_UP = { team = 1, kind = "fire", weapon = "tentacle", angle = 256, power = 1 }
local G = terrains.GROUND

local function soil(t, x0, x1, y0, y1)
  for y = y0, y1 do
    for x = x0, x1 do
      terrain.set(t, x, y, terrain.SOIL)
    end
  end
  return t
end

local LIGHT = { team = 1, kind = "fire", weapon = "jetpack", angle = 0, power = 1 }

local function lit(t, x, stock)
  local w = field(t, x)
  assert.is_true(my_turn(w, 1))
  w.teams[1].ammo[weapons.index_of("jetpack")] = stock or 1
  return w, w.cats[1], world.step(w, { LIGHT })
end

local function input(kind, direction)
  return { team = 1, kind = kind, direction = direction }
end

local function find(events, kind)
  for _, e in ipairs(events) do
    if e.type == kind then
      return e
    end
  end
  return nil
end

local function pixel(c)
  return math.floor(c.x / 256), math.floor(c.y / 256)
end

describe("🚀 the jetpack (§5.4, §8.2)", function()
  it("🚀 uses §5.4's figures", function()
    local j = weapons.get("jetpack")
    assert.are.same(
      { kind = "utility", aim = "none", ammo = 0 },
      { kind = j.kind, aim = j.aim, ammo = rules.AMMO.jetpack }
    )
    assert.are.same({ 150, 256, 96, 512, 32, 320 }, {
      rules.JET_FUEL,
      rules.JET_LIFT,
      rules.JET_UP,
      rules.JET_MAX_UP,
      rules.JET_SIDE,
      rules.JET_MAX_SIDE,
    })
    assert.is_true(rules.JET_MAX_SIDE < rules.THROWN_VX)
    assert.is_false(weapons.ends_turn("jetpack"))
  end)

  it("🚀 lit, it lifts the blob and keeps the turn, and costs one", function()
    local w, c, events = lit(terrains.flat(), 60, 1)
    assert.are.same({ type = "jet_started", cat = 1 }, find(events, "jet_started"))
    assert.are.same(
      { "aiming", rules.JET_FUEL, false, 0 },
      { w.turn.state, c.jet, c.grounded, w.teams[1].ammo[weapons.index_of("jetpack")] }
    )
    assert.is_true(c.vy < 0)
  end)

  it(
    "🚀 ▲ held flies the blob up a 40 px cliff, and the engine stops when it lands on top",
    function()
      local w, c = lit(terrains.cliff(40), 130, 1)
      local ended = nil
      local function go(inputs)
        ended = ended or find(world.step(w, inputs), "jet_ended")
      end
      go({ input("climb", -1), input("move", -1) })
      for _ = 1, 120 do
        if select(2, pixel(c)) < terrains.GROUND - 46 then
          break
        end
        go()
      end
      go({ input("climb", 0) })
      for _ = 1, 120 do
        if c.grounded then
          break
        end
        go()
      end
      local x, y = pixel(c)
      assert.are.same({ true, terrains.GROUND - 41 }, { x < 100, y })
      assert.are.same({ 0, rules.CAT_HP, "aiming" }, { c.jet, c.hp, w.turn.state })
      assert.are.same({ type = "jet_ended", cat = 1 }, ended)
    end
  )

  it("🚀 burns a tick of fuel per tick of thrust, 150 in all, then the blob falls", function()
    local w, c = lit(terrains.ceiling(70), 60, 1)
    world.step(w, { input("climb", -1) })
    local thrust, ended = 1, nil
    while ended == nil and thrust < 200 do
      ended = find(world.step(w), "jet_ended")
      thrust = thrust + 1
    end
    assert.are.same({ rules.JET_FUEL, 0 }, { thrust, c.jet })
    for _ = 1, 120 do
      world.step(w)
    end
    assert.are.same({ true, terrains.GROUND - 1 }, { c.grounded, select(2, pixel(c)) })
    assert.are.equal(rules.CAT_HP, c.hp)
  end)

  it("🚀 ◀ ▶ push it sideways and turn it, never fast enough to knock a blob over", function()
    local w, c = lit(terrains.flat(), 60, 1)
    world.step(w, { input("climb", -1), input("move", 1) })
    local fastest = 0
    for _ = 1, 40 do
      world.step(w)
      fastest = math.max(fastest, math.abs(c.vx))
    end
    assert.are.same({ rules.JET_MAX_SIDE, 1 }, { fastest, c.facing })
    world.step(w, { input("move", -1) })
    assert.are.equal(-1, c.facing)
  end)

  it("🚀 ◀ ▶ never brake a blob already flung faster than the engine pushes", function()
    local w, c = lit(terrains.flat(300), 60, 1)
    c.vx = 1000
    world.step(w, { input("move", 1) })
    assert.are.equal(1000, c.vx)
    world.step(w, { input("move", -1) })
    assert.are.equal(1000 - rules.JET_SIDE, c.vx)
  end)

  it("🚀 a jump cuts the engine, and the blob falls back", function()
    local w, c = lit(terrains.flat(), 60, 1)
    world.step(w, { input("climb", -1) })
    for _ = 1, 4 do
      world.step(w)
    end
    local events = world.step(w, { input("jump", 1) })
    assert.are.same({ type = "jet_ended", cat = 1 }, find(events, "jet_ended"))
    assert.are.equal(0, c.jet)
    for _ = 1, 90 do
      world.step(w)
    end
    assert.are.same({ true, rules.CAT_HP }, { c.grounded, c.hp })
  end)

  it("🚀 firing a weapon, or the end of the aiming, cuts the engine", function()
    local w, c = lit(terrains.flat(), 60, 1)
    world.step(w, { input("climb", -1) })
    world.step(w, { { team = 1, kind = "fire", weapon = "bazooka", angle = 300, power = 50 } })
    assert.are.same({ 0, "flight" }, { c.jet, w.turn.state })
    local w2, c2 = lit(terrains.flat(), 60, 1)
    world.step(w2, { input("climb", -1) })
    w2.turn.timer = 2
    world.step(w2)
    world.step(w2)
    assert.are.same({ 0, "settling" }, { c2.jet, w2.turn.state })
  end)

  it(
    "🚀 already burning or hanging from the tentacle, it is refused and costs nothing",
    function()
      local w, c = lit(terrains.flat(), 60, 2)
      local slot = weapons.index_of("jetpack")
      assert.are.equal(1, w.teams[1].ammo[slot])
      assert.is_nil(find(world.step(w, { LIGHT }), "jet_started"))
      assert.are.equal(1, w.teams[1].ammo[slot])
      local w2, c2 = lit(terrains.ceiling(80), 60, 0)
      world.step(w2, { { team = 1, kind = "fire", weapon = "tentacle", angle = 256, power = 1 } })
      assert.is_true(c2.hanging)
      w2.teams[1].ammo[slot] = 1
      assert.is_nil(find(world.step(w2, { LIGHT }), "jet_started"))
      assert.are.same({ 0, 1 }, { c2.jet, w2.teams[1].ammo[slot] })
      assert.is_true(c.jet > 0)
    end
  )

  it("🚀 without the engine, ▲ does nothing to a blob that does not hang", function()
    local w, c = lit(terrains.flat(), 60, 0)
    world.step(w, { input("climb", -1) })
    for _ = 1, 10 do
      world.step(w)
    end
    assert.are.same({ 0, 0, true }, { c.jet, c.climb, c.grounded })
  end)
end)

describe("🚀 the jetpack, at the edges (§5.4)", function()
  it("🚀 throwing the tentacle while it burns cuts the engine; one jump lets go", function()
    local w, c = lit(terrains.ceiling(70), 60)
    world.step(w, { input("climb", -1) })
    for _ = 1, 3 do
      world.step(w)
    end
    local events = world.step(w, { TENTACLE_UP })
    assert.is_true(c.hanging)
    assert.are.equal(0, c.jet)
    assert.is_not_nil(find(events, "jet_ended"))
    world.step(w, { input("jump", 1) })
    assert.is_false(c.hanging)
  end)

  it("🚀 cutting the engine with ▲ held lets go of ▲", function()
    local w, c = lit(terrains.ceiling(60), 60)
    world.step(w, { input("climb", -1) })
    for _ = 1, 3 do
      world.step(w)
    end
    world.step(w, { input("jump", 1) })
    assert.are.same({ 0, 0 }, { c.jet, c.climb })
  end)

  it("🚀 a sideways push alone burns fuel too", function()
    local w, c = lit(terrains.flat(), 60)
    assert.are.equal(rules.JET_FUEL, c.jet)
    world.step(w, { input("move", 1) })
    world.step(w)
    assert.are.equal(rules.JET_FUEL - 2, c.jet)
  end)

  it("🚀 lit, the blob gets its 2 px of give in the air back", function()
    local w = field(soil(terrains.flat(), 63, 66, G - 4, G - 1), 60)
    assert.is_true(my_turn(w, 1))
    local c = w.cats[1]
    w.teams[1].ammo[weapons.index_of("jetpack")] = 1
    world.step(w, { input("move", 1), LIGHT })
    for _ = 1, 30 do
      world.step(w)
    end
    assert.is_true(pixel(c) > 63, "x " .. pixel(c))
  end)

  it("🚀 ▼ does nothing to the engine", function()
    local w, c = lit(terrains.flat(), 60)
    local vy = c.vy
    world.step(w, { input("climb", 1) })
    assert.are.same({ rules.JET_FUEL, vy + rules.GRAVITY }, { c.jet, c.vy })
  end)
end)

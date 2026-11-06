local cat = require("shared.sim.cat")
local effects = require("shared.sim.effects")
local fixed = require("shared.sim.fixed")
local projectile = require("shared.sim.projectile")
local terrain = require("shared.sim.terrain")
local terrains = require("spec.support.terrains")
local weapons = require("shared.sim.weapons.registry")

local FP = fixed.FP

local function arena(t, cats, wind)
  local env =
    { terrain = t, cats = cats or {}, liquid = terrains.LIQUID, wind = wind or 0, events = {} }
  env.api = effects.new(env)
  return env
end

local function fly(env, p, ticks)
  local weapon = weapons.get(p.weapon)
  for tick = 1, ticks do
    projectile.step(env, p, weapon)
    if not p.alive then
      return tick
    end
  end
  return nil
end

local function first(env, kind)
  for _, e in ipairs(env.events) do
    if e.type == kind then
      return e
    end
  end
  return nil
end

local function shot(fields)
  return projectile.new({
    id = 1,
    weapon = fields.weapon,
    owner = fields.owner or 0,
    x = fields.x or fields.px * FP + 128,
    y = fields.y or fields.py * FP + 128,
    vx = fields.vx,
    vy = fields.vy,
    fuse = fields.fuse,
  })
end

describe("🚀 projectiles", function()
  it("🚀 never crosses a one-pixel wall, even at full speed", function()
    local env = arena(terrains.wall(1, 40))
    local p = shot({ weapon = "bazooka", px = 20, py = 80, vx = 3072, vy = 0 })
    assert.is_not_nil(fly(env, p, 60))
    assert.are.equal(120, first(env, "exploded").x)
  end)

  it("🚀 never slips through a diagonal one-pixel wall", function()
    for _, angle in ipairs({ 120, 128, 136 }) do
      local t = terrain.new(200, 120)
      for x = 80, 160 do
        terrain.set(t, x, x - 60, terrain.SOIL)
      end
      local env = arena(t)
      local vx, vy = projectile.launch_velocity(angle, 30)
      local p = shot({ weapon = "bazooka", px = 100, py = 46, vx = vx, vy = vy })
      fly(env, p, 200)
      local boom = first(env, "exploded")
      assert.is_not_nil(boom, "slipped through at angle " .. angle)
      assert.is_true(math.abs(boom.y - (boom.x - 60)) <= 1, "exploded off the wall")
    end
  end)

  it("🚀 launches with the angle and power it is given", function()
    assert.are.same({ 0, -2304 }, { projectile.launch_velocity(256, 100) })
    assert.are.same({ 1152, 0 }, { projectile.launch_velocity(0, 50) })
    assert.are.same({ -2304, 0 }, { projectile.launch_velocity(512, 100) })
  end)

  it("🚀 mirrors a launch exactly left and right", function()
    for angle = 0, 256, 4 do
      for _, power in ipairs({ 1, 37, 64, 100 }) do
        local vx, vy = projectile.launch_velocity(angle, power)
        local mx, my = projectile.launch_velocity(512 - angle, power)
        assert.are.same({ -vx, vy }, { mx, my }, "angle " .. angle .. " power " .. power)
      end
    end
  end)

  it("🚀 mirrors a whole bouncing grenade throw", function()
    local width = 400
    local function landing(x, angle, wind)
      local env = arena(terrains.flat(width), {}, wind)
      local vx, vy = projectile.launch_velocity(angle, 55)
      local p = shot({ weapon = "grenade", x = x, y = 80 * FP + 77, vx = vx, vy = vy, fuse = 120 })
      fly(env, p, 200)
      local boom = first(env, "exploded")
      return boom.x, boom.y
    end
    for _, angle in ipairs({ 40, 90, 150, 200, 250 }) do
      for _, wind in ipairs({ -7, 0, 7 }) do
        local x = 150 * FP + 37
        local lx, ly = landing(x, angle, wind)
        local rx, ry = landing(width * FP - 1 - x, 512 - angle, -wind)
        assert.are.same({ width - 1 - lx, ly }, { rx, ry }, "angle " .. angle .. " wind " .. wind)
      end
    end
  end)

  local function bazooka_landing(wind)
    local env = arena(terrains.flat(400), {}, wind)
    local vx, vy = projectile.launch_velocity(128, 60)
    local p = shot({ weapon = "bazooka", px = 20, py = 90, vx = vx, vy = vy })
    fly(env, p, 400)
    return first(env, "exploded").x
  end

  it("🚀 drifts the bazooka with the wind", function()
    local calm, tail, head = bazooka_landing(0), bazooka_landing(10), bazooka_landing(-10)
    assert.is_true(tail > calm and calm > head, tail .. " " .. calm .. " " .. head)
  end)

  local function grenade_rest(wind)
    local env = arena(terrains.flat(400), {}, wind)
    local vx, vy = projectile.launch_velocity(128, 60)
    local p = shot({ weapon = "grenade", px = 20, py = 90, vx = vx, vy = vy, fuse = 150 })
    fly(env, p, 400)
    return first(env, "exploded").x
  end

  it("🚀 leaves the grenade to the wind", function()
    assert.are.equal(grenade_rest(0), grenade_rest(10))
  end)

  it("🚀 bounces the grenade and blows it up exactly on its fuse", function()
    local env = arena(terrains.flat())
    local p = shot({ weapon = "grenade", px = 40, py = 80, vx = 400, vy = 0, fuse = 90 })
    assert.are.equal(90, fly(env, p, 200))
    assert.is_not_nil(first(env, "bounced"))
    assert.is_not_nil(first(env, "exploded"))
  end)

  it("🚀 lets a grenade come to rest, and fall again when its ground is carved", function()
    local t = terrains.flat()
    local env = arena(t)
    local p = shot({ weapon = "grenade", px = 40, py = 90, vx = 300, vy = 0, fuse = 250 })
    fly(env, p, 140)
    assert.is_true(p.resting)
    assert.are.same({ 0, 0 }, { p.vx, p.vy })
    local _, py = fixed.div(p.x, FP), fixed.div(p.y, FP)
    terrain.carve(t, fixed.div(p.x, FP), py + 6, 5)
    fly(env, p, 3)
    assert.is_false(p.resting)
    assert.is_true(fixed.div(p.y, FP) > py)
  end)

  it("🚀 lets a grenade fly through cats", function()
    local target = cat.new({ id = 2, team = 2, index = 1, px = 70, py = terrains.GROUND - 1 })
    local env = arena(terrains.flat(), { target })
    local p =
      shot({ weapon = "grenade", px = 60, py = terrains.GROUND - 4, vx = 768, vy = 0, fuse = 90 })
    fly(env, p, 8)
    assert.is_true(fixed.div(p.x, FP) > 72, "stopped at " .. fixed.div(p.x, FP))
    assert.is_true(p.alive)
    assert.is_nil(first(env, "exploded"))
  end)

  it("🚀 vanishes in the liquid without exploding", function()
    local env = arena(terrains.shore())
    local p = shot({ weapon = "bazooka", px = 150, py = 50, vx = 0, vy = 512 })
    assert.is_not_nil(fly(env, p, 120))
    assert.is_nil(first(env, "exploded"))
    assert.is_not_nil(first(env, "vanished"))
  end)

  it("🚀 vanishes 64 px beyond a side of the map", function()
    local env = arena(terrains.flat())
    local p = shot({ weapon = "bazooka", px = 190, py = 10, vx = 1024, vy = -1024 })
    assert.is_not_nil(fly(env, p, 120))
    assert.is_nil(first(env, "exploded"))
    local gone = first(env, "vanished")
    assert.are.equal(terrains.WIDTH + 64, gone.x)
  end)

  it("🚀 hits a cat, but not its own shooter during exactly 6 ticks", function()
    local shooter = cat.new({ id = 1, team = 1, index = 1, px = 30, py = terrains.GROUND - 1 })
    local target = cat.new({ id = 2, team = 2, index = 1, px = 70, py = terrains.GROUND - 1 })
    local env = arena(terrains.flat(), { shooter, target })
    local px, py = cat.pixel(shooter)
    local p = shot({ weapon = "bazooka", owner = 1, px = px, py = py - 3, vx = 2048, vy = 0 })
    fly(env, p, 60)
    local boom = first(env, "exploded")
    assert.is_true(boom.x >= 67 and boom.x <= 70, "exploded at " .. boom.x)
    assert.is_true(target.hp < 100)

    local lonely = cat.new({ id = 1, team = 1, index = 1, px = 30, py = terrains.GROUND - 1 })
    local env2 = arena(terrains.flat(), { lonely })
    local slow = shot({ weapon = "bazooka", owner = 1, px = 28, py = py - 5, vx = 16, vy = -60 })
    assert.are.equal(7, fly(env2, slow, 30))
  end)
end)

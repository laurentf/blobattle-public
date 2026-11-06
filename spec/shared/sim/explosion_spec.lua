local cat = require("shared.sim.cat")
local explosion = require("shared.sim.explosion")
local terrain = require("shared.sim.terrain")
local terrains = require("spec.support.terrains")

local SPEC = { carve = 12, radius = 16, damage = 50, push = 1280 }

local function env_with(t, cats)
  return { terrain = t, cats = cats, liquid = terrains.LIQUID, wind = 0, events = {} }
end

local function cat_at(id, px)
  local c = cat.new({ id = id, team = 1, index = id, px = px, py = terrains.GROUND - 1 })
  c.grounded = true
  return c
end

local function blast(x, y)
  return { x = x, y = y, spec = SPEC }
end

describe("💥 explosions", function()
  it("💥 deals nearly full damage beside the box centre and nothing beyond the radius", function()
    local c = cat_at(1, 50)
    local px, py = cat.pixel(c)
    local beside = explosion.effect(c, blast(px, py - 3))
    assert.are.equal(48, beside.damage)
    assert.is_nil(explosion.effect(c, blast(px + 16, py - 3)))
    assert.is_nil(explosion.effect(c, blast(px - 17, py - 3)))
  end)

  it("💥 hits a box the same from either side, pixel for pixel", function()
    local c = cat_at(1, 50)
    local px, py = cat.pixel(c)
    for d = 0, 16 do
      for dy = -6, 6, 2 do
        local left = explosion.effect(c, blast(px - 1 - d, py - 3 + dy))
        local right = explosion.effect(c, blast(px + d, py - 3 + dy))
        if left == nil then
          assert.is_nil(right, "offset " .. d)
        else
          assert.are.same({ -left.vx, left.vy, left.damage }, { right.vx, right.vy, right.damage })
        end
      end
    end
  end)

  it("💥 pushes away from the blast, always at least a little upwards", function()
    local c = cat_at(1, 50)
    local px, py = cat.pixel(c)
    local from_left = explosion.effect(c, blast(px - 5, py - 3))
    assert.is_true(from_left.vx > 0)
    assert.is_true(from_left.vy <= -64)
    local from_right = explosion.effect(c, blast(px + 4, py - 3))
    assert.is_true(from_right.vx < 0)
    local from_below = explosion.effect(c, blast(px, py + 6))
    assert.is_true(from_below.vy < -64)
  end)

  it("💥 carves, hurts, pushes and reports", function()
    local t = terrains.flat()
    local near, far = cat_at(1, 50), cat_at(2, 150)
    local env = env_with(t, { near, far })
    explosion.apply(env, blast(52, terrains.GROUND))
    assert.is_false(terrain.solid(t, 52, terrains.GROUND + 5))
    assert.is_true(near.hp < 100 and near.hurt and not near.grounded)
    assert.are.equal(100, far.hp)
    assert.is_true(far.grounded)
    assert.are.equal("exploded", env.events[1].type)
    assert.are.equal("damaged", env.events[2].type)
    assert.are.equal("explosion", env.events[2].cause)
  end)

  it("💥 lets a hanging blob go before it pushes it", function()
    local t = terrains.flat()
    for x = 0, t.width - 1 do
      for y = 36, 40 do
        terrain.set(t, x, y, terrain.SOIL)
      end
    end
    local c = cat_at(1, 50)
    local env = env_with(t, { c })
    assert.is_true(cat.grapple(c, { terrain = t, angle = 256, events = env.events }))
    assert.is_true(c.hanging)
    local px, py = cat.pixel(c)
    explosion.apply(env, blast(px + 4, py))
    assert.is_false(c.hanging)
    assert.is_true(c.vx < 0 and c.vy < 0)
    local kinds = {}
    for _, e in ipairs(env.events) do
      kinds[#kinds + 1] = e.type
    end
    assert.are.same({ "tentacle_hooked", "exploded", "damaged", "tentacle_released" }, kinds)
  end)

  it("💥 spares nobody, the dead excepted", function()
    local c = cat_at(1, 50)
    local dead = cat_at(2, 51)
    dead.alive = false
    local env = env_with(terrains.flat(), { c, dead })
    local px, py = cat.pixel(c)
    explosion.apply(env, blast(px, py - 3))
    assert.are.equal(52, c.hp)
    assert.are.equal(100, dead.hp)
  end)
end)

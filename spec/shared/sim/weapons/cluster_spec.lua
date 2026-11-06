local effects = require("shared.sim.effects")
local projectile = require("shared.sim.projectile")
local rules = require("shared.sim.rules")
local terrains = require("spec.support.terrains")
local weapons = require("shared.sim.weapons.registry")
local world = require("shared.sim.world")

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

local function sandbox(t)
  local env = { terrain = t, cats = {}, liquid = terrains.HEIGHT, wind = 0, events = {} }
  local list = {}
  env.spawn = function(fields)
    local p = projectile.new({
      id = #list + 1,
      weapon = fields.weapon,
      owner = fields.owner,
      x = fields.x,
      y = fields.y,
      vx = fields.vx,
      vy = fields.vy,
      fuse = fields.fuse,
    })
    list[#list + 1] = p
    return p
  end
  env.api = effects.new(env)
  return env, list
end

local function blasts(events)
  local out = {}
  for _, e in ipairs(events) do
    if e.type == "exploded" then
      out[#out + 1] = e
    end
  end
  return out
end

describe("🍇 the cluster (§8.2)", function()
  it("🍇 uses §8.2's figures, and so do its mini-blobs", function()
    local c, bit = weapons.get("cluster"), weapons.get("cluster_bit")
    assert.are.same({
      kind = "projectile",
      aim = "angle_power",
      fuse = { min = 1, max = 5, default = 3 },
      wind = 0,
      bounce = { restitution = 55, friction = 80 },
      explosion = { carve = 12, radius = 16, damage = 40, push = 1280 },
      ammo = 0,
    }, {
      kind = c.kind,
      aim = c.aim,
      fuse = c.fuse,
      wind = c.wind_percent,
      bounce = c.bounce,
      explosion = c.explosion,
      ammo = rules.AMMO.cluster,
    })
    assert.are.same({
      kind = "part",
      wind = 0,
      bounce = nil,
      explosion = { carve = 8, radius = 12, damage = 25, push = 1024 },
    }, {
      kind = bit.kind,
      wind = bit.wind_percent,
      bounce = bit.bounce,
      explosion = bit.explosion,
    })
    assert.are.same({
      { -512, -896 },
      { -256, -1024 },
      { 0, -1152 },
      { 256, -1024 },
      { 512, -896 },
    }, rules.CLUSTER_BITS)
    assert.is_true(weapons.ends_turn("cluster"))
  end)

  it(
    "🍇 goes off at its fuse, then its five mini-blobs dig five craters, mirrored to a pixel",
    function()
      local env, list = sandbox(terrains.flat())
      env.spawn({
        weapon = "cluster",
        owner = 1,
        x = 100 * 256 + 128,
        y = (terrains.GROUND - 1) * 256,
        vx = 0,
        vy = 0,
        fuse = 1,
      })
      for _ = 1, 600 do
        for i = 1, #list do
          projectile.step(env, list[i], weapons.get(list[i].weapon))
        end
      end
      for _, p in ipairs(list) do
        assert.is_false(p.alive, p.weapon)
      end
      local all = blasts(env.events)
      assert.are.equal(6, #all)
      assert.are.same({ 100, terrains.GROUND - 1, 12 }, { all[1].x, all[1].y, all[1].radius })
      local offsets = {}
      for i = 2, 6 do
        assert.are.equal(8, all[i].radius)
        offsets[#offsets + 1] = all[i].x - 100
      end
      table.sort(offsets)
      local spread = table.concat(offsets, " ")
      assert.are.equal(0, offsets[3], spread)
      assert.is_true(offsets[4] > 20 and offsets[5] > offsets[4] + 20, spread)
      assert.is_true(math.abs(offsets[1] + offsets[5]) <= 1, spread)
      assert.is_true(math.abs(offsets[2] + offsets[4]) <= 1, spread)
    end
  )

  it(
    "🍇 thrown in a game, it spends one, and the turn flies until the last mini-blob is gone",
    function()
      local w = field({
        { team = 1, index = 1, x = 40, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 180, y = terrains.GROUND - 1 },
      })
      local slot = weapons.index_of("cluster")
      assert.is_true(my_turn(w, 1))
      w.teams[1].ammo[slot] = 1
      local input = {
        team = 1,
        kind = "fire",
        weapon = "cluster",
        angle = 200,
        power = 45,
        fuse = 2,
      }
      local events = world.step(w, { input })
      assert.are.equal("fired", events[1] and events[1].type)
      assert.are.same({ "flight", 0 }, { w.turn.state, w.teams[1].ammo[slot] })
      local count = 0
      while w.turn.state == "flight" do
        count = count + #blasts(world.step(w))
        assert.is_true(w.tick < 2000)
      end
      assert.are.same({ 6, "retreat" }, { count, w.turn.state })
      assert.is_true(my_turn(w, 1))
      local before = w.tick
      world.step(w, { input })
      assert.are.same({ "aiming", 0 }, { w.turn.state, #w.projectiles })
      assert.are.equal(before + 1, w.tick)
    end
  )

  it("🍇 at its fuse it is gone, and five mini-blobs leave the centre of its pixel", function()
    local w = field({
      { team = 1, index = 1, x = 40, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 180, y = terrains.GROUND - 1 },
    })
    assert.is_true(my_turn(w, 1))
    w.teams[1].ammo[weapons.index_of("cluster")] = 1
    world.step(w, {
      { team = 1, kind = "fire", weapon = "cluster", angle = 200, power = 45, fuse = 2 },
    })
    local boom = nil
    for _ = 1, 200 do
      boom = blasts(world.step(w))[1]
      if boom then
        break
      end
    end
    assert.is_table(boom)
    assert.are.equal(5, #w.projectiles)
    for i, p in ipairs(w.projectiles) do
      assert.are.same({
        "cluster_bit",
        boom.x * 256 + 128,
        boom.y * 256 + 128,
        rules.CLUSTER_BITS[i][1],
        rules.CLUSTER_BITS[i][2],
        1,
      }, { p.weapon, p.x, p.y, p.vx, p.vy, p.owner })
    end
  end)

  it("🍇 a mini-blob or a shell is never something one fires", function()
    local w = field({
      { team = 1, index = 1, x = 40, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 180, y = terrains.GROUND - 1 },
    })
    assert.is_true(my_turn(w, 1))
    for _, id in ipairs({ "cluster_bit", "airstrike_shell" }) do
      local events = world.step(w, {
        { team = 1, kind = "fire", weapon = id, angle = 200, power = 45, target = 100 },
      })
      assert.are.same({ "aiming", 0, 0 }, { w.turn.state, #w.projectiles, #events }, id)
    end
  end)
end)

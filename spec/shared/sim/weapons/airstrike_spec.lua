local rules = require("shared.sim.rules")
local terrains = require("spec.support.terrains")
local weapons = require("shared.sim.weapons.registry")
local world = require("shared.sim.world")

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

local function strike(w, target)
  return world.step(w, {
    { team = 1, kind = "fire", weapon = "airstrike", angle = 0, power = 1, target = target },
  })
end

local function fly_out(w)
  local blasts, hurt = {}, {}
  while w.turn.state == "flight" do
    for _, e in ipairs(world.step(w)) do
      if e.type == "exploded" then
        blasts[#blasts + 1] = e
      elseif e.type == "damaged" then
        hurt[#hurt + 1] = e.cat
      end
    end
    assert.is_true(w.tick < 2000)
  end
  return blasts, hurt
end

describe("📡 the air strike (§8.2)", function()
  it("📡 uses §8.2's figures, and so do its shells", function()
    local a, shell = weapons.get("airstrike"), weapons.get("airstrike_shell")
    assert.are.same(
      { kind = "strike", aim = "target", ammo = 0 },
      { kind = a.kind, aim = a.aim, ammo = rules.AMMO.airstrike }
    )
    assert.is_function(a.on_use)
    assert.are.same({
      kind = "part",
      wind = 50,
      bounce = nil,
      explosion = { carve = 12, radius = 16, damage = 35, push = 1536 },
    }, {
      kind = shell.kind,
      wind = shell.wind_percent,
      bounce = shell.bounce,
      explosion = shell.explosion,
    })
    assert.are.same({ -24, -12, 0, 12, 24 }, rules.AIRSTRIKE_OFFSETS)
    assert.are.same({ 32, 24, 16, 24, 32 }, rules.AIRSTRIKE_ABOVE)
    assert.are.equal(768, rules.AIRSTRIKE_VY)
    assert.is_true(weapons.ends_turn("airstrike"))
  end)

  it(
    "📡 on a chosen column, five shells fall and dig five craters in a line, mirrored around it",
    function()
      local w = field({
        { team = 1, index = 1, x = 20, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 280, y = terrains.GROUND - 1 },
      })
      local slot = weapons.index_of("airstrike")
      assert.is_true(my_turn(w, 1))
      w.teams[1].ammo[slot] = 1
      local events = strike(w, 150)
      assert.are.same({ "fired", "airstrike" }, { events[1].type, events[1].weapon })
      assert.are.same({ "flight", 5, 0 }, { w.turn.state, #w.projectiles, w.teams[1].ammo[slot] })
      local blasts = fly_out(w)
      assert.are.equal(5, #blasts)
      assert.are.same({ 150, 12 }, { blasts[1].x, blasts[1].radius })
      local xs, depth = {}, {}
      for _, b in ipairs(blasts) do
        xs[#xs + 1] = b.x
        depth[b.x] = b.y
        assert.is_true(b.y >= terrains.GROUND and b.y <= terrains.GROUND + 2, b.x .. "," .. b.y)
      end
      table.sort(xs)
      assert.are.same({ 126, 138, 150, 162, 174 }, xs)
      assert.are.same({ depth[174], depth[162] }, { depth[126], depth[138] })
      assert.are.equal("retreat", w.turn.state)
    end
  )

  it("📡 its shells start where §8.2 says, falling at 768 FP a tick", function()
    local w = field({
      { team = 1, index = 1, x = 20, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 280, y = terrains.GROUND - 1 },
    })
    assert.is_true(my_turn(w, 1))
    w.teams[1].ammo[weapons.index_of("airstrike")] = 1
    strike(w, 150)
    assert.are.equal(5, #w.projectiles)
    local vy = rules.AIRSTRIKE_VY + rules.GRAVITY
    for k, p in ipairs(w.projectiles) do
      assert.are.same({
        "airstrike_shell",
        (150 + rules.AIRSTRIKE_OFFSETS[k]) * 256 + 128,
        -rules.AIRSTRIKE_ABOVE[k] * 256 + 128 + vy,
        0,
        vy,
        1,
      }, { p.weapon, p.x, p.y, p.vx, p.vy, p.owner })
    end
  end)

  it("📡 a shell that meets a blob on its way goes off on it", function()
    local w = field({
      { team = 1, index = 1, x = 20, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 150, y = terrains.GROUND - 1 },
    })
    assert.is_true(my_turn(w, 1))
    w.teams[1].ammo[weapons.index_of("airstrike")] = 1
    strike(w, 150)
    local blasts, hurt = fly_out(w)
    assert.is_true(blasts[1].y < terrains.GROUND - 1, "the first shell went off at " .. blasts[1].y)
    assert.are.equal(2, hurt[1])
  end)

  it(
    "📡 a column off the map, missing or not an integer is ignored, and costs nothing",
    function()
      local w = field({
        { team = 1, index = 1, x = 20, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 280, y = terrains.GROUND - 1 },
      })
      local slot = weapons.index_of("airstrike")
      assert.is_true(my_turn(w, 1))
      w.teams[1].ammo[slot] = 1
      for _, target in ipairs({ -1, 300, 149.5, "150", false }) do
        assert.are.same({}, strike(w, target), tostring(target))
      end
      assert.are.same({}, strike(w, nil))
      assert.are.same({ "aiming", 0, 1 }, { w.turn.state, #w.projectiles, w.teams[1].ammo[slot] })
      assert.are.equal("fired", strike(w, 299)[1].type)
    end
  )

  it("📡 without one in stock, a strike is ignored", function()
    local w = field({
      { team = 1, index = 1, x = 20, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 280, y = terrains.GROUND - 1 },
    })
    assert.is_true(my_turn(w, 1))
    assert.are.same({}, strike(w, 150))
    assert.are.same({ "aiming", 0 }, { w.turn.state, #w.projectiles })
  end)
end)

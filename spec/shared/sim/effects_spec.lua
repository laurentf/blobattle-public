local brain = require("shared.bots.brain")
local effects = require("shared.sim.effects")
local terrains = require("spec.support.terrains")
local weapons = require("shared.sim.weapons.registry")
local world = require("shared.sim.world")

local function duel()
  return world.from_terrain({
    terrain = terrains.flat(400),
    liquid = terrains.LIQUID,
    settings = { teams = 2, cats_per_team = 1, wind_max = 0 },
    spawns = {
      { team = 1, index = 1, x = 100, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 260, y = terrains.GROUND - 1 },
    },
  })
end

local function until_aiming(w)
  for _ = 1, 200 do
    if w.turn.state == "aiming" then
      return
    end
    world.step(w)
  end
end

local function with_hooks(hooks, body)
  local bazooka = weapons.get("bazooka")
  for name, hook in pairs(hooks) do
    bazooka[name] = hook
  end
  local ok, err = pcall(body)
  for name in pairs(hooks) do
    bazooka[name] = nil
  end
  assert(ok, err)
end

describe("🔫 the EffectApi (§8.1)", function()
  it("🔫 gives a hook the named explosion, removal and spawning", function()
    local api = effects.new({ events = {} })
    assert.is_function(api.explode)
    assert.is_function(api.remove_projectile)
    assert.has_error(function()
      api.spawn_projectile({})
    end)
  end)

  it("🔫 runs on_tick every tick and on_impact with the hit, through the world", function()
    local ticks, hit = 0, nil
    with_hooks({
      on_tick = function()
        ticks = ticks + 1
      end,
      on_impact = function(api, p, where)
        hit = where
        api.explode({ x = where.x, y = where.y, spec = weapons.get("bazooka").explosion })
        api.remove_projectile(p)
      end,
    }, function()
      local w = duel()
      until_aiming(w)
      world.step(w, { { team = 1, kind = "fire", weapon = "bazooka", angle = 100, power = 60 } })
      for _ = 1, 300 do
        world.step(w)
      end
    end)
    assert.is_true(ticks > 3)
    assert.is_number(hit.x)
    assert.is_number(hit.y)
  end)

  it("🔫 lets on_impact split a shell into bomblets the world then flies", function()
    local exploded = 0
    with_hooks({
      on_impact = function(api, p, where)
        for _, vx in ipairs({ -300, 300 }) do
          local bomblet = api.spawn_projectile({
            weapon = "grenade",
            owner = p.owner,
            x = where.x * 256 + 128,
            y = (where.y - 4) * 256,
            vx = vx,
            vy = -600,
            fuse = 30,
          })
          bomblet.age = 0
        end
        api.remove_projectile(p)
      end,
    }, function()
      local w = duel()
      until_aiming(w)
      world.step(w, { { team = 1, kind = "fire", weapon = "bazooka", angle = 100, power = 60 } })
      for _ = 1, 400 do
        for _, e in ipairs(world.step(w)) do
          if e.type == "exploded" then
            exploded = exploded + 1
          end
        end
      end
    end)
    assert.are.equal(2, exploded)
  end)

  it("🔫 fires on_timer with the place it went off", function()
    local at
    local grenade = weapons.get("grenade")
    grenade.on_timer = function(api, p, where)
      at = where
      api.remove_projectile(p)
    end
    local ok, err = pcall(function()
      local w = duel()
      until_aiming(w)
      world.step(
        w,
        { { team = 1, kind = "fire", weapon = "grenade", angle = 128, power = 20, fuse = 1 } }
      )
      for _ = 1, 60 do
        world.step(w)
      end
    end)
    grenade.on_timer = nil
    assert(ok, err)
    assert.is_number(at.x)
  end)

  it("🔫 lets a bot evaluate a weapon whose hook spawns projectiles", function()
    with_hooks({
      on_impact = function(api, p, where)
        local bomblet = api.spawn_projectile({
          weapon = "grenade",
          owner = p.owner,
          x = where.x * 256,
          y = where.y * 256,
          vx = 0,
          vy = 0,
          fuse = 30,
        })
        bomblet.age = 0
        api.explode({ x = where.x, y = where.y, spec = weapons.get("bazooka").explosion })
        api.remove_projectile(p)
      end,
    }, function()
      local w = duel()
      until_aiming(w)
      local bot = brain.new({ team = 1, level = "easy", seed = 2 })
      assert.has_no.errors(function()
        brain.think(bot, w, 1000000)
      end)
    end)
  end)
end)

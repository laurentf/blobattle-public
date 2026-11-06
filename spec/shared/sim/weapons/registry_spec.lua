local cat = require("shared.sim.cat")
local en = require("shared.i18n.en")
local effects = require("shared.sim.effects")
local fixed = require("shared.sim.fixed")
local projectile = require("shared.sim.projectile")
local rules = require("shared.sim.rules")
local terrain = require("shared.sim.terrain")
local terrains = require("spec.support.terrains")
local weapons = require("shared.sim.weapons.registry")

local function integer(v)
  return type(v) == "number" and fixed.mod(v, 1) == 0
end

local REFERENCE = {
  flat = function()
    return terrains.flat()
  end,
  wall = function()
    return terrains.wall(1, 60)
  end,
  well = function()
    return terrains.well(10)
  end,
}

local function sandbox(t, cats)
  local env = { terrain = t, cats = cats, liquid = terrains.LIQUID, wind = 7, events = {} }
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
      facing = fields.facing,
    })
    list[#list + 1] = p
    return p
  end
  env.api = effects.new(env)
  return env, list
end

local function run_out(env, list)
  for _ = 1, 600 do
    local alive = false
    for i = 1, #list do
      local p = list[i]
      projectile.step(env, p, weapons.get(p.weapon))
      alive = alive or p.alive
    end
    if not alive then
      return true
    end
  end
  return false
end

describe("🔫 weapon contract (D-05)", function()
  it("🔫 lists each weapon once, reachable by id", function()
    local seen = {}
    for _, weapon in ipairs(weapons.list) do
      assert.is_nil(seen[weapon.id])
      seen[weapon.id] = true
      assert.are.equal(weapon, weapons.get(weapon.id))
    end
    assert.is_nil(weapons.get("banana"))
  end)

  it(
    "🔫 keeps the parts apart: reachable by id, never in the list, never chosen (§8.1)",
    function()
      assert.is_true(#weapons.parts >= 1)
      local seen = {}
      for _, weapon in ipairs(weapons.list) do
        seen[weapon.id] = true
        assert.is_true(weapons.selectable(weapon.id), weapon.id)
      end
      for _, part in ipairs(weapons.parts) do
        assert.is_nil(seen[part.id], part.id)
        seen[part.id] = true
        assert.are.equal(part, weapons.get(part.id))
        assert.is_false(weapons.selectable(part.id), part.id)
        assert.is_nil(rules.AMMO[part.id], part.id)
      end
      assert.is_false(weapons.selectable("banana"))
      assert.is_false(weapons.selectable(nil))
    end
  )

  it("🔫 lists the weapons in the order of the grid and of the keys (§7.3)", function()
    local ids = {}
    for i, weapon in ipairs(weapons.list) do
      ids[i] = weapon.id
    end
    assert.are.same({
      "bazooka",
      "grenade",
      "tentacle",
      "uppercut",
      "chomp",
      "dynamite",
      "cluster",
      "airstrike",
      "waddler",
      "jetpack",
    }, ids)
  end)

  it("🔫 gives each weapon its position in the list", function()
    for i, weapon in ipairs(weapons.list) do
      assert.are.equal(i, weapons.index_of(weapon.id))
    end
    for j, part in ipairs(weapons.parts) do
      assert.are.equal(#weapons.list + j, weapons.index_of(part.id))
    end
    assert.is_nil(weapons.index_of("banana"))
  end)

  it(
    "🔫 draws every weapon's ammunition from rules.AMMO, never from its module (§8.1)",
    function()
      for _, weapon in ipairs(weapons.list) do
        assert.is_nil(weapon.ammo, weapon.id)
        local ammo = rules.AMMO[weapon.id]
        assert.is_true(integer(ammo) and ammo >= -1, weapon.id)
      end
      for id in pairs(rules.AMMO) do
        assert.is_not_nil(weapons.get(id), id)
      end
    end
  )

  it("🔫 knows every kind it lists", function()
    for _, weapon in ipairs(weapons.list) do
      local kind = weapon.kind
      local known = {
        projectile = true,
        utility = true,
        melee = true,
        digger = true,
        placed = true,
        strike = true,
        walker = true,
      }
      assert.is_true(known[kind], weapon.id)
    end
  end)

  it("🔫 ends the turn with every weapon but a utility", function()
    for _, weapon in ipairs(weapons.list) do
      assert.are.equal(weapon.kind ~= "utility", weapons.ends_turn(weapon.id), weapon.id)
    end
  end)

  for _, weapon in ipairs(weapons.list) do
    describe(weapon.id, function()
      it("🔫 has its name in the English catalogue", function()
        assert.is_string(en["weapon." .. weapon.id])
      end)

      if weapon.kind == "utility" then
        it("🔫 declares a valid utility shape", function()
          assert.is_true(weapon.aim == "angle" or weapon.aim == "none", weapon.aim)
          assert.is_true(integer(rules.AMMO[weapon.id]) and rules.AMMO[weapon.id] >= -1)
          assert.is_function(weapon.on_use)
          assert.is_nil(weapon.explosion)
        end)

        for name, build in pairs(REFERENCE) do
          for _, angle in ipairs({ 32, 128, 224 }) do
            it(
              "🔫 acts on its user alone on the " .. name .. " terrain at angle " .. angle,
              function()
                local t = build()
                local user =
                  cat.new({ id = 1, team = 1, index = 1, px = 60, py = terrains.GROUND - 1 })
                local env = { terrain = t, cats = { user }, liquid = terrains.LIQUID, wind = 7 }
                env.events = {}
                env.api = effects.new(env)
                local before = { terrain.cells_hash(t) }
                assert.is_true(weapon.on_use(env.api, user, { angle = angle, power = 80 }))
                assert.are.same(before, { terrain.cells_hash(t) })
                assert.is_true(#env.events >= 1)
                for _, e in ipairs(env.events) do
                  assert.are.equal(user.id, e.cat)
                end
              end
            )
          end
        end
        return
      end

      if weapon.kind == "digger" then
        it("🔫 declares a valid digger shape", function()
          assert.are.equal("angle", weapon.aim)
          assert.is_true(integer(rules.AMMO[weapon.id]) and rules.AMMO[weapon.id] >= -1)
          assert.is_function(weapon.on_use)
          assert.is_nil(weapon.explosion)
        end)

        for name, build in pairs(REFERENCE) do
          for _, angle in ipairs({ 32, 512, 768 }) do
            it(
              "🔫 sets its user alone to eat on the " .. name .. " terrain at angle " .. angle,
              function()
                local t = build()
                local feet = terrains.GROUND - 1
                local user = cat.new({ id = 1, team = 1, index = 1, px = 60, py = feet })
                local other = cat.new({ id = 2, team = 2, index = 1, px = 66, py = feet })
                local env = {
                  terrain = t,
                  cats = { user, other },
                  liquid = terrains.LIQUID,
                  wind = 7,
                }
                env.events = {}
                env.api = effects.new(env)
                local before = { terrain.cells_hash(t) }
                assert.is_true(weapon.on_use(env.api, user, { angle = angle, power = 80 }))
                assert.are.same(before, { terrain.cells_hash(t) })
                assert.are.same(
                  { rules.DIG_TICKS, angle, 0 },
                  { user.dig, user.dig_angle, other.dig }
                )
                assert.are.same({}, env.events)
              end
            )
          end
        end
        return
      end

      if weapon.kind == "melee" then
        it("🔫 declares a valid melee shape", function()
          assert.are.equal("none", weapon.aim)
          assert.is_true(integer(rules.AMMO[weapon.id]) and rules.AMMO[weapon.id] >= -1)
          assert.is_function(weapon.on_use)
          assert.is_nil(weapon.explosion)
          for _, key in ipairs({ "reach", "damage", "push_x", "push_y" }) do
            assert.is_true(integer(weapon.melee[key]) and weapon.melee[key] > 0, key)
          end
        end)

        for name, build in pairs(REFERENCE) do
          it("🔫 strikes the blob in front alone on the " .. name .. " terrain", function()
            local t = build()
            local feet = terrains.GROUND - 1
            local user = cat.new({ id = 1, team = 1, index = 1, px = 60, py = feet })
            local front =
              cat.new({ id = 2, team = 2, index = 1, px = 60 + rules.CAT_WIDTH, py = feet })
            local behind =
              cat.new({ id = 3, team = 2, index = 2, px = 60 - rules.CAT_WIDTH, py = feet })
            local env = {
              terrain = t,
              cats = { user, front, behind },
              liquid = terrains.LIQUID,
              wind = 7,
            }
            env.events = {}
            env.api = effects.new(env)
            local before = { terrain.cells_hash(t) }
            assert.is_true(weapon.on_use(env.api, user, { angle = 0, power = 1 }))
            assert.are.same(before, { terrain.cells_hash(t) })
            assert.is_true(front.hp < rules.CAT_HP and front.vy < 0)
            assert.are.same({ rules.CAT_HP, rules.CAT_HP }, { user.hp, behind.hp })
            assert.is_true(#env.events >= 1)
            for _, e in ipairs(env.events) do
              assert.are.equal(front.id, e.cat)
            end
          end)
        end
        return
      end

      if weapon.kind == "walker" then
        it("🔫 declares a valid walker shape", function()
          assert.are.equal("none", weapon.aim)
          assert.is_true(integer(rules.AMMO[weapon.id]) and rules.AMMO[weapon.id] >= -1)
          assert.is_true(integer(weapon.timer) and weapon.timer >= 1 and weapon.timer <= 20)
          for _, key in ipairs({ "carve", "radius", "damage", "push" }) do
            assert.is_true(integer(weapon.explosion[key]) and weapon.explosion[key] > 0, key)
          end
        end)

        for name, build in pairs(REFERENCE) do
          for _, facing in ipairs({ -1, 1 }) do
            it(
              "🔫 walks off on the " .. name .. " terrain facing " .. facing .. ", and ends",
              function()
                local user =
                  cat.new({ id = 1, team = 1, index = 1, px = 60, py = terrains.GROUND - 1 })
                local env, list = sandbox(build(), { user })
                local x, y = cat.feet(user)
                env.spawn({
                  weapon = weapon.id,
                  owner = 1,
                  x = x,
                  y = y,
                  vx = 0,
                  vy = 0,
                  fuse = weapon.timer * rules.TICKS_PER_SECOND,
                  facing = facing,
                })
                assert.is_true(run_out(env, list), "still in play after 600 ticks")
              end
            )
          end
        end
        return
      end

      if weapon.kind == "strike" then
        it("🔫 declares a valid strike shape", function()
          assert.are.equal("target", weapon.aim)
          assert.is_true(integer(rules.AMMO[weapon.id]) and rules.AMMO[weapon.id] >= -1)
          assert.is_function(weapon.on_use)
          assert.is_nil(weapon.explosion)
        end)

        for name, build in pairs(REFERENCE) do
          it(
            "🔫 drops shells on the " .. name .. " terrain, and every one of them ends",
            function()
              local t = build()
              local user =
                cat.new({ id = 1, team = 1, index = 1, px = 60, py = terrains.GROUND - 1 })
              local env, list = sandbox(t, { user })
              assert.is_true(weapon.on_use(env.api, user, { angle = 0, power = 1, target = 120 }))
              assert.is_true(#list >= 1)
              assert.is_true(run_out(env, list), "still in play after 600 ticks")
            end
          )
        end
        return
      end

      if weapon.kind == "placed" then
        it("🔫 declares a valid placed shape", function()
          assert.are.equal("none", weapon.aim)
          assert.is_true(integer(rules.AMMO[weapon.id]) and rules.AMMO[weapon.id] >= -1)
          assert.is_true(integer(weapon.timer) and weapon.timer >= 1 and weapon.timer <= 10)
          assert.is_true(integer(weapon.wind_percent))
          assert.is_true(integer(weapon.bounce.restitution) and integer(weapon.bounce.friction))
          for _, key in ipairs({ "carve", "radius", "damage", "push" }) do
            assert.is_true(integer(weapon.explosion[key]) and weapon.explosion[key] > 0, key)
          end
        end)

        for name, build in pairs(REFERENCE) do
          it(
            "🔫 placed on the " .. name .. " terrain, rests, then goes off with its timer",
            function()
              local t = build()
              local user =
                cat.new({ id = 1, team = 1, index = 1, px = 60, py = terrains.GROUND - 1 })
              local env = { terrain = t, cats = { user }, liquid = terrains.LIQUID, wind = 7 }
              env.events = {}
              env.api = effects.new(env)
              local x, y = cat.feet(user)
              local p = projectile.new({
                id = 1,
                weapon = weapon.id,
                owner = 1,
                x = x,
                y = y,
                vx = 0,
                vy = 0,
                fuse = weapon.timer * rules.TICKS_PER_SECOND,
              })
              local rested, ticks = false, 0
              while p.alive and ticks < 1000 do
                projectile.step(env, p, weapon)
                ticks = ticks + 1
                rested = rested or p.resting
              end
              assert.are.same({ true, weapon.timer * rules.TICKS_PER_SECOND }, { rested, ticks })
              local exploded = false
              for _, e in ipairs(env.events) do
                exploded = exploded or e.type == "exploded"
              end
              assert.is_true(exploded)
            end
          )
        end
        return
      end

      it("🔫 declares a valid shape", function()
        assert.are.equal("projectile", weapon.kind)
        assert.are.equal("angle_power", weapon.aim)
        assert.is_true(integer(rules.AMMO[weapon.id]) and rules.AMMO[weapon.id] >= -1)
        assert.is_true(integer(weapon.wind_percent))
        assert.is_true(weapon.wind_percent >= 0 and weapon.wind_percent <= 100)
        for _, key in ipairs({ "carve", "radius", "damage", "push" }) do
          assert.is_true(integer(weapon.explosion[key]) and weapon.explosion[key] > 0, key)
        end
        if weapon.fuse then
          assert.is_true(weapon.fuse.min >= 1 and weapon.fuse.max <= 5)
          assert.is_true(weapon.fuse.default >= weapon.fuse.min)
          assert.is_true(weapon.fuse.default <= weapon.fuse.max)
        end
        if weapon.bounce then
          assert.is_true(integer(weapon.bounce.restitution) and integer(weapon.bounce.friction))
        end
      end)

      for name, build in pairs(REFERENCE) do
        for _, angle in ipairs({ 32, 128, 224 }) do
          it(
            "🔫 fires, flies and ends on the " .. name .. " terrain at angle " .. angle,
            function()
              local t = build()
              local shooter =
                cat.new({ id = 1, team = 1, index = 1, px = 60, py = terrains.GROUND - 1 })
              local env, list = sandbox(t, { shooter })
              local cx, cy = cat.center(shooter)
              local vx, vy = projectile.launch_velocity(angle, 80)
              local fuse = weapon.fuse and weapon.fuse.max * 30 or -1
              env.spawn({
                weapon = weapon.id,
                owner = 1,
                x = cx * 256 + 128,
                y = cy * 256 + 128,
                vx = vx,
                vy = vy,
                fuse = fuse,
              })
              assert.is_true(run_out(env, list), "still in play after 600 ticks")
            end
          )
        end
      end
    end)
  end
  for _, part in ipairs(weapons.parts) do
    describe(part.id, function()
      it("🔫 declares a valid part shape", function()
        assert.are.equal("part", part.kind)
        assert.is_nil(part.aim)
        assert.is_true(integer(part.wind_percent))
        assert.is_true(part.wind_percent >= 0 and part.wind_percent <= 100)
        for _, key in ipairs({ "carve", "radius", "damage", "push" }) do
          assert.is_true(integer(part.explosion[key]) and part.explosion[key] > 0, key)
        end
      end)

      for name, build in pairs(REFERENCE) do
        it("🔫 falls and ends on the " .. name .. " terrain", function()
          local env, list = sandbox(build(), {})
          env.spawn({
            weapon = part.id,
            owner = 1,
            x = 60 * 256 + 128,
            y = 20 * 256,
            vx = 256,
            vy = 0,
          })
          assert.is_true(run_out(env, list), "still in play after 600 ticks")
        end)
      end
    end)
  end
end)

local rules = require("shared.sim.rules")
local trig = require("shared.sim.trig")
local weapons = require("shared.sim.weapons.registry")
local rng = require("shared.sim.rng")
local hash = require("shared.sim.hash")
local fixed = require("shared.sim.fixed")

local LIMIT = rules.MAX_MAGNITUDE

local function below_limit(name, value)
  assert.is_true(value < LIMIT, name .. " reaches " .. value)
end

describe("📏 magnitude bounds (D-02)", function()
  it("📏 sets the limit at 2^50", function()
    assert.are.equal(1125899906842624, LIMIT)
  end)

  it("📏 keeps velocity decomposition under the limit", function()
    below_limit("speed × trig", rules.MAX_AXIS_SPEED * trig.SCALE)
    below_limit("rounded speed × trig", rules.MAX_AXIS_SPEED * trig.SCALE + trig.SCALE)
    below_limit("launch × trig", rules.LAUNCH_MAX_SPEED * rules.POWER_MAX * trig.SCALE)
  end)

  it("📏 keeps positions and squared distances under the limit", function()
    local extent = rules.MAP_WIDTH_MAX + 2 * rules.OUT_MARGIN
    below_limit("position", extent * fixed.FP)
    below_limit("squared distance in px", 2 * extent * extent)
    below_limit("squared distance in FP", 2 * extent * extent * fixed.FP * fixed.FP)
  end)

  it("📏 keeps the generator and the hash exact", function()
    for name, spec in pairs(rng.STREAMS) do
      below_limit("rng product " .. name, (rng.MODULUS - 1) * spec.multiplier)
      below_limit("rng seed offset " .. name, rng.MAX_SEED + spec.offset)
    end
    for _, multiplier in ipairs(hash.MULTIPLIERS) do
      below_limit("hash step", (hash.MODULUS - 1) * multiplier + hash.MODULUS)
    end
  end)

  it("📏 keeps the map noise under the limit", function()
    for _, octaves in ipairs({ rules.SURFACE_OCTAVES, rules.CAVE_OCTAVES }) do
      local weights = 0
      for _, octave in ipairs(octaves) do
        local span = octave.span
        below_limit("smoothstep", rules.NOISE_MAX * span * span * (3 * span))
        weights = weights + octave.weight
      end
      below_limit("weighted noise", rules.NOISE_MAX * weights)
    end
    below_limit("surface scaling", rules.MAP_HEIGHT * rules.NOISE_MAX)
  end)

  it("📏 keeps every weapon's arithmetic under the limit", function()
    local normal = 2 * (1 + 2) * 5
    for _, weapon in ipairs(weapons.list) do
      local e = weapon.explosion or { damage = 0, radius = 0, push = 0 }
      below_limit(weapon.id .. " damage", e.damage * e.radius)
      below_limit(weapon.id .. " push", e.push * e.radius * 2 * e.radius)
      below_limit(weapon.id .. " wind", 10 * rules.WIND_ACCEL * (weapon.wind_percent or 0))
      if weapon.bounce then
        local dot = 2 * rules.MAX_AXIS_SPEED * normal
        below_limit(weapon.id .. " bounce", dot * normal)
        below_limit(weapon.id .. " restitution", rules.MAX_AXIS_SPEED * 2 * 100)
      end
    end
  end)

  it("📏 keeps the Chomp's arithmetic under the limit", function()
    below_limit("meal", rules.DIG_TICKS * rules.DIG_PIXELS * fixed.FP * trig.SCALE)
  end)

  it("📏 keeps the tentacle's arithmetic under the limit", function()
    local rope = rules.ROPE_MAX * fixed.FP
    local reach = rope + 2 * rules.MAX_AXIS_SPEED + 2 * fixed.FP
    below_limit("cast", rules.TENTACLE_RANGE * fixed.FP * trig.SCALE)
    below_limit("squared reach", 2 * reach * reach)
    below_limit("projection", reach * rope)
    below_limit("push", rules.SWING_PUSH * reach)
    below_limit("slack", 2 * rules.MAX_AXIS_SPEED * reach * reach)
    below_limit("bounce", rules.MAX_AXIS_SPEED * rules.ROPE_BOUNCE)
    below_limit("travel", 2 * rules.MAX_AXIS_SPEED * (2 * rules.MAX_AXIS_SPEED + fixed.FP))
  end)

  it("📏 keeps fall damage under the limit", function()
    below_limit(
      "fall damage",
      (rules.MAX_AXIS_SPEED - rules.FALL_SAFE_SPEED) * rules.FALL_DAMAGE_PER_256
    )
  end)

  it("📦 counts each weapon's ammunition per team and per game in one table (§8.2)", function()
    assert.are.same({
      bazooka = 10,
      grenade = 10,
      tentacle = -1,
      uppercut = -1,
      chomp = 3,
      dynamite = 1,
      cluster = 0,
      airstrike = 0,
      waddler = 0,
      jetpack = 0,
    }, rules.AMMO)
  end)
end)

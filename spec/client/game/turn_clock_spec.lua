local rules = require("shared.sim.rules")
local terrains = require("spec.support.terrains")
local turn_clock = require("game.turn_clock")
local world = require("shared.sim.world")

local FIRE = { team = 1, kind = "fire", weapon = "bazooka", angle = 64, power = 60 }

local function duel()
  return world.from_terrain({
    terrain = terrains.flat(),
    liquid = terrains.LIQUID,
    settings = { teams = 2, cats_per_team = 1, wind_max = 0 },
    spawns = {
      { team = 1, index = 1, x = 40, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 160, y = terrains.GROUND - 1 },
    },
  })
end

local function step_to(w, state)
  for _ = 1, 2000 do
    if w.turn.state == state then
      return
    end
    world.step(w)
  end
  error("never reached " .. state)
end

describe("⏱️ the time left shown by the HUD (§7.4)", function()
  it("⏱️ counts the turn down while aiming, from its full length", function()
    local w = duel()
    local full = w.settings.turn_seconds
    assert.are.equal(full, turn_clock.seconds(w.turn))
    step_to(w, "aiming")
    for _ = 1, rules.TICKS_PER_SECOND + 1 do
      world.step(w)
    end
    assert.are.equal(full - 1, turn_clock.seconds(w.turn))
  end)

  it("⏱️ after the shot, shows the retreat, then zero, and is never empty", function()
    local w = duel()
    step_to(w, "aiming")
    world.step(w, { FIRE })
    local retreat = rules.RETREAT_TICKS / rules.TICKS_PER_SECOND
    local first, last = {}, {}
    repeat
      local s = turn_clock.seconds(w.turn)
      assert.is_number(s)
      first[w.turn.state] = first[w.turn.state] or s
      last[w.turn.state] = s
      world.step(w)
    until w.turn.state == "turn_start"
    assert.are.same({ flight = retreat, retreat = retreat, settling = 0 }, {
      flight = first.flight,
      retreat = first.retreat,
      settling = first.settling,
    })
    assert.are.equal(retreat, last.flight)
    assert.is_true(last.retreat >= 1 and last.retreat <= retreat)
    assert.are.equal(0, last.turn_end)
  end)

  it("⏱️ after placing the dynamite, counts its whole fuse down during the retreat", function()
    local w = duel()
    step_to(w, "aiming")
    world.step(w, { { team = 1, kind = "fire", weapon = "dynamite", angle = 0, power = 1 } })
    assert.are.same({ "retreat", 5 }, { w.turn.state, turn_clock.seconds(w.turn) })
    for _ = 1, 2 * rules.TICKS_PER_SECOND do
      world.step(w)
    end
    assert.are.equal(3, turn_clock.seconds(w.turn))
  end)
end)

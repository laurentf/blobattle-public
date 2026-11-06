local terrains = require("spec.support.terrains")
local world = require("shared.sim.world")

describe("🔫 the bazooka (§8.2)", function()
  it("🔫 throws a blob it hits at the feet at least 60 px up", function()
    local w = world.from_terrain({
      terrain = terrains.flat(400),
      liquid = terrains.LIQUID,
      settings = { teams = 2, cats_per_team = 1, wind_max = 0 },
      spawns = {
        { team = 1, index = 1, x = 200, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 350, y = terrains.GROUND - 1 },
      },
    })
    while w.turn.state ~= "aiming" do
      world.step(w)
    end
    local c = w.cats[w.teams[w.turn.team].cats[1]]
    world.step(
      w,
      { { team = w.turn.team, kind = "fire", weapon = "bazooka", angle = 768, power = 5 } }
    )
    local top = c.y
    for _ = 1, 200 do
      world.step(w)
      top = math.min(top, c.y)
    end
    local rise = (terrains.GROUND - 1) - math.floor(top / 256)
    assert.is_true(rise >= 60, rise .. " px")
  end)
end)

local stats = require("shared.sim.stats")

local function world_of(teams_of_cats)
  local cats = {}
  for id, team in ipairs(teams_of_cats) do
    cats[id] = { id = id, team = team }
  end
  return { cats = cats, teams = { {}, {}, {} } }
end

describe("🎮 game statistics (§6.4)", function()
  it("🎮 credits the acting team with damage and kills on other teams only", function()
    local w = world_of({ 1, 2, 3, 1 })
    local s = stats.new(w)
    stats.record(s, w, 1, {
      { type = "damaged", cat = 2, amount = 30, cause = "explosion" },
      { type = "damaged", cat = 3, amount = 12, cause = "explosion" },
      { type = "damaged", cat = 4, amount = 50, cause = "explosion" },
      { type = "damaged", cat = 1, amount = 9, cause = "fall" },
      { type = "died", cat = 2, cause = "hp" },
      { type = "died", cat = 4, cause = "hp" },
      { type = "exploded", x = 1, y = 2, radius = 12 },
    })
    stats.record(s, w, 3, { { type = "died", cat = 1, cause = "liquid" } })
    assert.are.same({
      { team = 1, damage = 42, kills = 1 },
      { team = 2, damage = 0, kills = 0 },
      { team = 3, damage = 0, kills = 1 },
    }, s)
  end)

  it(
    "🎮 credits no team with what happens outside any turn (acting team 0, the quake)",
    function()
      local w = world_of({ 1, 2 })
      local s = stats.new(w)
      stats.record(s, w, 0, {
        { type = "damaged", cat = 2, amount = 30, cause = "fall" },
        { type = "died", cat = 1, cause = "liquid" },
      })
      assert.are.same({
        { team = 1, damage = 0, kills = 0 },
        { team = 2, damage = 0, kills = 0 },
        { team = 3, damage = 0, kills = 0 },
      }, s)
    end
  )
end)

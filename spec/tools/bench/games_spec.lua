local games = require("tools.bench.games")

describe("🏁 the bench", function()
  it("🏁 plays an all-bot game to its end and reports it", function()
    local stats = games.new_stats()
    games.play({ index = 3, teams = 2, cats_per_team = 1, level = "easy" }, stats)
    assert.are.equal(1, stats.games)
    assert.are.same({}, stats.errors)
    assert.is_true(stats.turns > 0)
    assert.is_true(stats.shots.easy > 0)
    assert.is_true(stats.died.hp + stats.died.liquid >= 1 or stats.limit == 1)
  end)

  it("🏁 counts a game stopped by the round limit even when a team fell on the way", function()
    local stats = games.new_stats()
    games.play(games.settings_for(40), stats)
    assert.are.same({}, stats.errors)
    assert.are.equal(1, stats.limit)
  end)

  it(
    "🏁 counts games and round limits by map, and the quakes with the deaths they cause",
    function()
      local stats = games.new_stats()
      games.play(games.settings_for(11), stats)
      assert.are.same({}, stats.errors)
      assert.are.same({ games = 1, limit = 0 }, stats.maps.forest)
      assert.are.same({ games = 0, limit = 0 }, stats.maps.volcano)
      assert.are.same({ 2, 2 }, { stats.quakes, stats.quake_deaths })
      games.play(games.settings_for(40), stats)
      local volcano = stats.maps.volcano
      assert.are.equal(1, stats.maps.forest.limit + volcano.limit)
      assert.are.equal(2, stats.maps.forest.games + volcano.games)
    end
  )

  it("🏁 draws the same settings for the same index", function()
    assert.are.same(games.settings_for(17), games.settings_for(17))
    local seen = {}
    for index = 1, 40 do
      local s = games.settings_for(index)
      seen[s.teams .. "x" .. s.cats_per_team] = true
      assert.is_true(
        s.teams >= 2 and s.teams <= 8 and s.cats_per_team >= 1 and s.cats_per_team <= 6
      )
    end
    local count = 0
    for _ in pairs(seen) do
      count = count + 1
    end
    assert.is_true(count > 10)
  end)
end)

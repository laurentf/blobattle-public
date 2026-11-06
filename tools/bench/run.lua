package.path = "./?.lua;" .. package.path

local games = require("tools.bench.games")
local rules = require("shared.sim.rules")

local count = tonumber(arg[1]) or 200
local stats = games.new_stats()
local started = os.clock()
for index = 1, count do
  games.play(games.settings_for(index), stats)
  if index % 20 == 0 then
    io.stderr:write(string.format("… %d games, %.0f s\n", index, os.clock() - started))
  end
end

local n = stats.games
print(string.format("🏁 %d games in %.1f s, %d errors", n, os.clock() - started, #stats.errors))
print(string.format("   turns: %.1f per game, bots passed %d turns", stats.turns / n, stats.skips))
print(
  string.format(
    "   simulated time: %.1f min per game",
    stats.ticks / n / rules.TICKS_PER_SECOND / 60
  )
)
print(
  string.format(
    "   round limit reached: %d (%.1f %%), draws: %d",
    stats.limit,
    100 * stats.limit / n,
    stats.draws
  )
)
if #stats.limit_settings > 0 then
  print("   … at the limit: " .. table.concat(stats.limit_settings, ", "))
end
for _, name in ipairs({ "forest", "volcano" }) do
  local map = stats.maps[name]
  if map.games > 0 then
    print(
      string.format(
        "   %s: %d games, %d at the round limit (%.1f %%)",
        name,
        map.games,
        map.limit,
        100 * map.limit / map.games
      )
    )
  end
end
print(
  string.format("   deaths: %d by hit points, %d in the liquid", stats.died.hp, stats.died.liquid)
)
print(
  string.format(
    "   quakes: %d, %.1f per forest game, %d deaths while the ground shook",
    stats.quakes,
    stats.quakes / math.max(stats.maps.forest.games, 1),
    stats.quake_deaths
  )
)
for _, level in ipairs(games.LEVELS) do
  local shots = stats.shots[level]
  if shots > 0 then
    print(
      string.format(
        "   %s: %d shots, %.1f damage per shot, %.0f %% of shots hurt someone",
        level,
        shots,
        stats.damage[level] / shots,
        100 * stats.hits[level] / shots
      )
    )
  end
end
for _, line in ipairs(stats.errors) do
  print("   ❌ " .. line)
end
os.exit(#stats.errors == 0 and 0 or 1)

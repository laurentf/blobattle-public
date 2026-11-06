local names = require("shared.names")
local world = require("shared.sim.world")

local M = {}

function M.run(vector)
  local w = assert(world.new(vector.seed, vector.settings))
  local by_tick = {}
  for _, entry in ipairs(vector.script) do
    local list = by_tick[entry.at] or {}
    list[#list + 1] = entry.input
    by_tick[entry.at] = list
  end
  local sums = {}
  for _, check in ipairs(vector.checks) do
    while w.tick < check do
      if w.turn.state == "ended" then
        error("the game ended at tick " .. w.tick .. ", before the check at tick " .. check)
      end
      world.step(w, by_tick[w.tick])
    end
    local a, b = world.checksum(w)
    sums[#sums + 1] = { tick = check, a = a, b = b }
  end
  return sums
end

function M.names(vector)
  return names.game(vector.seed, vector.settings.teams)
end

function M.name_lines(list)
  local lines = {}
  for i, team in ipairs(list) do
    lines[i] = "team " .. i .. " " .. team.name .. " " .. table.concat(team.members, " ")
  end
  return lines
end

return M

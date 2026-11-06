local brain = require("shared.bots.brain")
local rules = require("shared.sim.rules")

local M = {}

function M.new(fields)
  local bots = {}
  for _, team in ipairs(fields.teams) do
    bots[team] = brain.new({ team = team, level = fields.level, seed = fields.seed })
  end
  return {
    bots = bots,
    level = fields.level,
    seed = fields.seed,
    budget = fields.budget or rules.BOT_WORK_PER_TICK,
  }
end

function M.take(driver, team)
  if driver.bots[team] == nil then
    driver.bots[team] = brain.new({ team = team, level = driver.level, seed = driver.seed })
  end
end

function M.release(driver, team)
  driver.bots[team] = nil
end

function M.inputs(driver, w)
  local bot = driver.bots[w.turn.team]
  if bot == nil then
    return nil
  end
  local input = brain.think(bot, w, driver.budget)
  if input == nil then
    return nil
  end
  return { input }
end

return M

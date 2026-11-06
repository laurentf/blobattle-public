local rules = require("shared.sim.rules")

local M = {}

M.authority = nil
M.link = nil
M.online = false
M.room_code = nil
M.multi_problem = nil
M.room_problem = nil
M.profile = nil
M.keys = nil
M.keyboard = false
M.result = nil
M.settings = {
  teams = rules.SETTINGS.teams.default,
  cats_per_team = rules.SETTINGS.cats_per_team.default,
  bot_level = rules.SETTINGS.bot_level.default,
  map = rules.SETTINGS.map.default,
}

return M

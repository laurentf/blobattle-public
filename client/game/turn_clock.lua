local rules = require("shared.sim.rules")

local M = {}

local ceil = math.ceil

function M.seconds(turn)
  local state = turn.state
  if state == "turn_start" or state == "aiming" then
    return ceil(turn.timer / rules.TICKS_PER_SECOND)
  elseif state == "flight" then
    return ceil(rules.RETREAT_TICKS / rules.TICKS_PER_SECOND)
  elseif state == "retreat" then
    return ceil(turn.timer / rules.TICKS_PER_SECOND)
  end
  return 0
end

return M

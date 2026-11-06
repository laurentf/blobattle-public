local nk = require("nakama")

local M = {}

local function line(state, text)
  local tick = state.world and state.world.tick or state.match_tick or 0
  return text .. " room=" .. state.code .. " phase=" .. state.phase .. " tick=" .. tick
end

function M.debug(state, text)
  nk.logger_debug(line(state, text))
end

function M.info(state, text)
  nk.logger_info(line(state, text))
end

function M.warn(state, text)
  nk.logger_warn(line(state, text))
end

function M.error(state, text)
  nk.logger_error(line(state, text))
end

return M

local nk = require("nakama")

local M = {}

function M.label(state)
  return nk.json_encode({ code = state.code, phase = state.phase })
end

function M.set(state, dispatcher, name)
  state.phase = name
  dispatcher.match_label_update(M.label(state))
end

return M

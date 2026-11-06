-- pairs(t), 0.5, math.sin(x) and os.time() are fine inside a comment
--[[ and inside a long comment: next(t), 1e3, a / b ]]
local fixed = require("shared.sim.fixed")

local M = {}

local NOTE = "pairs 0.5 / % ^ in a string are not code"
local LONG = [[require("client.x") math.sin 2.5]]

function M.step(t)
  local total = 0
  for i = 1, #t do
    total = total + t[i].next + fixed.div(t[i].x, 256)
  end
  return total + 0x10, NOTE, LONG
end

return M

local M = {}

M.STEP = 4

local sin, floor = math.sin, math.floor

function M.height(t, x, z)
  return 0.9 * sin(t * 2 + x * 0.35) + 0.5 * sin(t * 3.1 + x * 0.9 + z * 0.4)
end

function M.surface(t, x, z, x0)
  local a = x0 + floor((x - x0) / M.STEP) * M.STEP
  local f = (x - a) / M.STEP
  return M.height(t, a, z) * (1 - f) + M.height(t, a + M.STEP, z) * f
end

return M

local math = math
local M = {}
function M.length(dx, dy)
  return math.floor(math.sqrt(dx * dx + dy * dy))
end
return M

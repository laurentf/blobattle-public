local M = {}

local count = 0

function M.next(prefix)
  count = count + 1
  return "/" .. prefix .. "_" .. count .. ".bufferc"
end

return M

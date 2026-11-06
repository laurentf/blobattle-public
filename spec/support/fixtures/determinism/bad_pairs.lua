local M = {}
function M.sum(t)
  local s = 0
  for _, v in pairs(t) do
    s = s + v
  end
  return s
end
return M

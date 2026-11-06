local M = {}

local KEEP = 300

function M.new()
  return {}
end

function M.add(list, value)
  list[#list + 1] = value
  if #list > KEEP then
    table.remove(list, 1)
  end
end

function M.summary(list)
  if #list == 0 then
    return { avg = 0, p95 = 0, max = 0, n = 0 }
  end
  local sorted, total = {}, 0
  for i, v in ipairs(list) do
    sorted[i] = v
    total = total + v
  end
  table.sort(sorted)
  return {
    avg = total / #sorted,
    p95 = sorted[math.max(1, math.ceil(#sorted * 0.95))],
    max = sorted[#sorted],
    n = #sorted,
  }
end

return M

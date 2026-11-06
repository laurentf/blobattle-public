local M = {}

function M.new(w)
  local s = {}
  for i = 1, #w.teams do
    s[i] = { team = i, damage = 0, kills = 0 }
  end
  return s
end

function M.record(s, w, acting, events)
  local line = s[acting]
  if line == nil then
    return
  end
  for _, e in ipairs(events) do
    local c = e.cat and w.cats[e.cat]
    if c and c.team ~= acting then
      if e.type == "damaged" then
        line.damage = line.damage + e.amount
      elseif e.type == "died" then
        line.kills = line.kills + 1
      end
    end
  end
end

return M

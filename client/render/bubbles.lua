local M = {}

M.RATE = 0.012
M.LIFE = 0.9
M.RISE = 1.5
M.SIZE = 1.4

function M.new(fields)
  return {
    width = fields.width,
    level = fields.level,
    lava = fields.lava,
    random = fields.random or math.random,
    list = {},
    due = 0,
  }
end

function M.set_level(b, level)
  b.level = level
end

function M.step(b, dt, open)
  local list, kept = b.list, 0
  for i = 1, #list do
    local bubble = list[i]
    bubble.age = bubble.age + dt
    if bubble.age < bubble.life then
      kept = kept + 1
      list[kept] = bubble
    end
  end
  for i = #list, kept + 1, -1 do
    list[i] = nil
  end
  if not b.lava then
    return
  end
  b.due = b.due + dt * b.width * M.RATE
  while b.due >= 1 do
    b.due = b.due - 1
    local x = math.floor(b.random() * b.width)
    if open(x) then
      list[#list + 1] = {
        x = x + b.random(),
        level = b.level,
        age = 0,
        life = M.LIFE * (0.6 + 0.4 * b.random()),
        size = M.SIZE * (0.5 + 0.5 * b.random()),
      }
    end
  end
end

function M.shape(bubble, out)
  out = out or {}
  local k = bubble.age / bubble.life
  out.size = bubble.size * (0.3 + 0.7 * k)
  out.rise = M.RISE * k
  return out
end

return M

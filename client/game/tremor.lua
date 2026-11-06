local M = {}

M.SECONDS = 0.45
M.PER_PUSH = 1 / 200

function M.new()
  return { amplitude = 0, left = 0, x = 0, y = 0 }
end

function M.shake(t, push)
  t.amplitude = push * M.PER_PUSH
  t.left = M.SECONDS
end

function M.step(t, dt, time)
  t.left = math.max(0, t.left - dt)
  if t.left == 0 then
    t.x, t.y = 0, 0
    return
  end
  local k = t.amplitude * t.left / M.SECONDS
  t.x = k * math.sin(time * 71)
  t.y = k * math.sin(time * 53 + 1.3)
end

return M

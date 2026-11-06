local M = {}

M.SPEED = 2

function M.step(shown, target, dt)
  if shown > target then
    return math.max(target, shown - M.SPEED * dt)
  end
  return math.min(target, shown + M.SPEED * dt)
end

return M

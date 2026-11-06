local M = {}

M.EVERY = 90
M.HIGH = 0.1
M.LOW = 0.32
M.PUFFS_MIN, M.PUFFS_MAX = 3, 5
M.PUFF_MIN, M.PUFF_MAX = 4, 9
M.CALM = 0.6
M.PER_WIND = 0.8
M.MARGIN = 40
M.SPREAD = 12

function M.new(fields)
  local random = fields.random or math.random
  local width, height = fields.width, fields.height
  local list = {}
  for i = 1, math.floor(width / M.EVERY + 0.5) do
    local puffs = {}
    local count = M.PUFFS_MIN + math.floor(random() * (M.PUFFS_MAX - M.PUFFS_MIN + 1))
    for p = 1, count do
      puffs[p] = {
        dx = (p - (count + 1) / 2) * 5 + (random() - 0.5) * 3,
        dy = (random() - 0.5) * 3,
        size = M.PUFF_MIN + random() * (M.PUFF_MAX - M.PUFF_MIN),
      }
    end
    list[i] = {
      x = (i - 1 + random()) * width / math.floor(width / M.EVERY + 0.5),
      y = height * (1 - M.LOW + random() * (M.LOW - M.HIGH)),
      speed = 0.7 + random() * 0.6,
      puffs = puffs,
    }
  end
  return { list = list, width = width }
end

function M.step(c, dt, wind)
  local drift = wind == 0 and M.CALM or wind * M.PER_WIND
  for _, cloud in ipairs(c.list) do
    cloud.x = cloud.x + drift * cloud.speed * dt
    if cloud.x > c.width + M.MARGIN then
      cloud.x = cloud.x - c.width - 2 * M.MARGIN
    elseif cloud.x < -M.MARGIN then
      cloud.x = cloud.x + c.width + 2 * M.MARGIN
    end
  end
end

return M

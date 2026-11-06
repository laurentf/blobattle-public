local terrain = require("shared.sim.terrain")

local M = {}

M.WIDTH = 200
M.HEIGHT = 120
M.GROUND = 100
M.LIQUID = 112

local function soil_rect(t, x0, y0, x1, y1)
  for y = math.max(y0, 0), math.min(y1, t.height - 1) do
    for x = math.max(x0, 0), math.min(x1, t.width - 1) do
      terrain.set(t, x, y, terrain.SOIL)
    end
  end
end

function M.flat(width)
  local t = terrain.new(width or M.WIDTH, M.HEIGHT)
  soil_rect(t, 0, M.GROUND, t.width - 1, M.HEIGHT - 1)
  return t
end

function M.stairs(rise)
  local t = M.flat()
  soil_rect(t, 100, M.GROUND - rise, M.WIDTH - 1, M.GROUND - 1)
  return t
end

function M.cliff(height)
  local t = terrain.new(M.WIDTH, M.HEIGHT)
  soil_rect(t, 0, M.GROUND - height, 99, M.HEIGHT - 1)
  soil_rect(t, 100, M.GROUND, M.WIDTH - 1, M.HEIGHT - 1)
  return t
end

function M.wall(thickness, height)
  local t = M.flat()
  soil_rect(t, 120, M.GROUND - height, 120 + thickness - 1, M.GROUND - 1)
  return t
end

function M.ledge(x, top)
  local t = M.flat()
  soil_rect(t, x, top, M.WIDTH - 1, M.GROUND - 1)
  return t
end

function M.overhang(x, bottom)
  local t = M.flat()
  soil_rect(t, x, bottom - 2, M.WIDTH - 1, bottom)
  return t
end

function M.staircase(x, rise, run)
  local t = M.flat()
  local step = 0
  while M.GROUND - (step + 1) * rise >= 0 and x + step * run < M.WIDTH do
    soil_rect(t, x + step * run, M.GROUND - (step + 1) * rise, M.WIDTH - 1, M.GROUND - 1)
    step = step + 1
  end
  return t
end

function M.ceiling(bottom, width)
  local t = M.flat(width)
  soil_rect(t, 0, bottom - 4, t.width - 1, bottom)
  return t
end

function M.shore()
  local t = terrain.new(M.WIDTH, M.HEIGHT)
  soil_rect(t, 0, M.GROUND, 99, M.HEIGHT - 1)
  return t
end

function M.pockets(spots)
  local t = terrain.new(M.WIDTH, M.HEIGHT)
  soil_rect(t, 0, 0, M.WIDTH - 1, M.HEIGHT - 1)
  for _, spot in ipairs(spots) do
    for y = spot[2] - 6, spot[2] do
      for x = spot[1] - 3, spot[1] + 2 do
        terrain.set(t, x, y, terrain.AIR)
      end
    end
  end
  return t
end

function M.well(width)
  local t = M.flat()
  for y = 0, M.HEIGHT - 1 do
    for x = 100, 100 + width - 1 do
      terrain.set(t, x, y, terrain.AIR)
    end
  end
  return t
end

return M

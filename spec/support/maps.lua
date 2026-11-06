local rules = require("shared.sim.rules")
local terrain = require("shared.sim.terrain")

local M = {}

local function box_columns(px)
  local left = px - math.floor(rules.CAT_WIDTH / 2)
  return left, left + rules.CAT_WIDTH - 1
end

function M.box_free(t, px, py)
  local left, right = box_columns(px)
  for y = py - rules.CAT_HEIGHT + 1, py do
    for x = left, right do
      if terrain.solid(t, x, y) then
        return false
      end
    end
  end
  return true
end

function M.open_sky(t, px, py)
  local left, right = box_columns(px)
  for x = left, right do
    for y = 0, py do
      if terrain.solid(t, x, y) then
        return false
      end
    end
  end
  return true
end

function M.supported(t, px, py)
  local left, right = box_columns(px)
  for x = left, right do
    if terrain.solid(t, x, py + 1) then
      return true
    end
  end
  return false
end

M.SETTINGS = {
  { teams = 2, cats_per_team = 1, map = "random" },
  { teams = 2, cats_per_team = 4, map = "forest" },
  { teams = 3, cats_per_team = 3, map = "volcano" },
  { teams = 4, cats_per_team = 4, map = "random" },
  { teams = 6, cats_per_team = 2, map = "forest" },
  { teams = 8, cats_per_team = 4, map = "volcano" },
  { teams = 8, cats_per_team = 6, map = "random" },
}

M.LIQUID = { forest = "water", volcano = "lava" }

function M.first_soil(t, x)
  local y = 0
  while y < t.height and terrain.get(t, x, y) ~= terrain.SOIL do
    y = y + 1
  end
  return y
end

function M.in_overhang(map, x, y, margin)
  for _, o in ipairs(map.overhangs) do
    local rx, ry = o.reach + margin, o.height + margin
    local dx, dy = x - o.x, y - o.y
    if dx * dx * ry * ry + dy * dy * rx * rx <= (rx * ry) ^ 2 then
      return true
    end
  end
  return false
end

function M.small_islands(t, minimum)
  local width, total, cells = t.width, t.width * t.height, t.cells
  local function ground(n)
    return cells[n] ~= terrain.AIR and cells[n] ~= terrain.STEEL
  end
  local label = {}
  local stack = {}
  local function visit(n, top)
    if n >= 1 and n <= total and ground(n) and not label[n] then
      label[n] = true
      top = top + 1
      stack[top] = n
    end
    return top
  end
  local function flood(start)
    label[start] = true
    stack[1] = start
    local top, size = 1, 0
    while top > 0 do
      local i = stack[top]
      top = top - 1
      size = size + 1
      local x = (i - 1) % width
      top = visit(i - width, top)
      top = visit(i + width, top)
      if x > 0 then
        top = visit(i - 1, top)
      end
      if x < width - 1 then
        top = visit(i + 1, top)
      end
    end
    return size
  end
  for i = total - width + 1, total do
    if ground(i) and not label[i] then
      flood(i)
    end
  end
  local small = 0
  for i = 1, total do
    if ground(i) and not label[i] and flood(i) < minimum then
      small = small + 1
    end
  end
  return small
end

return M

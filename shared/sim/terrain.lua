local fixed = require("shared.sim.fixed")
local hash = require("shared.sim.hash")
local rules = require("shared.sim.rules")

local max, min = math.max, math.min

local M = {}

M.AIR = 0
M.SOIL = 1
M.WOOD = 2
M.LEAVES = 3
M.STEEL = 4
M.MATERIALS = 5
M.RUN = 8

function M.new(width, height)
  local cells = {}
  for i = 1, width * height do
    cells[i] = M.AIR
  end
  return { width = width, height = height, cells = cells, log = hash.new() }
end

function M.get(t, x, y)
  if x < 0 or x >= t.width or y < 0 then
    return M.AIR
  end
  if y >= t.height then
    return M.SOIL
  end
  return t.cells[y * t.width + x + 1]
end

function M.solid(t, x, y)
  return M.get(t, x, y) ~= M.AIR
end

function M.set(t, x, y, value)
  if x < 0 or x >= t.width or y < 0 or y >= t.height then
    error("cell out of the map")
  end
  t.cells[y * t.width + x + 1] = value
end

function M.carve(t, cx, cy, radius)
  local cells, width = t.cells, t.width
  local removed = 0
  local r2 = radius * radius
  for dy = -radius, radius do
    local y = cy + dy
    if y >= 0 and y < t.height then
      local span = fixed.isqrt(r2 - dy * dy)
      local row = y * width + 1
      for x = max(cx - span, 0), min(cx + span, width - 1) do
        if cells[row + x] ~= M.AIR then
          cells[row + x] = M.AIR
          removed = removed + 1
        end
      end
    end
  end
  hash.add(t.log, cx)
  hash.add(t.log, cy)
  hash.add(t.log, radius)
  return removed
end

function M.encode(t)
  local out = { t.width, t.height, t.log.a, t.log.b }
  local cells, width = t.cells, t.width
  for y = 0, t.height - 1 do
    local row = y * width
    local count_at = #out + 1
    out[count_at] = 0
    local current, run = cells[row + 1], 0
    for x = 1, width do
      local v = cells[row + x]
      if v == current then
        run = run + 1
      else
        out[#out + 1] = run * M.RUN + current
        out[count_at] = out[count_at] + 1
        current, run = v, 1
      end
    end
    out[#out + 1] = run * M.RUN + current
    out[count_at] = out[count_at] + 1
  end
  return out
end

local function whole(v, low, high)
  return type(v) == "number" and fixed.mod(v, 1) == 0 and v >= low and v <= high
end

function M.decode(data)
  local width, height = data[1], data[2]
  if not whole(width, 1, rules.MAP_WIDTH_MAX) or not whole(height, 1, rules.MAP_WIDTH_MAX) then
    return nil, "terrain_encoding"
  end
  if not whole(data[3], 0, hash.MODULUS - 1) or not whole(data[4], 0, hash.MODULUS - 1) then
    return nil, "terrain_encoding"
  end
  local t = M.new(width, height)
  t.log.a, t.log.b = data[3], data[4]
  local cells = t.cells
  local i = 5
  for y = 0, height - 1 do
    local runs = data[i]
    if not whole(runs, 1, width) then
      return nil, "terrain_encoding"
    end
    i = i + 1
    local x = 1
    for _ = 1, runs do
      local token = data[i]
      if not whole(token, M.RUN, (width + 1 - x) * M.RUN + M.MATERIALS - 1) then
        return nil, "terrain_encoding"
      end
      local run, value = fixed.div(token, M.RUN), fixed.mod(token, M.RUN)
      if value >= M.MATERIALS then
        return nil, "terrain_encoding"
      end
      i = i + 1
      for k = x, x + run - 1 do
        cells[y * width + k] = value
      end
      x = x + run
    end
    if x ~= width + 1 then
      return nil, "terrain_encoding"
    end
  end
  if i ~= #data + 1 then
    return nil, "terrain_encoding"
  end
  return t
end

function M.hash_encoded(data)
  local h = hash.new()
  for i = 5, #data do
    hash.add(h, data[i])
  end
  return hash.digest(h)
end

function M.cells_hash(t)
  return M.hash_encoded(M.encode(t))
end

function M.log_digest(t)
  return hash.digest(t.log)
end

return M

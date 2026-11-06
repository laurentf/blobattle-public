local palette = require("ui.palette")
local rng = require("shared.sim.rng")
local shapes = require("render.shapes")

local M = {}

M.DEBRIS = 10
M.CUBES = M.DEBRIS + 2

M.MEADOW = {
  view = 120,
  width = 300,
  camera = { fov = 0.6, pan = 30, min_width = 110, ground_line = 12, ground_at = 0.2 },
  blobs = { -64, -40, -14, 12, 38, 62 },
  layers = {
    {
      depth = -160,
      cell = 6,
      low = 7,
      high = 15,
      every = 4,
      thickness = 12,
      colour = { 0.64, 0.76, 0.9 },
    },
    {
      depth = -70,
      cell = 3,
      low = 5,
      high = 11,
      every = 5,
      thickness = 9,
      colour = { 0.48, 0.72, 0.52 },
    },
    {
      depth = 0,
      cell = 2,
      low = 5,
      high = 10,
      every = 7,
      thickness = 12,
      colour = palette.SOIL,
      rim = palette.RIM,
    },
  },
  water = { level = 4, colour = palette.WATER },
  clouds = { count = 6, low = 38, high = 62, depth = -110, colour = { 1, 1, 1 } },
}

local function relief(stream, spec, columns)
  local points = {}
  for i = 0, math.ceil(columns / spec.every) + 1 do
    points[i] = rng.range(stream, spec.low, spec.high)
  end
  local heights = {}
  for i = 1, columns do
    local at = (i - 1) / spec.every
    local k = math.floor(at)
    local t = at - k
    local h = points[k] + (points[k + 1] - points[k]) * (3 - 2 * t) * t * t
    heights[i] = math.floor(h + 0.5)
  end
  return heights
end

function M.layers(seed, look)
  local stream = rng.stream(seed, "map")
  local out = {}
  for i, spec in ipairs(look.layers) do
    local distance = look.view - spec.depth
    local columns = math.ceil(look.width * distance / look.view / spec.cell)
    out[i] = {
      depth = spec.depth,
      cell = spec.cell,
      thickness = spec.thickness,
      colour = spec.colour,
      rim = spec.rim,
      heights = relief(stream, spec, columns),
      x0 = -columns * spec.cell / 2,
    }
  end
  return out
end

function M.eye(look, aspect)
  local cam = look.camera
  local slope = math.tan(cam.fov / 2)
  local z = math.max(look.view, cam.min_width / (2 * slope * aspect))
  return { z = z, y = cam.ground_line + slope * z * (1 - 2 * cam.ground_at) }
end

function M.water(ground, look)
  return shapes.liquid({
    x0 = ground.x0 - 20,
    x1 = -ground.x0 + 20,
    top = look.water.level * ground.cell,
    bottom = -60,
  })
end

local function column(layer, x)
  local i = math.floor((x - layer.x0) / layer.cell) + 1
  return math.max(1, math.min(#layer.heights, i))
end

function M.ground(layer, x, half)
  half = half or 0
  local top = 0
  for i = column(layer, x - half), column(layer, x + half) do
    top = math.max(top, layer.heights[i])
  end
  return top * layer.cell
end

local function puff(stream)
  local cells = {}
  local rx, ry = rng.range(stream, 4, 7), rng.range(stream, 2, 3)
  for x = -rx, rx do
    for y = 0, ry do
      if (x / (rx + 0.5)) ^ 2 + (y / (ry + 0.5)) ^ 2 <= 1 then
        cells[#cells + 1] = { x = x, y = y }
      end
    end
  end
  return cells
end

function M.clouds(seed, look)
  local stream = rng.stream(seed, "sim")
  local spec = look.clouds
  local span = look.width * (look.view - spec.depth) / look.view
  local out = {}
  for i = 1, spec.count do
    out[i] = {
      cells = puff(stream),
      x = -span / 2 + span * (i - 1) / spec.count + rng.range(stream, 0, 20),
      y = rng.range(stream, spec.low, spec.high),
      depth = spec.depth + rng.range(stream, -20, 20),
      size = rng.range(stream, 2, 3),
      speed = rng.range(stream, 2, 5),
    }
  end
  return out
end

return M

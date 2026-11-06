local palette = require("ui.palette")
local terrain = require("shared.sim.terrain")

local M = {}

M.AIR, M.SURFACE, M.SOIL, M.ROCK, M.WOOD, M.LEAVES, M.STEEL = 0, 1, 2, 3, 4, 5, 6
M.CONSTANTS = { "surface", "soil", "rock", "wood", "leaves", "steel" }
M.SURFACE_DEPTH = 2
M.SOIL_DEPTH = 8

function M.look(liquid)
  return liquid.kind == "lava" and palette.BIOMES.volcano or palette.BIOMES.forest
end

function M.fill(t, out)
  local width, height, cells = t.width, t.height, t.cells
  local AIR, WOOD, LEAVES, STEEL = terrain.AIR, terrain.WOOD, terrain.LEAVES, terrain.STEEL
  local surface_depth, soil_depth = M.SURFACE_DEPTH, M.SOIL_DEPTH
  local depth = {}
  for x = 1, width do
    depth[x] = 0
  end
  for row = 0, height - 1 do
    local from, to = row * width, (height - 1 - row) * width
    for x = 1, width do
      local v = cells[from + x]
      local k
      if v == AIR then
        depth[x] = 0
        k = M.AIR
      elseif v == WOOD then
        depth[x] = 0
        k = M.WOOD
      elseif v == LEAVES then
        depth[x] = 0
        k = M.LEAVES
      elseif v == STEEL then
        depth[x] = 0
        k = M.STEEL
      else
        local d = depth[x] + 1
        depth[x] = d
        if d <= surface_depth then
          k = M.SURFACE
        elseif d <= soil_depth then
          k = M.SOIL
        else
          k = M.ROCK
        end
      end
      out[to + x] = k
    end
  end
  return out
end

return M

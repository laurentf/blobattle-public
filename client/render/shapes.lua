local fuse = require("render.fuse")
local waves = require("render.waves")
local voxel_mesh = require("render.voxel_mesh")

local M = {}

local ALL = { pz = true, nz = true, px = true, nx = true, py = true, ny = true }

local function writer()
  local pos, nrm = {}, {}
  local out = { pos = pos, nrm = nrm, n = 0 }
  function out.vertex(x, y, z, nx, ny, nz)
    local k = out.n * 3
    pos[k + 1], pos[k + 2], pos[k + 3] = x, y, z
    nrm[k + 1], nrm[k + 2], nrm[k + 3] = nx, ny, nz
    out.n = out.n + 1
  end
  function out.quad(a, b, c, d, nx, ny, nz)
    for _, v in ipairs({ a, b, c, a, c, d }) do
      out.vertex(v[1], v[2], v[3], nx, ny, nz)
    end
  end
  return out
end

local function box(out, x0, y0, z0, x1, y1, z1, faces)
  if faces.pz then
    out.quad({ x0, y0, z1 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z1 }, 0, 0, 1)
  end
  if faces.nz then
    out.quad({ x1, y0, z0 }, { x0, y0, z0 }, { x0, y1, z0 }, { x1, y1, z0 }, 0, 0, -1)
  end
  if faces.px then
    out.quad({ x1, y0, z1 }, { x1, y0, z0 }, { x1, y1, z0 }, { x1, y1, z1 }, 1, 0, 0)
  end
  if faces.nx then
    out.quad({ x0, y0, z0 }, { x0, y0, z1 }, { x0, y1, z1 }, { x0, y1, z0 }, -1, 0, 0)
  end
  if faces.py then
    out.quad({ x0, y1, z1 }, { x1, y1, z1 }, { x1, y1, z0 }, { x0, y1, z0 }, 0, 1, 0)
  end
  if faces.ny then
    out.quad({ x0, y0, z0 }, { x1, y0, z0 }, { x1, y0, z1 }, { x0, y0, z1 }, 0, -1, 0)
  end
end

function M.blob()
  local set = {}
  local function key(i, j, k)
    return i .. ":" .. j .. ":" .. k
  end
  for i = -3, 3 do
    for j = 0, 6 do
      for k = -2, 2 do
        local d = (i / 3.6) ^ 2 + ((j + 0.5 - 3.4) / 3.6) ^ 2 + (k / 2.9) ^ 2
        if d <= 1 or (j == 0 and math.abs(i) <= 2 and math.abs(k) <= 1) then
          set[key(i, j, k)] = true
        end
      end
    end
  end
  local out = writer()
  for i = -3, 3 do
    for j = 0, 6 do
      for k = -2, 2 do
        if set[key(i, j, k)] then
          box(out, i - 0.5, j, k - 0.5, i + 0.5, j + 1, k + 0.5, {
            pz = not set[key(i, j, k + 1)],
            nz = not set[key(i, j, k - 1)],
            px = not set[key(i + 1, j, k)],
            nx = not set[key(i - 1, j, k)],
            py = not set[key(i, j + 1, k)],
            ny = not set[key(i, j - 1, k)],
          })
        end
      end
    end
  end
  return out
end

local FACE_Z0, FACE_Z1 = 2.45, 2.62

function M.extrude(cells, fields)
  local depth = fields.depth
  local filled = {}
  for _, c in ipairs(cells) do
    filled[c.x .. ":" .. c.y] = true
  end
  local function free(x, y)
    return not filled[x .. ":" .. y]
  end
  local out = writer()
  local z0, z1 = -depth / 2, depth / 2
  for _, c in ipairs(cells) do
    local x, y = c.x, c.y
    box(out, x - 0.5, y, z0, x + 0.5, y + 1, z1, {
      pz = true,
      nz = true,
      px = free(x + 1, y),
      nx = free(x - 1, y),
      py = free(x, y + 1),
      ny = free(x, y - 1),
    })
  end
  return out
end

function M.skyline(heights, fields)
  local cell, depth, band = fields.cell, fields.depth, fields.band
  local out = writer()
  local n = #heights
  local back, front = -depth / 2, depth / 2
  for i, h in ipairs(heights) do
    local x0, x1 = (i - 1.5) * cell, (i - 0.5) * cell
    local floor = band and math.max(0, h - band) or 0
    local top = h * cell
    local y0 = floor * cell
    out.quad({ x0, y0, front }, { x1, y0, front }, { x1, top, front }, { x0, top, front }, 0, 0, 1)
    out.quad({ x0, top, front }, { x1, top, front }, { x1, top, back }, { x0, top, back }, 0, 1, 0)
    local right = i < n and math.max(heights[i + 1] * cell, y0) or y0
    if right < top then
      out.quad(
        { x1, right, front },
        { x1, right, back },
        { x1, top, back },
        { x1, top, front },
        1,
        0,
        0
      )
    end
    local left = i > 1 and math.max(heights[i - 1] * cell, y0) or y0
    if left < top then
      out.quad(
        { x0, left, back },
        { x0, left, front },
        { x0, top, front },
        { x0, top, back },
        -1,
        0,
        0
      )
    end
  end
  return out
end

function M.face(face)
  local out = writer()
  for _, rects in pairs(face) do
    for _, r in ipairs(rects) do
      box(out, r[1], r[2], FACE_Z0, r[3], r[4], FACE_Z1, ALL)
    end
  end
  return out
end

function M.rocket()
  local out = writer()
  box(out, -1.3, -0.4, -0.4, 0.9, 0.4, 0.4, ALL)
  box(out, 0.9, -0.25, -0.25, 1.7, 0.25, 0.25, ALL)
  box(out, -1.7, -0.7, -0.12, -1.1, 0.7, 0.12, ALL)
  box(out, -1.7, -0.12, -0.7, -1.1, 0.12, 0.7, ALL)
  return out
end

function M.dynamite()
  local out = writer()
  box(out, -0.8, -1, -0.8, 0.8, fuse.BASE, 0.8, ALL)
  return out
end

function M.crate()
  local out = writer()
  box(out, -3, 0, -3, 3, 6, 3, ALL)
  return out
end

function M.crate_mark()
  local out = writer()
  box(out, -2.2, 2.6, 3, 2.2, 3.4, 3.4, ALL)
  box(out, -0.4, 0.8, 3, 0.4, 5.2, 3.4, ALL)
  return out
end

function M.chute()
  local out = writer()
  box(out, -6, 12, -4, 6, 14, 4, ALL)
  box(out, -4.5, 14, -3, 4.5, 15.5, 3, ALL)
  box(out, -7, 10.5, -3, -5.6, 12, 3, ALL)
  box(out, 5.6, 10.5, -3, 7, 12, 3, ALL)
  for _, x in ipairs({ -5.2, -2, 2, 5.2 }) do
    box(out, x - 0.15, 6, -0.15, x + 0.15, 11, 0.15, ALL)
  end
  return out
end

function M.plane()
  local out = writer()
  box(out, -7, -1.2, -1.5, 6, 1.2, 1.5, ALL)
  box(out, 6, -0.8, -1, 8, 0.8, 1, ALL)
  box(out, -1.5, -0.4, -9, 2.5, 0.4, 9, ALL)
  box(out, -7, 1.2, -0.4, -4.5, 4.5, 0.4, ALL)
  box(out, -7, -0.3, -3.5, -5, 0.3, 3.5, ALL)
  return out
end

function M.cube()
  local out = writer()
  box(out, -0.5, -0.5, -0.5, 0.5, 0.5, 0.5, ALL)
  return out
end

function M.liquid(fields)
  local out = writer()
  local top, depth = fields.top, voxel_mesh.DEPTH
  local front = depth + 0.4
  local step = waves.STEP
  for x = fields.x0, fields.x1 - step, step do
    local a, b = x, x + step
    out.vertex(a, fields.bottom, front, 0, 0, 1)
    out.vertex(b, fields.bottom, front, 0, 0, 1)
    out.vertex(b, top, front, 1, 0, 0)
    out.vertex(a, fields.bottom, front, 0, 0, 1)
    out.vertex(b, top, front, 1, 0, 0)
    out.vertex(a, top, front, 1, 0, 0)
    out.vertex(a, top, front, 1, 0, 0)
    out.vertex(b, top, front, 1, 0, 0)
    out.vertex(b, top, -depth, 1, 0, 0)
    out.vertex(a, top, front, 1, 0, 0)
    out.vertex(b, top, -depth, 1, 0, 0)
    out.vertex(a, top, -depth, 1, 0, 0)
  end
  return out
end

return M

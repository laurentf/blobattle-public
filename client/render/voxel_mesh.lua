local rules = require("shared.sim.rules")

local M = {}

M.CHUNK = 32
M.BAND = 32
M.DEPTH = 10
M.RIM_NY = 0.05
M.RIM_NZ = 0.9987

local DEPTH = M.DEPTH

local function copy(part)
  local pos, nrm = {}, {}
  for i = 1, part.n * 3 do
    pos[i], nrm[i] = part.pos[i], part.nrm[i]
  end
  return { pos = pos, nrm = nrm, n = part.n }
end

local scratch = { pos = {}, nrm = {}, n = 0 }
local spos, snrm = scratch.pos, scratch.nrm

function scratch.quad(ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz, nx, ny, nz)
  local i = scratch.n * 3
  spos[i + 1], spos[i + 2], spos[i + 3] = ax, ay, az
  spos[i + 4], spos[i + 5], spos[i + 6] = bx, by, bz
  spos[i + 7], spos[i + 8], spos[i + 9] = cx, cy, cz
  spos[i + 10], spos[i + 11], spos[i + 12] = ax, ay, az
  spos[i + 13], spos[i + 14], spos[i + 15] = cx, cy, cz
  spos[i + 16], spos[i + 17], spos[i + 18] = dx, dy, dz
  for k = 1, 18, 3 do
    snrm[i + k], snrm[i + k + 1], snrm[i + k + 2] = nx, ny, nz
  end
  scratch.n = scratch.n + 6
end

local function writer()
  scratch.n = 0
  return scratch
end

local function solid_at(t)
  local cells, width, height = t.cells, t.width, t.height
  return function(x, y)
    if y < 0 or x < 0 or x >= width then
      return false
    end
    if y >= height then
      return true
    end
    return cells[y * width + x + 1] ~= 0
  end
end

local function build_row(mesh, chunk, y)
  local t = mesh.terrain
  local cells, width, height = t.cells, t.width, t.height
  local x0, x1 = chunk.x0, chunk.x1
  local top, bottom = height - y, height - y - 1
  local here = y * width + 1
  local up1, up2, down = here - width, here - 2 * width, here + width
  local has_up1, has_up2, has_down = y >= 1, y >= 2, y + 1 < height
  local out = writer()
  local x = x0
  while x < x1 do
    if cells[here + x] ~= 0 then
      local rim = not (has_up1 and cells[up1 + x] ~= 0) or not (has_up2 and cells[up2 + x] ~= 0)
      local s = x
      x = x + 1
      while
        x < x1
        and cells[here + x] ~= 0
        and (not (has_up1 and cells[up1 + x] ~= 0) or not (has_up2 and cells[up2 + x] ~= 0))
          == rim
      do
        x = x + 1
      end
      local ny, nz = 0, 1
      if rim then
        ny, nz = M.RIM_NY, M.RIM_NZ
      end
      out.quad(s, bottom, DEPTH, x, bottom, DEPTH, x, top, DEPTH, s, top, DEPTH, 0, ny, nz)
    else
      x = x + 1
    end
  end
  x = x0
  while x < x1 do
    if cells[here + x] ~= 0 and not (has_up1 and cells[up1 + x] ~= 0) then
      local s = x
      x = x + 1
      while x < x1 and cells[here + x] ~= 0 and not (has_up1 and cells[up1 + x] ~= 0) do
        x = x + 1
      end
      out.quad(s, top, DEPTH, x, top, DEPTH, x, top, -DEPTH, s, top, -DEPTH, 0, 1, 0)
    else
      x = x + 1
    end
  end
  x = x0
  while x < x1 do
    if cells[here + x] ~= 0 and has_down and cells[down + x] == 0 then
      local s = x
      x = x + 1
      while x < x1 and cells[here + x] ~= 0 and has_down and cells[down + x] == 0 do
        x = x + 1
      end
      out.quad(s, bottom, -DEPTH, x, bottom, -DEPTH, x, bottom, DEPTH, s, bottom, DEPTH, 0, -1, 0)
    else
      x = x + 1
    end
  end
  chunk.rows[y + 1] = mesh.seal(out)
end

local function build_column(mesh, chunk, x, band)
  local height = mesh.terrain.height
  local solid = mesh.solid
  local out = writer()
  local first = band * M.BAND
  local last = math.min(first + M.BAND, height)
  for side = -1, 1, 2 do
    local fx = side < 0 and x or x + 1
    local y = first
    while y < last do
      if solid(x, y) and not solid(x + side, y) then
        local s = y
        y = y + 1
        while y < last and solid(x, y) and not solid(x + side, y) do
          y = y + 1
        end
        local hi, lo = height - s, height - y
        if side < 0 then
          out.quad(fx, lo, -DEPTH, fx, lo, DEPTH, fx, hi, DEPTH, fx, hi, -DEPTH, -1, 0, 0)
        else
          out.quad(fx, lo, DEPTH, fx, lo, -DEPTH, fx, hi, -DEPTH, fx, hi, DEPTH, 1, 0, 0)
        end
      else
        y = y + 1
      end
    end
  end
  local column = chunk.cols[x - chunk.x0 + 1]
  column[band + 1] = mesh.seal(out)
end

function M.new(t, fields)
  fields = fields or {}
  local mesh = {
    terrain = t,
    solid = solid_at(t),
    seal = fields.seal or copy,
    chunks = {},
  }
  mesh.bands = math.ceil(t.height / M.BAND)
  local count = math.ceil(t.width / M.CHUNK)
  for i = 1, count do
    local x0 = (i - 1) * M.CHUNK
    local chunk = {
      index = i,
      x0 = x0,
      x1 = math.min(x0 + M.CHUNK, t.width),
      rows = {},
      cols = {},
      dirty = nil,
    }
    for x = chunk.x0, chunk.x1 - 1 do
      chunk.cols[x - x0 + 1] = {}
    end
    mesh.chunks[i] = chunk
  end
  return mesh
end

function M.build_all(mesh)
  for _, chunk in ipairs(mesh.chunks) do
    for y = 0, mesh.terrain.height - 1 do
      build_row(mesh, chunk, y)
    end
    for x = chunk.x0, chunk.x1 - 1 do
      for band = 0, mesh.bands - 1 do
        build_column(mesh, chunk, x, band)
      end
    end
    chunk.dirty = nil
  end
end

local function merge(chunk, rows_lo, rows_hi, cols_lo, cols_hi, bands_lo, bands_hi)
  local d = chunk.dirty
  if d == nil then
    chunk.dirty = {
      rows_lo = rows_lo,
      rows_hi = rows_hi,
      cols_lo = cols_lo,
      cols_hi = cols_hi,
      bands_lo = bands_lo,
      bands_hi = bands_hi,
      band = bands_lo,
    }
    return
  end
  if rows_lo <= rows_hi then
    if d.rows_lo > d.rows_hi then
      d.rows_lo, d.rows_hi = rows_lo, rows_hi
    else
      d.rows_lo, d.rows_hi = math.min(d.rows_lo, rows_lo), math.max(d.rows_hi, rows_hi)
    end
  end
  if cols_lo <= cols_hi then
    if d.cols_lo > d.cols_hi then
      d.cols_lo, d.cols_hi = cols_lo, cols_hi
      d.bands_lo, d.bands_hi, d.band = bands_lo, bands_hi, bands_lo
    else
      d.cols_lo, d.cols_hi = math.min(d.cols_lo, cols_lo), math.max(d.cols_hi, cols_hi)
      d.bands_lo, d.bands_hi = math.min(d.bands_lo, bands_lo), math.max(d.bands_hi, bands_hi)
      d.band = d.bands_lo
    end
  end
end

function M.region(mesh, area)
  local t = mesh.terrain
  local rows_lo, rows_hi = math.max(0, area.y0 - 1), math.min(t.height - 1, area.y1 + 2)
  local cells_lo, cells_hi = area.x0, area.x1
  local cols_lo, cols_hi = math.max(0, area.x0 - 1), math.min(t.width - 1, area.x1 + 1)
  local bands_lo = math.max(0, math.floor(area.y0 / M.BAND))
  local bands_hi = math.min(mesh.bands - 1, math.floor(area.y1 / M.BAND))
  local touched = {}
  for _, chunk in ipairs(mesh.chunks) do
    local c_lo, c_hi = math.max(cols_lo, chunk.x0), math.min(cols_hi, chunk.x1 - 1)
    if c_lo <= c_hi then
      local r_lo, r_hi = rows_lo, rows_hi
      if cells_hi < chunk.x0 or cells_lo > chunk.x1 - 1 then
        r_lo, r_hi = 1, 0
      end
      if bands_lo > bands_hi then
        c_lo, c_hi = 1, 0
      end
      merge(chunk, r_lo, r_hi, c_lo, c_hi, bands_lo, bands_hi)
      touched[#touched + 1] = chunk.index
    end
  end
  return touched
end

function M.crack_area(e, liquid)
  local zigzag = rules.CRACK_ZIGZAG_MAX
  return {
    x0 = e.x - zigzag,
    x1 = e.x + e.width - 1 + zigzag,
    y0 = e.top,
    y1 = liquid + rules.CRACK_BELOW,
  }
end

function M.crater(mesh, blast)
  local x, y, radius = blast.x, blast.y, blast.radius
  return M.region(mesh, { x0 = x - radius, x1 = x + radius, y0 = y - radius, y1 = y + radius })
end

function M.rebuild(mesh, more)
  local done = {}
  for _, chunk in ipairs(mesh.chunks) do
    local d = chunk.dirty
    if d then
      while d.rows_lo <= d.rows_hi do
        if not more("row") then
          return done
        end
        build_row(mesh, chunk, d.rows_lo)
        d.rows_lo = d.rows_lo + 1
      end
      while d.cols_lo <= d.cols_hi do
        if not more("column") then
          return done
        end
        build_column(mesh, chunk, d.cols_lo, d.band)
        if d.band < d.bands_hi then
          d.band = d.band + 1
        else
          d.band = d.bands_lo
          d.cols_lo = d.cols_lo + 1
        end
      end
      chunk.dirty = nil
      done[#done + 1] = chunk.index
    end
  end
  return done
end

function M.front(mesh, x, y)
  local t = mesh.terrain
  if x < 0 or x >= t.width or y < 0 or y >= t.height then
    return false
  end
  local part = mesh.chunks[math.floor(x / M.CHUNK) + 1].rows[y + 1]
  local pos = part.ps or part.pos
  for q = 0, part.n / 6 - 1 do
    local b = q * 18
    if (part.ns or part.nrm)[b + 3] > 0.9 and pos[b + 1] <= x and pos[b + 4] > x then
      return true
    end
  end
  return false
end

function M.busy(mesh)
  for _, chunk in ipairs(mesh.chunks) do
    if chunk.dirty then
      return true
    end
  end
  return false
end

function M.parts(chunk)
  local list = {}
  for _, part in ipairs(chunk.rows) do
    list[#list + 1] = part
  end
  for _, column in ipairs(chunk.cols) do
    for _, part in ipairs(column) do
      list[#list + 1] = part
    end
  end
  return list
end

return M

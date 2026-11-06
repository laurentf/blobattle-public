local M = {}

M.FOV = 0.6
M.TILT = -0.13
M.NEAR = 60
M.START = 165
M.ABOVE = 14
M.FOLLOW_RATE = 3
M.GLIDE_SECONDS = 0.8
M.SKY = 32

local COS, SIN = math.cos(M.TILT), math.sin(M.TILT)
local FOCAL = 1 / math.tan(M.FOV / 2)

local function far_for(r)
  local aspect = r.screen.width / r.screen.height
  local across = r.map_width * 1.1 * FOCAL / (2 * aspect)
  local up = (r.map_height + M.SKY) * 1.1 * FOCAL / 2
  return math.max(M.START, across, up)
end

local function overview(r)
  return r.distance >= r.far - 1e-6
end

function M.new(fields)
  local r = {
    map_width = fields.map_width,
    map_height = fields.map_height or 256,
    screen = fields.screen,
    x = 0,
    y = 0,
    distance = M.START,
    target_x = nil,
    target_y = nil,
    auto = true,
    glide = nil,
  }
  r.far = far_for(r)
  if fields.overview then
    r.distance = r.far
  end
  return r
end

function M.resize(r, width, height)
  local whole = overview(r)
  r.screen.width, r.screen.height = width, height
  r.far = far_for(r)
  r.distance = whole and r.far or math.min(r.distance, r.far)
end

function M.to_screen(r, wx, wy)
  local rx, ry, rz = wx - r.x, wy - r.y, -r.distance
  local vy = COS * ry + SIN * rz
  local vz = -SIN * ry + COS * rz
  local aspect = r.screen.width / r.screen.height
  local nx = rx / -vz * FOCAL / aspect
  local ny = vy / -vz * FOCAL
  return (nx + 1) / 2 * r.screen.width, (ny + 1) / 2 * r.screen.height
end

function M.to_world(r, sx, sy)
  local aspect = r.screen.width / r.screen.height
  local nx = sx / r.screen.width * 2 - 1
  local ny = sy / r.screen.height * 2 - 1
  local dx, vy, vz = nx * aspect / FOCAL, ny / FOCAL, -1
  local dy = COS * vy - SIN * vz
  local dz = SIN * vy + COS * vz
  local t = -r.distance / dz
  return r.x + t * dx, r.y + t * dy
end

function M.follow(r, x, y)
  r.target_x, r.target_y = x, y + M.ABOVE
end

function M.glide(r)
  r.glide = { x = r.x, y = r.y, t = 0 }
end

function M.update(r, dt)
  if not r.auto or r.target_x == nil then
    return
  end
  if overview(r) then
    r.glide = nil
    r.target_x = r.map_width / 2
    r.target_y = (r.map_height + M.SKY) / 2 - r.distance * SIN / COS
  end
  local g = r.glide
  if g then
    g.t = g.t + dt
    local k = math.min(1, g.t / M.GLIDE_SECONDS)
    local s = k * k * (3 - 2 * k)
    r.x = g.x + (r.target_x - g.x) * s
    r.y = g.y + (r.target_y - g.y) * s
    if k >= 1 then
      r.glide = nil
    end
    return
  end
  local k = math.min(1, dt * M.FOLLOW_RATE)
  r.x = r.x + (r.target_x - r.x) * k
  r.y = r.y + (r.target_y - r.y) * k
end

function M.place(r, x, y)
  r.x, r.y = x, y + M.ABOVE
end

function M.pan(r, drag)
  local x0, y0 = M.to_world(r, drag.x, drag.y)
  local x1, y1 = M.to_world(r, drag.x + drag.dx, drag.y + drag.dy)
  r.x, r.y = r.x + x0 - x1, r.y + y0 - y1
  r.auto = false
  r.glide = nil
end

function M.pinch(r, factor)
  r.distance = math.max(M.NEAR, math.min(r.far, r.distance / factor))
end

function M.turn(r)
  r.auto = true
end

function M.recenter(r)
  r.auto = true
end

function M.shot(r)
  r.auto = true
  r.glide = nil
end

return M

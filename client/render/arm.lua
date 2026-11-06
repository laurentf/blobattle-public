local M = {}

M.SEGMENTS = 16

local REACH_SECONDS = 0.12
local RETRACT_SECONDS = 0.18
local STIFFNESS, DAMPING = 60, 5
local KICK = 6
local BEND = 0.3
local AMPLITUDE_MAX = 2
local WAVE_RATE, WAVE_SPAN = 10, 1.5

function M.new()
  return {
    mode = "idle",
    reach = 0,
    amp = 0,
    vamp = 0,
    phase = 0,
    tip_x = 0,
    tip_y = 0,
  }
end

function M.hooked(a, x, y)
  a.mode, a.tip_x, a.tip_y, a.reach = "hooked", x, y, 0
  a.vamp = a.vamp + KICK
end

function M.missed(a, x, y)
  a.mode, a.tip_x, a.tip_y, a.reach = "missed", x, y, 0
end

function M.released(a)
  if a.mode == "hooked" then
    a.mode = "retracting"
  end
end

function M.step(a, dt, speed)
  if a.mode == "hooked" then
    a.reach = math.min(1, a.reach + dt / REACH_SECONDS)
  elseif a.mode == "missed" then
    a.reach = a.reach + dt / REACH_SECONDS
    if a.reach >= 1 then
      a.reach, a.mode = 1, "retracting"
    end
  elseif a.mode == "retracting" then
    a.reach = a.reach - dt / RETRACT_SECONDS
    if a.reach <= 0 then
      a.reach, a.mode = 0, "idle"
    end
  end
  local bend = math.min(AMPLITUDE_MAX, speed * BEND)
  a.vamp = a.vamp + (-STIFFNESS * (a.amp - bend) - DAMPING * a.vamp) * dt
  a.amp = math.max(-AMPLITUDE_MAX, math.min(AMPLITUDE_MAX, a.amp + a.vamp * dt))
  a.phase = a.phase + dt * WAVE_RATE
end

function M.points(a, from, out)
  if a.mode == "idle" then
    return 0
  end
  local from_x, from_y = from.x, from.y
  local dx, dy = (a.tip_x - from_x) * a.reach, (a.tip_y - from_y) * a.reach
  local length = math.sqrt(dx * dx + dy * dy)
  if length < 0.5 then
    return 0
  end
  local nx, ny = -dy / length, dx / length
  for i = 0, M.SEGMENTS do
    local u = i / M.SEGMENTS
    local wave = a.amp * math.sin(math.pi * u) * math.sin(a.phase - u * WAVE_SPAN * math.pi)
    local p = out[i + 1]
    if p == nil then
      p = {}
      out[i + 1] = p
    end
    p.x = from_x + dx * u + nx * wave
    p.y = from_y + dy * u + ny * wave
  end
  return M.SEGMENTS + 1
end

return M

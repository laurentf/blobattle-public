local M = {}

M.STUDIO_IN = 0.4
M.SHAKE_UNTIL = 2.9
M.STUDIO_OUT = 3.3
M.LOGO_IN = 3.5
M.LOGO_FULL = 4
M.LOGO_OUT = 5.7
M.HOME = 6.1
M.OVER = 6.5
M.SHAKE_MIN = 1
M.SHAKE_MAX = 14
M.ZOOM = 0.15
M.LOGO_POP = 0.25
M.LOGO_BOUNCES = 2.5

local function ramp(t, from, to)
  if t <= from then
    return 0
  end
  if t >= to then
    return 1
  end
  return (t - from) / (to - from)
end

function M.at(t, out)
  out = out or {}
  local build = ramp(t, 0, M.SHAKE_UNTIL)
  out.studio = ramp(t, 0, M.STUDIO_IN) * (1 - ramp(t, M.SHAKE_UNTIL, M.STUDIO_OUT))
  out.shake = M.SHAKE_MIN + (M.SHAKE_MAX - M.SHAKE_MIN) * build * build
  out.zoom = 1 + M.ZOOM * build
  local shown = ramp(t, M.LOGO_IN, M.LOGO_FULL)
  out.logo = shown * (1 - ramp(t, M.LOGO_OUT, M.HOME))
  out.logo_scale = 1 - M.LOGO_POP * (1 - shown) * math.cos(M.LOGO_BOUNCES * math.pi * shown)
  out.cover = 1 - ramp(t, M.HOME, M.OVER)
  out.home = t >= M.HOME
  out.over = t >= M.OVER
  return out
end

function M.skip(t)
  return math.max(t, M.HOME)
end

return M

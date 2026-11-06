local cat = require("shared.sim.cat")
local fixed = require("shared.sim.fixed")
local rng = require("shared.sim.rng")
local rules = require("shared.sim.rules")
local terrain = require("shared.sim.terrain")

local div, clamp = fixed.div, fixed.clamp
local max, min = math.max, math.min

local M = {}

M.LAST_SHAKE = 1 + (rules.QUAKE_SHAKES - 1) * rules.QUAKE_SHAKE_EVERY

function M.due(w)
  return w.liquid.kind == "water" and w.rounds >= rules.QUAKE_FROM
end

function M.number(w)
  return w.rounds - rules.QUAKE_FROM + 1
end

function M.strength(n)
  return min(rules.QUAKE_PUSH + rules.QUAKE_PUSH_STEP * n, rules.QUAKE_PUSH_MAX)
end

function M.offset(crack, y)
  if y < crack.top then
    return crack.path[1]
  end
  return crack.path[min(div(y - crack.top, rules.CRACK_ZIGZAG_EVERY) + 1, #crack.path)]
end

local function bottom(w)
  return min(w.liquid.level + rules.CRACK_BELOW, w.terrain.height - 1)
end

local function carve_band(w, crack, first, last)
  local t = w.terrain
  local cells, width = t.cells, t.width
  local highest = nil
  for y = 0, bottom(w) do
    local base = crack.x + M.offset(crack, y)
    local row = y * width + 1
    for x = max(base + first, 0), min(base + last, width - 1) do
      if cells[row + x] ~= terrain.AIR then
        terrain.carve(t, x, y, 0)
        if highest == nil then
          highest = y
        end
      end
    end
  end
  return highest
end

local function surface(w, x, width)
  local t = w.terrain
  local last = bottom(w)
  for y = 0, last do
    for cx = x, x + width - 1 do
      if terrain.solid(t, cx, y) then
        return y
      end
    end
  end
  return last
end

local function crack_event(w, crack, highest)
  local top = crack.top
  if highest ~= nil and highest < top then
    top = highest
  end
  w.events[#w.events + 1] = { type = "cracked", x = crack.x, width = crack.width, top = top }
end

function M.open(w, x)
  local width = rules.CRACK_WIDTH
  local top = surface(w, x, width)
  local limit = rules.CRACK_ZIGZAG_MAX
  local path = { 0 }
  for k = 2, div(bottom(w) - top, rules.CRACK_ZIGZAG_EVERY) + 1 do
    path[k] = clamp(path[k - 1] + rng.range(w.rng.sim, -limit, limit), -limit, limit)
  end
  local crack = { x = x, width = width, top = top, path = path }
  w.cracks[#w.cracks + 1] = crack
  crack_event(w, crack, carve_band(w, crack, 0, width - 1))
  return crack
end

local function widen(w, crack)
  local side = div(rules.CRACK_WIDEN, 2)
  crack.x = crack.x - side
  crack.width = crack.width + rules.CRACK_WIDEN
  local left = carve_band(w, crack, 0, side - 1)
  local right = carve_band(w, crack, crack.width - side, crack.width - 1)
  if left == nil or (right ~= nil and right < left) then
    left = right
  end
  crack_event(w, crack, left)
end

local function apart(x, width, spans)
  for _, s in ipairs(spans) do
    if
      x + width - 1 >= s.x - rules.CRACK_DISTANCE
      and x <= s.x + s.width - 1 + rules.CRACK_DISTANCE
    then
      return false
    end
  end
  return true
end

function M.crack(w)
  for _, crack in ipairs(w.cracks) do
    widen(w, crack)
  end
  local width = rules.CRACK_WIDTH
  local low = div(w.terrain.width * rules.CRACK_ZONE_START_PERCENT, 100)
  local high = div(w.terrain.width * rules.CRACK_ZONE_END_PERCENT, 100) - width
  for _ = 1, rules.CRACK_TRIES do
    local x = rng.range(w.rng.sim, low, high)
    if apart(x, width, w.wells) and apart(x, width, w.cracks) then
      return M.open(w, x)
    end
  end
  return nil
end

function M.shake(w, n)
  local push = M.strength(n)
  for _, c in ipairs(w.cats) do
    if c.alive and c.grounded then
      cat.push(c, rng.range(w.rng.sim, -push, push), -rules.QUAKE_LIFT)
    end
  end
  w.events[#w.events + 1] = { type = "shook", n = n }
end

function M.begin(w)
  w.events[#w.events + 1] = { type = "quaked", n = M.number(w) }
end

function M.act(w)
  local k = w.turn.ticks
  if k == 1 then
    M.crack(w)
  end
  if k <= M.LAST_SHAKE and fixed.mod(k - 1, rules.QUAKE_SHAKE_EVERY) == 0 then
    M.shake(w, M.number(w))
  end
end

return M

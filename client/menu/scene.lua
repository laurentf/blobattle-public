local M = {}

M.FIRST_SHELL = 2
M.SHELL_EVERY = { 4, 6 }
M.FLIGHT = 1.1
M.MISS = { 5, 9 }
M.SCARE_RADIUS = 18
M.MOOD_SECONDS = 2

function M.new(fields)
  local s = {
    random = fields.random,
    time = 0,
    next_shell = M.FIRST_SHELL,
    flying = {},
    events = {},
    blobs = {},
  }
  for i, b in ipairs(fields.blobs) do
    s.blobs[i] = { x = b.x, mood = "calm", calm_at = 0, hop = nil, shake = nil }
  end
  return s
end

local function pick(s, n)
  return math.min(n, math.floor(s.random(1, n + 1)))
end

local function nearest(s, x)
  local best = math.huge
  for _, b in ipairs(s.blobs) do
    best = math.min(best, math.abs(b.x - x))
  end
  return best
end

local function aim(s)
  local n = #s.blobs
  local first = pick(s, n)
  local side = s.random(0, 1) < 0.5 and -1 or 1
  local miss = s.random(M.MISS[1], M.MISS[2])
  for k = 0, 2 * n - 1 do
    local b = s.blobs[(first + math.floor(k / 2) - 1) % n + 1]
    local way = k % 2 == 0 and side or -side
    local to = b.x + way * miss
    local gap = nearest(s, to)
    if gap >= M.MISS[1] and gap <= M.MISS[2] then
      return to, way
    end
  end
  return s.blobs[first].x + side * miss, side
end

local function land(s, x)
  local calm = {}
  for _, b in ipairs(s.blobs) do
    if math.abs(b.x - x) <= M.SCARE_RADIUS then
      b.mood, b.calm_at, b.hop = "scared", s.time + M.MOOD_SECONDS, true
    else
      calm[#calm + 1] = b
    end
  end
  if #calm > 0 then
    local b = calm[pick(s, #calm)]
    b.mood, b.calm_at, b.shake = "angry", s.time + M.MOOD_SECONDS, true
  end
end

function M.update(s, dt)
  local events = s.events
  for i = #events, 1, -1 do
    events[i] = nil
  end
  s.time = s.time + dt
  for _, b in ipairs(s.blobs) do
    if b.mood ~= "calm" and s.time >= b.calm_at then
      b.mood = "calm"
    end
  end
  for i = #s.flying, 1, -1 do
    local f = s.flying[i]
    if s.time >= f.lands - 1e-9 then
      table.remove(s.flying, i)
      land(s, f.to)
      events[#events + 1] = { type = "boom", x = f.to }
    end
  end
  if s.time >= s.next_shell - 1e-9 then
    local to, side = aim(s)
    s.flying[#s.flying + 1] = { to = to, lands = s.time + M.FLIGHT }
    events[#events + 1] = { type = "shell", to = to, side = side, flight = M.FLIGHT }
    s.next_shell = s.time + s.random(M.SHELL_EVERY[1], M.SHELL_EVERY[2])
  end
  return events
end

return M

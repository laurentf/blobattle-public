local rules = require("shared.sim.rules")
local world = require("shared.sim.world")

local M = {}

M.MAX_LAG = 6

local TICK = 1 / rules.TICKS_PER_SECOND
local EPSILON = 1e-9

local function none() end

function M.new(fields)
  local self = {
    world = nil,
    confirmed = 0,
    result = nil,
    divergences = 0,
    checked = 0,
    restored = 0,
    rejected = 0,
    resync = nil,
  }
  local on_events = fields.on_events or none
  local by_tick, sums = {}, {}
  local ending = nil
  local acc = 0
  local cats_before, shots_before = {}, {}

  local function remember(w)
    for _, c in ipairs(w.cats) do
      local b = cats_before[c.id]
      if b == nil then
        b = {}
        cats_before[c.id] = b
      end
      b.x, b.y = c.x, c.y
    end
    for _, p in ipairs(w.projectiles) do
      local b = shots_before[p.id]
      if b == nil then
        b = {}
        shots_before[p.id] = b
      end
      b.x, b.y = p.x, p.y
    end
  end

  local function forget_before(list, tick)
    for at in pairs(list) do
      if at < tick then
        list[at] = nil
      end
    end
  end

  local function restore(data)
    local w = type(data.state) == "table" and world.restore(data.state)
    if not w or w.tick ~= data.tick then
      self.rejected = self.rejected + 1
      return
    end
    forget_before(by_tick, data.tick)
    forget_before(sums, data.tick + 1)
    self.world = w
    self.confirmed = math.max(self.confirmed, data.tick)
    self.restored = self.restored + 1
    self.resync = nil
    acc = 0
    remember(w)
  end

  function self.receive(m)
    local data = m.data
    if m.name == "game_start" then
      self.world = assert(world.new(data.seed, data.settings))
      self.start, self.confirmed, self.result, ending, acc = data, 0, nil, nil, 0
      forget_before(by_tick, math.huge)
      forget_before(sums, math.huge)
      remember(self.world)
    elseif m.name == "ticks" then
      local from = self.world and self.world.tick or 0
      for _, entry in ipairs(data.inputs) do
        if entry.at >= from then
          local list = by_tick[entry.at]
          if list == nil then
            list = {}
            by_tick[entry.at] = list
          end
          list[#list + 1] = entry.input
        end
      end
      self.confirmed = data.to
    elseif m.name == "checksum" then
      sums[data.tick] = data.sum
    elseif m.name == "snapshot" then
      restore(data)
    elseif m.name == "game_end" then
      ending = data
    end
  end

  local function step(w)
    remember(w)
    local at = w.tick
    local inputs = by_tick[at]
    local events = world.step(w, inputs)
    by_tick[at] = nil
    local sum = sums[w.tick]
    if sum then
      local a, b = world.checksum(w)
      if a ~= sum[1] or b ~= sum[2] then
        self.divergences = self.divergences + 1
        self.resync = self.resync or w.tick
      end
      self.checked = self.checked + 1
      sums[w.tick] = nil
    end
    on_events(events, inputs)
  end

  function self.advance(dt)
    local w = self.world
    if w == nil then
      return 0
    end
    acc = acc + dt
    while w.tick < self.confirmed do
      local late = self.confirmed - w.tick > M.MAX_LAG
      if acc >= TICK - EPSILON then
        acc = acc - TICK
      elseif not late then
        break
      end
      step(w)
    end
    if w.tick >= self.confirmed then
      acc = math.min(acc, TICK)
      if ending and self.result == nil and w.turn.state == "ended" then
        self.result = ending
      end
    end
    return math.max(0, math.min(1, acc / TICK))
  end

  function self.before(id)
    return cats_before[id]
  end

  function self.before_shot(id)
    return shots_before[id]
  end

  return self
end

return M

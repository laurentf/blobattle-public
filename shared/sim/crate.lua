local explosion = require("shared.sim.explosion")
local fixed = require("shared.sim.fixed")
local rng = require("shared.sim.rng")
local rules = require("shared.sim.rules")
local terrain = require("shared.sim.terrain")
local weapons = require("shared.sim.weapons.registry")

local div, clamp = fixed.div, fixed.clamp
local FP = fixed.FP

local M = {}

local HALF = div(rules.CRATE_SIZE, 2)

function M.new(fields)
  return {
    id = fields.id,
    weapon = fields.weapon,
    x = fields.x,
    y = fields.y,
    vx = fields.vx or 0,
    vy = fields.vy or 0,
    chute = fields.chute,
    fuse = -1,
    alive = true,
  }
end

function M.pixel(k)
  return div(k.x, FP), div(k.y, FP)
end

local function box_free(t, px, py)
  for y = py - rules.CRATE_SIZE + 1, py do
    for x = px - HALF, px - HALF + rules.CRATE_SIZE - 1 do
      if terrain.solid(t, x, y) then
        return false
      end
    end
  end
  return true
end

local function supported(t, px, py)
  for x = px - HALF, px - HALF + rules.CRATE_SIZE - 1 do
    if terrain.solid(t, x, py + 1) then
      return true
    end
  end
  return false
end

local function landing_column(w, x)
  for y = 0, w.liquid.level - 1 do
    if terrain.solid(w.terrain, x, y) then
      return true
    end
  end
  return false
end

function M.due(w)
  local played = 0
  for _, team in ipairs(w.teams) do
    played = played + team.turns
  end
  if fixed.mod(played + 1, rules.CRATE_EVERY) ~= 0 then
    return false
  end
  local count = 0
  for _, k in ipairs(w.crates) do
    if k.alive then
      count = count + 1
    end
  end
  return count < rules.CRATE_MAX
end

function M.drop(w)
  if not M.due(w) then
    return nil
  end
  local s, width = w.rng.sim, w.terrain.width
  local column = nil
  for _ = 1, rules.CRATE_TRIES do
    local x = rng.range(s, rules.CRATE_EDGE, width - 1 - rules.CRATE_EDGE)
    if landing_column(w, x) then
      column = x
      break
    end
  end
  if column == nil then
    return nil
  end
  local weapon = rules.CRATE_WEAPONS[rng.range(s, 1, #rules.CRATE_WEAPONS)]
  local k = M.new({
    id = w.next_crate,
    weapon = weapon,
    x = column * FP + div(FP, 2),
    y = -FP,
    vx = w.wind * rules.CRATE_DRIFT,
    vy = rules.CRATE_FALL,
    chute = true,
  })
  w.next_crate = w.next_crate + 1
  w.crates[#w.crates + 1] = k
  w.events[#w.events + 1] = { type = "crate_dropped", crate = k.id, x = column }
  return k
end

local function drift(t, k)
  local remaining = k.vx
  while remaining ~= 0 do
    local step = clamp(remaining, -FP, FP)
    local nx = k.x + step
    if div(nx, FP) ~= div(k.x, FP) and not box_free(t, div(nx, FP), div(k.y, FP)) then
      k.vx = 0
      return
    end
    k.x = nx
    remaining = remaining - step
  end
end

local function fall(t, k, events)
  local remaining = k.vy
  while remaining > 0 do
    local step = clamp(remaining, 0, FP)
    local px, py = M.pixel(k)
    if div(k.y + step, FP) ~= py and supported(t, px, py) then
      k.y = py * FP
      k.vx, k.vy = 0, 0
      if k.chute then
        k.chute = false
        events[#events + 1] = { type = "crate_landed", crate = k.id }
      end
      return
    end
    k.y = k.y + step
    remaining = remaining - step
  end
end

local function lost(env, k)
  local px, py = M.pixel(k)
  local centre = py - div(rules.CRATE_SIZE, 2)
  return centre >= env.liquid
    or px < -rules.OUT_MARGIN
    or px >= env.terrain.width + rules.OUT_MARGIN
end

function M.blow(env, crates)
  local due = env.due_crates
  if due == nil then
    due = {}
    env.due_crates = due
  end
  local count = 0
  for _, k in ipairs(crates) do
    if k.alive and k.fuse > 0 then
      count = count + 1
      due[count] = k
    end
  end
  for i = 1, count do
    local k = due[i]
    local px, py = M.pixel(k)
    k.alive = false
    env.events[#env.events + 1] = { type = "crate_destroyed", crate = k.id }
    explosion.apply(env, { x = px, y = py - 2, spec = rules.CRATE_BLAST })
    due[i] = nil
  end
end

function M.drown(k, fields)
  if k.alive and lost(fields, k) then
    k.alive = false
    fields.events[#fields.events + 1] = { type = "crate_lost", crate = k.id }
  end
end

function M.step(env, k)
  if not k.alive then
    return
  end
  local t, events = env.terrain, env.events
  local px, py = M.pixel(k)
  if k.chute then
    drift(t, k)
    fall(t, k, events)
  elseif k.vy > 0 or not supported(t, px, py) then
    k.vy = clamp(k.vy + rules.GRAVITY, 0, rules.MAX_AXIS_SPEED)
    fall(t, k, events)
  end
  if lost(env, k) then
    k.alive = false
    events[#events + 1] = { type = "crate_lost", crate = k.id }
  end
end

function M.at_rest(k)
  return not k.alive or (not k.chute and k.vy == 0 and k.fuse < 0)
end

local function touches(k, px, py)
  local kx, ky = M.pixel(k)
  return fixed.abs(px - kx) < rules.CRATE_SIZE
    and py - rules.CAT_HEIGHT + 1 <= ky
    and ky - rules.CRATE_SIZE + 1 <= py
end

function M.pick(w, c)
  if c == nil or not c.alive then
    return
  end
  local px, py = div(c.x, FP), div(c.y, FP)
  for _, k in ipairs(w.crates) do
    if k.alive and k.fuse < 0 and touches(k, px, py) then
      k.alive = false
      local ammo = w.teams[c.team].ammo
      local slot = weapons.index_of(k.weapon)
      if ammo[slot] >= 0 then
        ammo[slot] = ammo[slot] + 1
      end
      w.events[#w.events + 1] =
        { type = "crate_picked", crate = k.id, cat = c.id, weapon = k.weapon }
    end
  end
end

function M.freeze(k, events)
  if not k.alive then
    return
  end
  if k.fuse > 0 then
    k.alive = false
    events[#events + 1] = { type = "crate_lost", crate = k.id }
    return
  end
  k.chute, k.vx, k.vy = false, 0, 0
end

return M

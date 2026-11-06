local weapons = require("shared.sim.weapons.registry")

local M = {}

M.REST = { vx = 0, vy = 0, walk = 0 }

local SHOT_KICK, STRIKE_KICK = 4, 12
local STIFFNESS = 170
local DAMPING = 9
local STRETCH_PER_SPEED = 0.09
local STRETCH_MIN, STRETCH_MAX = -0.25, 0.35
local BREATH, BREATH_RATE = 0.025, 2.6
local WALK_BOB, WALK_RATE = 0.06, 22
local LEAN_PER_SPEED, LEAN_WALK, LEAN_RATE = 0.08, 0.12, 10
local WOBBLE_MAX, WOBBLE_BASE, WOBBLE_PER_DAMAGE, WOBBLE_FADE, WOBBLE_RATE =
  1.4, 0.5, 1 / 60, 2.5, 18
local MIN_HEIGHT = 0.45
local PUDDLE_X, PUDDLE_Y = 1.5, 0.2

function M.new(phase)
  return { s = 1, vs = 0, lean = 0, wob = 0, phase = phase, time = 0, dead = false }
end

function M.event(j, e)
  if j.dead then
    return
  end
  if e.type == "landed" or e.type == "rebounded" then
    j.vs = j.vs - 5
  elseif e.type == "damaged" then
    j.wob = math.min(WOBBLE_MAX, j.wob + WOBBLE_BASE + e.amount * WOBBLE_PER_DAMAGE)
    j.vs = j.vs - 3
  elseif e.type == "fired" then
    local weapon = e.weapon and weapons.get(e.weapon)
    j.vs = j.vs + (weapon and weapon.kind == "melee" and STRIKE_KICK or SHOT_KICK)
  elseif e.type == "died" then
    j.dead = true
  end
end

function M.step(j, dt, motion)
  if j.dead then
    return
  end
  j.time = j.time + dt
  local t = j.time
  local stretch = math.max(STRETCH_MIN, math.min(STRETCH_MAX, -motion.vy * STRETCH_PER_SPEED))
  local target = 1 + stretch + math.sin(t * BREATH_RATE + j.phase) * BREATH
  if motion.walk ~= 0 then
    target = target + math.sin(t * WALK_RATE) * WALK_BOB
  end
  local acc = -STIFFNESS * (j.s - target) - DAMPING * j.vs
  j.vs = j.vs + acc * dt
  j.s = j.s + j.vs * dt
  local lean = -motion.vx * LEAN_PER_SPEED - motion.walk * LEAN_WALK
  j.lean = j.lean + (lean - j.lean) * math.min(1, dt * LEAN_RATE)
  j.wob = j.wob * math.max(0, 1 - dt * WOBBLE_FADE)
end

function M.shape(j, out)
  out = out or {}
  if j.dead then
    out.sx, out.sy, out.lean, out.wobble, out.phase, out.dead = PUDDLE_X, PUDDLE_Y, 0, 0, 0, true
    return out
  end
  local sy = math.max(MIN_HEIGHT, j.s)
  out.sx = 1 / math.sqrt(sy)
  out.sy = sy
  out.lean = j.lean
  out.wobble = j.wob
  out.phase = j.time * WOBBLE_RATE + j.phase
  out.dead = false
  return out
end

return M

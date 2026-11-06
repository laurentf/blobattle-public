local fixed = require("shared.sim.fixed")
local rules = require("shared.sim.rules")
local terrain = require("shared.sim.terrain")
local trig = require("shared.sim.trig")

local div, clamp, round_div = fixed.div, fixed.clamp, fixed.round_div
local max = math.max
local FP = fixed.FP

local M = {}

local HALF = div(rules.CAT_WIDTH, 2)
local CENTRE_X = div(FP, 2)
local CENTRE_Y = div(rules.CAT_HEIGHT * FP, 2) - FP
local ANCHOR_X = CENTRE_X + div(FP, 2)
local ANCHOR_Y = CENTRE_Y + div(FP, 2)

function M.new(fields)
  return {
    id = fields.id,
    team = fields.team,
    index = fields.index,
    x = fields.px * FP + div(FP, 2),
    y = fields.py * FP,
    vx = 0,
    vy = 0,
    hp = rules.CAT_HP,
    alive = true,
    grounded = false,
    facing = 1,
    walk = 0,
    walk_clock = 0,
    nudge = 0,
    gauge = rules.GAUGE,
    hanging = false,
    anchor_x = 0,
    anchor_y = 0,
    rope = 0,
    climb = 0,
    dig = 0,
    dig_angle = 0,
    jet = 0,
    hurt = false,
  }
end

function M.pixel(c)
  return div(c.x, FP), div(c.y, FP)
end

function M.center(c)
  local px, py = M.pixel(c)
  return px, py - div(rules.CAT_HEIGHT, 2)
end

function M.muzzle(c)
  local px, py = M.pixel(c)
  return px * FP, (2 * py + 2 - rules.CAT_HEIGHT) * div(FP, 2)
end

function M.feet(c)
  local px, py = M.pixel(c)
  return px * FP + c.facing * div(FP, 2), py * FP
end

function M.box_free(t, px, py)
  for y = py - rules.CAT_HEIGHT + 1, py do
    for x = px - HALF, px - HALF + rules.CAT_WIDTH - 1 do
      if terrain.solid(t, x, y) then
        return false
      end
    end
  end
  return true
end

function M.supported(t, px, py)
  for x = px - HALF, px - HALF + rules.CAT_WIDTH - 1 do
    if terrain.solid(t, x, py + 1) then
      return true
    end
  end
  return false
end

function M.contains(c, x, y)
  local px, py = M.pixel(c)
  return x >= px - HALF
    and x < px - HALF + rules.CAT_WIDTH
    and y > py - rules.CAT_HEIGHT
    and y <= py
end

local function place(c, px, py)
  c.x = px * FP + (c.x - div(c.x, FP) * FP)
  c.y = py * FP
end

local function start_falling(c)
  c.grounded = false
  c.vx = 0
  c.vy = 0
  c.nudge = rules.AIR_NUDGE
end

function M.damage(c, hurt, events)
  if hurt.amount <= 0 then
    return
  end
  c.hp = c.hp - hurt.amount
  c.hurt = true
  events[#events + 1] = { type = "damaged", cat = c.id, amount = hurt.amount, cause = hurt.cause }
end

local function foothold(t, nx, py)
  for up = 0, rules.STEP_UP do
    local ny = py - up
    if M.box_free(t, nx, ny) then
      if M.supported(t, nx, ny) then
        return ny, true
      end
      for down = 1, rules.STEP_DOWN do
        if not M.box_free(t, nx, ny + down) then
          break
        end
        if M.supported(t, nx, ny + down) then
          return ny + down, true
        end
      end
      return ny, false
    end
  end
  return nil, false
end

local function walk(c, t)
  c.walk_clock = c.walk_clock + 1
  if c.walk_clock < rules.WALK_TICKS then
    return
  end
  c.walk_clock = 0
  if c.gauge < rules.GAUGE_WALK then
    return
  end
  local px, py = M.pixel(c)
  local nx = px + c.walk
  local ny, standing = foothold(t, nx, py)
  if ny == nil then
    return
  end
  c.gauge = c.gauge - rules.GAUGE_WALK
  place(c, nx, ny)
  if not standing then
    start_falling(c)
  end
end

local function thrown(c)
  return c.vx > rules.THROWN_VX or c.vx < -rules.THROWN_VX
end

local function percent(value, pct)
  return round_div(value * pct, 100)
end

local function knock(c, cats, events)
  if cats == nil or not thrown(c) then
    return false
  end
  local px, py = M.pixel(c)
  local reach = (rules.CAT_WIDTH + 1) * FP
  for _, d in ipairs(cats) do
    local near = d.x - c.x < reach and c.x - d.x < reach
    local qx, qy = M.pixel(d)
    local close = fixed.abs(qx - px) < rules.CAT_WIDTH and fixed.abs(qy - py) < rules.CAT_HEIGHT
    if near and d ~= c and d.alive and d.dig == 0 and close and (qx - px) * (c.vx - d.vx) > 0 then
      local sx = percent(c.vx - d.vx, rules.BUMP_SHARE)
      local sy = percent(c.vy - d.vy, rules.BUMP_SHARE)
      M.release(d, events)
      d.vx, d.vy = d.vx + sx, math.min(d.vy + sy, -rules.BUMP_LIFT)
      d.grounded = false
      d.nudge = rules.AIR_NUDGE
      c.vx, c.vy = c.vx - sx, c.vy - sy
      return true
    end
  end
  return false
end

local function skid(c, t, cats, events)
  local remaining = c.vx
  while remaining ~= 0 do
    local step = clamp(remaining, -FP, FP)
    local nx = c.x + step
    local px, py = M.pixel(c)
    local npx = div(nx, FP)
    if npx ~= px then
      local ny, standing = foothold(t, npx, py)
      if ny == nil then
        c.vx = 0
        return
      end
      c.x, c.y = nx, ny * FP
      if not standing then
        c.grounded = false
        c.vy = 0
        c.nudge = rules.AIR_NUDGE
        return true
      end
    else
      c.x = nx
    end
    if knock(c, cats, events) then
      if c.vy == 0 then
        return false
      end
      c.grounded = false
      c.nudge = rules.AIR_NUDGE
      return true
    end
    remaining = remaining - step
  end
  if c.vx > rules.SLIDE_FRICTION then
    c.vx = c.vx - rules.SLIDE_FRICTION
  elseif c.vx < -rules.SLIDE_FRICTION then
    c.vx = c.vx + rules.SLIDE_FRICTION
  else
    c.vx = 0
  end
end

local function hurt_by_fall(c, impact, events)
  if impact > rules.FALL_SAFE_SPEED then
    local amount = div((impact - rules.FALL_SAFE_SPEED) * rules.FALL_DAMAGE_PER_256, FP)
    M.damage(c, { amount = amount, cause = "fall" }, events)
  end
end

local function land(c, events)
  local impact = c.vy
  c.grounded = true
  c.vx = thrown(c) and percent(c.vx, rules.SLIDE_KEEP) or 0
  c.vy = 0
  c.y = div(c.y, FP) * FP
  events[#events + 1] = { type = "landed", cat = c.id }
  hurt_by_fall(c, impact, events)
end

local function rebound(c, events)
  local impact = c.vy
  c.vy = -percent(impact, rules.GROUND_BOUNCE)
  c.vx = percent(c.vx, rules.BOUNCE_KEEP_VX)
  c.y = div(c.y, FP) * FP
  c.nudge = rules.AIR_NUDGE
  events[#events + 1] = { type = "rebounded", cat = c.id }
  hurt_by_fall(c, impact, events)
end

local function lift(t, px, py, budget)
  for k = 1, budget do
    if M.box_free(t, px, py - k) then
      return -k, k
    end
  end
  for k = 1, budget do
    if M.box_free(t, px, py + k) then
      return k, k
    end
  end
  return nil, 0
end

local function slide(t, px, py, budget)
  for k = 1, budget do
    if M.box_free(t, px + k, py) then
      return k, k
    end
    if M.box_free(t, px - k, py) then
      return -k, k
    end
  end
  return nil, 0
end

local function fly(c, t, events, cats)
  c.vy = clamp(c.vy + rules.GRAVITY, -rules.MAX_AXIS_SPEED, rules.MAX_AXIS_SPEED)
  c.vx = clamp(c.vx, -rules.MAX_AXIS_SPEED, rules.MAX_AXIS_SPEED)
  local remaining = c.vx
  while remaining ~= 0 do
    local step = clamp(remaining, -FP, FP)
    local nx = c.x + step
    local _, py = M.pixel(c)
    local dy, spent = 0, 0
    if not M.box_free(t, div(nx, FP), py) then
      dy, spent = lift(t, div(nx, FP), py, c.nudge)
    end
    if dy then
      c.nudge = c.nudge - spent
      c.x = nx
      c.y = c.y + dy * FP
      remaining = remaining - step
      if knock(c, cats, events) then
        remaining = 0
      end
    else
      c.vx = thrown(c) and -percent(c.vx, rules.WALL_BOUNCE) or 0
      remaining = 0
    end
  end
  remaining = c.vy
  while remaining ~= 0 do
    local step = clamp(remaining, -FP, FP)
    local ny = c.y + step
    local px = div(c.x, FP)
    local dx, spent = nil, 0
    if M.box_free(t, px, div(ny, FP)) then
      dx = 0
    elseif step < 0 then
      dx, spent = slide(t, px, div(ny, FP), c.nudge)
    end
    if dx then
      c.nudge = c.nudge - spent
      c.x = c.x + dx * FP
      c.y = ny
      remaining = remaining - step
      if knock(c, cats, events) then
        remaining = 0
      end
    elseif step > 0 and thrown(c) and c.vy > rules.BOUNCE_VY then
      rebound(c, events)
      remaining = 0
    elseif step > 0 then
      land(c, events)
      return
    else
      c.vy = 0
      remaining = 0
    end
  end
  local px, py = M.pixel(c)
  if c.vy >= 0 and M.supported(t, px, py) and not c.grounded then
    if thrown(c) and c.vy > rules.BOUNCE_VY then
      rebound(c, events)
    else
      land(c, events)
    end
  end
end

function M.release(c, events)
  if not c.hanging then
    return false
  end
  c.hanging = false
  c.climb = 0
  c.grounded = false
  c.nudge = rules.AIR_NUDGE
  events[#events + 1] = { type = "tentacle_released", cat = c.id }
  return true
end

local function rope_offset(c)
  return c.x - c.anchor_x * FP - ANCHOR_X, c.y - c.anchor_y * FP - ANCHOR_Y
end

local function cell(v, side)
  local q = div(v, FP)
  if side < 0 and q * FP == v then
    return q - 1
  end
  return q
end

local function hook(c, ax, ay, events)
  c.hanging = true
  c.grounded = false
  c.anchor_x, c.anchor_y = ax, ay
  local dx, dy = rope_offset(c)
  c.rope = clamp(fixed.isqrt(dx * dx + dy * dy), rules.ROPE_MIN * FP, rules.ROPE_MAX * FP)
  events[#events + 1] = { type = "tentacle_hooked", cat = c.id, x = ax, y = ay }
end

function M.grapple(c, fields)
  local cost = c.grounded and rules.GAUGE_TENTACLE or rules.GAUGE_TENTACLE_AIR
  if c.hanging or c.gauge < cost then
    return false
  end
  c.gauge = c.gauge - cost
  local cos, sin = trig.cos(fields.angle), trig.sin(fields.angle)
  local side = fixed.sign(cos)
  if side == 0 then
    side = c.facing
  end
  local ox, oy = c.x - CENTRE_X, c.y - CENTRE_Y
  local cx, cy = 0, 0
  for k = 1, rules.TENTACLE_RANGE do
    cx = cell(ox + round_div(k * FP * cos, trig.SCALE), side)
    cy = div(oy - round_div(k * FP * sin, trig.SCALE), FP)
    if terrain.solid(fields.terrain, cx, cy) then
      hook(c, cx, cy, fields.events)
      return true
    end
  end
  fields.events[#fields.events + 1] = { type = "tentacle_missed", cat = c.id, x = cx, y = cy }
  return true
end

local function push_along(c, dx, dy)
  local tx, ty = -dy, dx
  if tx * c.walk < 0 then
    tx, ty = dy, -dx
  end
  if tx == 0 then
    return
  end
  local d = fixed.isqrt(dx * dx + dy * dy)
  c.vx = c.vx + round_div(rules.SWING_PUSH * tx, d)
  c.vy = c.vy + round_div(rules.SWING_PUSH * ty, d)
end

local function travel(c, t, mx, my)
  local x0, y0 = c.x, c.y
  local blocked, bounced_x, bounced_y = false, false, false
  local remaining = mx
  while remaining ~= 0 do
    local step = clamp(remaining, -FP, FP)
    local nx = c.x + step
    local px, py = M.pixel(c)
    if div(nx, FP) ~= px and not M.box_free(t, div(nx, FP), py) then
      blocked, bounced_x = true, fixed.sign(c.vx) == fixed.sign(step)
      if bounced_x then
        c.vx = percent(-c.vx, rules.ROPE_BOUNCE)
      end
      break
    end
    c.x = nx
    remaining = remaining - step
  end
  remaining = my
  while remaining ~= 0 do
    local step = clamp(remaining, -FP, FP)
    local ny = c.y + step
    local px, py = M.pixel(c)
    if div(ny, FP) ~= py and not M.box_free(t, px, div(ny, FP)) then
      blocked, bounced_y = true, fixed.sign(c.vy) == fixed.sign(step)
      if bounced_y then
        c.vy = percent(-c.vy, rules.ROPE_BOUNCE)
      end
      break
    end
    c.y = ny
    remaining = remaining - step
  end
  if not blocked then
    return
  end
  if not bounced_x then
    c.vx = c.x - x0
  end
  if not bounced_y then
    c.vy = c.y - y0
  end
end

local function slacken(c, ox, oy)
  local outward = c.vx * ox + c.vy * oy
  if outward <= 0 then
    return
  end
  local square = ox * ox + oy * oy
  c.vx = c.vx - round_div(outward * ox, square)
  c.vy = c.vy - round_div(outward * oy, square)
end

local function turn_faster(c, ox, oy, before)
  local square = ox * ox + oy * oy
  local along = c.vx * ox + c.vy * oy
  local rx, ry = round_div(along * ox, square), round_div(along * oy, square)
  c.vx = rx + round_div((c.vx - rx) * before, c.rope)
  c.vy = ry + round_div((c.vy - ry) * before, c.rope)
end

local function swing(c, t, events)
  c.gauge = max(0, c.gauge - rules.GAUGE_HANG)
  if c.gauge == 0 then
    M.release(c, events)
    return false
  end
  local before = c.rope
  c.rope = clamp(c.rope + c.climb * rules.ROPE_STEP, rules.ROPE_MIN * FP, rules.ROPE_MAX * FP)
  local dx, dy = rope_offset(c)
  if c.rope ~= before and dx * dx + dy * dy >= before * before then
    turn_faster(c, dx, dy, before)
  end
  c.vy = c.vy + rules.GRAVITY
  if c.walk ~= 0 then
    push_along(c, dx, dy)
  end
  c.vx = clamp(c.vx, -rules.MAX_AXIS_SPEED, rules.MAX_AXIS_SPEED)
  c.vy = clamp(c.vy, -rules.MAX_AXIS_SPEED, rules.MAX_AXIS_SPEED)
  local rope2 = c.rope * c.rope
  if dx * dx + dy * dy >= rope2 then
    slacken(c, dx, dy)
  end
  local nx, ny = dx + c.vx, dy + c.vy
  local reach = nx * nx + ny * ny
  if reach > rope2 then
    local d = fixed.isqrt(reach)
    nx, ny = round_div(nx * c.rope, d), round_div(ny * c.rope, d)
    slacken(c, nx, ny)
  end
  travel(c, t, nx - dx, ny - dy)
  c.vx = clamp(c.vx, -rules.MAX_AXIS_SPEED, rules.MAX_AXIS_SPEED)
  c.vy = clamp(c.vy, -rules.MAX_AXIS_SPEED, rules.MAX_AXIS_SPEED)
  return true
end

local function stop_jet(c, events)
  c.jet = 0
  c.climb = 0
  events[#events + 1] = { type = "jet_ended", cat = c.id }
end

function M.cut(c, events)
  if c.jet == 0 then
    return false
  end
  stop_jet(c, events)
  return true
end

function M.ignite(c, events)
  if not c.alive or c.hanging or c.jet > 0 then
    return false
  end
  c.jet = rules.JET_FUEL
  c.climb = 0
  c.grounded = false
  c.vy = -rules.JET_LIFT
  c.nudge = rules.AIR_NUDGE
  events[#events + 1] = { type = "jet_started", cat = c.id }
  return true
end

local function thrust(c, events)
  local pushed = false
  if c.climb < 0 then
    c.vy = max(c.vy - rules.JET_UP, -rules.JET_MAX_UP)
    pushed = true
  end
  if c.walk ~= 0 then
    local ahead = c.walk * c.vx
    if ahead < rules.JET_MAX_SIDE then
      c.vx = c.walk * math.min(ahead + rules.JET_SIDE, rules.JET_MAX_SIDE)
    end
    c.facing = c.walk
    pushed = true
  end
  if pushed then
    c.jet = c.jet - 1
    if c.jet == 0 then
      stop_jet(c, events)
    end
  end
end

local function drown(c, t, liquid, events)
  local cx, cy = M.center(c)
  if cy >= liquid or cx < 0 or cx >= t.width then
    M.release(c, events)
    M.cut(c, events)
    c.dig = 0
    c.alive = false
    c.hp = 0
    events[#events + 1] = { type = "died", cat = c.id, cause = "liquid" }
    return true
  end
  return false
end

local function inside(t, px, py)
  return px - HALF >= 0
    and px - HALF + rules.CAT_WIDTH <= t.width
    and py - rules.CAT_HEIGHT + 1 >= 0
    and py < t.height
end

local function chew(c, t, events)
  local k = rules.DIG_TICKS - c.dig + 1
  local cos, sin = trig.cos(c.dig_angle), trig.sin(c.dig_angle)
  local span, every = rules.DIG_PIXELS * FP, rules.DIG_EVERY * trig.SCALE
  local nx = c.x + round_div(k * span * cos, every) - round_div((k - 1) * span * cos, every)
  local ny = c.y - round_div(k * span * sin, every) + round_div((k - 1) * span * sin, every)
  if not inside(t, div(nx, FP), div(ny, FP)) then
    c.dig = 0
    start_falling(c)
    return
  end
  local side = fixed.sign(cos)
  if side == 0 then
    side = c.facing
  end
  local bx, by = cell(nx - CENTRE_X, side), div(ny - CENTRE_Y, FP)
  terrain.carve(t, bx, by, rules.DIG_RADIUS)
  events[#events + 1] = { type = "chomped", cat = c.id, x = bx, y = by, radius = rules.DIG_RADIUS }
  c.x, c.y = nx, ny
  c.dig = c.dig - 1
  if c.dig == 0 then
    start_falling(c)
  end
end

function M.burrow(c, angle)
  local side = fixed.sign(trig.cos(angle))
  if side ~= 0 then
    c.facing = side
  end
  c.dig = rules.DIG_TICKS
  c.dig_angle = angle
  c.grounded = false
  c.vx, c.vy = 0, 0
  return true
end

function M.drown(c, fields)
  return drown(c, fields.terrain, fields.liquid, fields.events)
end

function M.set_walk(c, direction)
  c.walk = direction
  c.walk_clock = 0
  if direction ~= 0 then
    c.facing = direction
  end
end

function M.set_climb(c, direction)
  if not c.hanging and c.jet == 0 then
    return false
  end
  c.climb = direction
  return true
end

function M.jump(c, direction, events)
  if M.cut(c, events) then
    return true
  end
  if M.release(c, events) then
    if c.gauge >= rules.GAUGE_JUMP then
      c.gauge = c.gauge - rules.GAUGE_JUMP
      c.facing = direction
      c.vx = c.vx + direction * rules.JUMP_VX
      c.vy = c.vy + rules.JUMP_VY
    end
    return true
  end
  if not c.grounded or c.gauge < rules.GAUGE_JUMP then
    return false
  end
  c.gauge = c.gauge - rules.GAUGE_JUMP
  c.facing = direction
  c.grounded = false
  c.vx = direction * rules.JUMP_VX
  c.vy = rules.JUMP_VY
  c.nudge = rules.AIR_NUDGE
  return true
end

function M.push(c, vx, vy)
  c.grounded = false
  c.vx = vx
  c.vy = vy
  c.nudge = rules.AIR_NUDGE
end

function M.step(c, t, liquid, events, cats)
  if not c.alive then
    return
  end
  if c.dig > 0 then
    chew(c, t, events)
    drown(c, t, liquid, events)
    return
  end
  if c.hanging and swing(c, t, events) then
    drown(c, t, liquid, events)
    return
  end
  if c.jet > 0 then
    thrust(c, events)
    fly(c, t, events, cats)
    if c.grounded then
      M.cut(c, events)
    end
    drown(c, t, liquid, events)
    return
  end
  local took_off = false
  if c.grounded then
    local px, py = M.pixel(c)
    if not M.supported(t, px, py) then
      start_falling(c)
    elseif c.vx ~= 0 then
      took_off = skid(c, t, cats, events)
    elseif c.walk ~= 0 then
      walk(c, t)
    end
  end
  if not c.grounded and not took_off then
    fly(c, t, events, cats)
  end
  drown(c, t, liquid, events)
end

function M.at_rest(c)
  return not c.alive or (c.grounded and not c.hanging and c.vx == 0 and c.vy == 0)
end

return M

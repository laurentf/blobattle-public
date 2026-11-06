local cat = require("shared.sim.cat")
local fixed = require("shared.sim.fixed")
local rules = require("shared.sim.rules")
local terrain = require("shared.sim.terrain")
local trig = require("shared.sim.trig")

local div, round_div, clamp, abs = fixed.div, fixed.round_div, fixed.clamp, fixed.abs
local max, min = math.max, math.min
local FP = fixed.FP

local M = {}

function M.new(fields)
  return {
    id = fields.id,
    weapon = fields.weapon,
    owner = fields.owner,
    x = fields.x,
    y = fields.y,
    vx = fields.vx,
    vy = fields.vy,
    age = 0,
    fuse = fields.fuse or -1,
    facing = fields.facing or 0,
    resting = false,
    alive = true,
  }
end

function M.launch_velocity(angle, power)
  local speed = div(rules.LAUNCH_MAX_SPEED * power, rules.POWER_MAX)
  return round_div(speed * trig.cos(angle), trig.SCALE),
    round_div(-speed * trig.sin(angle), trig.SCALE)
end

local function out_of_play(env, px, py)
  return py >= env.liquid or px < -rules.OUT_MARGIN or px >= env.terrain.width + rules.OUT_MARGIN
end

local function gather_nearby(env, p, x1, y1)
  local near = env.near
  if near == nil then
    near = {}
    env.near = near
  end
  local count = 0
  local reach = rules.CAT_WIDTH + rules.CAT_HEIGHT
  local left, right = div(min(p.x, x1), FP) - reach, div(max(p.x, x1), FP) + reach
  local top, bottom = div(min(p.y, y1), FP) - reach, div(max(p.y, y1), FP) + reach
  for _, c in ipairs(env.cats) do
    if c.alive and not (c.id == p.owner and p.age <= rules.OWNER_GRACE_TICKS) then
      local cx, cy = cat.pixel(c)
      if cx >= left and cx <= right and cy >= top and cy <= bottom then
        count = count + 1
        near[count] = c
      end
    end
  end
  return near, count
end

local function hit_cat(near, count, px, py)
  for i = 1, count do
    if cat.contains(near[i], px, py) then
      return near[i]
    end
  end
  return nil
end

local function surface_normal(t, px, py)
  local nx, ny = 0, 0
  for dy = -2, 2 do
    for dx = -2, 2 do
      if terrain.solid(t, px + dx, py + dy) then
        nx = nx - dx
        ny = ny - dy
      end
    end
  end
  return nx, ny
end

local function bounce(env, p, weapon, px, py)
  local nx, ny = surface_normal(env.terrain, px, py)
  local restitution, friction = weapon.bounce.restitution, weapon.bounce.friction
  if nx == 0 and ny == 0 then
    p.vx = round_div(-p.vx * restitution, 100)
    p.vy = round_div(-p.vy * restitution, 100)
  else
    local dot = p.vx * nx + p.vy * ny
    if dot < 0 then
      local nn = nx * nx + ny * ny
      local vnx, vny = round_div(dot * nx, nn), round_div(dot * ny, nn)
      local tx, ty = p.vx - vnx, p.vy - vny
      p.vx = round_div(tx * friction, 100) - round_div(vnx * restitution, 100)
      p.vy = round_div(ty * friction, 100) - round_div(vny * restitution, 100)
    end
  end
  env.events[#env.events + 1] = { type = "bounced", projectile = p.id }
  if abs(p.vx) + abs(p.vy) < rules.REST_SPEED then
    p.vx, p.vy = 0, 0
    p.resting = true
  end
end

local function impact(env, p, weapon, hit)
  if weapon.on_impact then
    weapon.on_impact(env.api, p, hit)
    return
  end
  env.api.explode({ x = hit.x, y = hit.y, spec = weapon.explosion })
  env.api.remove_projectile(p)
end

local function timer(env, p, weapon)
  local at = { x = div(p.x, FP), y = div(p.y, FP) }
  if weapon.on_timer then
    weapon.on_timer(env.api, p, at)
    return
  end
  env.api.explode({ x = at.x, y = at.y, spec = weapon.explosion })
  env.api.remove_projectile(p)
end

function M.trigger(env, p, weapon)
  local at = { x = div(p.x, FP), y = div(p.y, FP) }
  if weapon.on_trigger then
    weapon.on_trigger(env.api, p, at)
    return
  end
  env.api.explode({ x = at.x, y = at.y, spec = weapon.explosion })
  env.api.remove_projectile(p)
end

local function column_free(t, x, y)
  for k = 0, rules.WADDLER_HEIGHT - 1 do
    if terrain.solid(t, x, y - k) then
      return false
    end
  end
  return true
end

local function foothold(t, nx, py)
  for up = 0, rules.STEP_UP do
    local ny = py - up
    if column_free(t, nx, ny) then
      if terrain.solid(t, nx, ny + 1) then
        return ny, true
      end
      for down = 1, rules.STEP_DOWN do
        if not column_free(t, nx, ny + down) then
          break
        end
        if terrain.solid(t, nx, ny + down + 1) then
          return ny + down, true
        end
      end
      return ny, false
    end
  end
  return nil, false
end

local function walk_on(t, p, px, py)
  local ny, standing = foothold(t, px + p.facing, py)
  if ny == nil then
    p.facing = -p.facing
    return
  end
  p.x = p.x + p.facing * FP
  p.y = ny * FP
  if not standing then
    p.vx = 0
  end
end

local function hop_through_air(t, p)
  p.vy = clamp(p.vy + rules.GRAVITY, -rules.MAX_AXIS_SPEED, rules.MAX_AXIS_SPEED)
  local remaining = p.vx
  while remaining ~= 0 do
    local step = clamp(remaining, -FP, FP)
    local nx = p.x + step
    if div(nx, FP) ~= div(p.x, FP) and not column_free(t, div(nx, FP), div(p.y, FP)) then
      p.vx = -p.vx
      p.facing = -p.facing
      break
    end
    p.x = nx
    remaining = remaining - step
  end
  remaining = p.vy
  while remaining ~= 0 do
    local step = clamp(remaining, -FP, FP)
    local ny = p.y + step
    if div(ny, FP) ~= div(p.y, FP) and not column_free(t, div(p.x, FP), div(ny, FP)) then
      if step > 0 then
        p.y = div(p.y, FP) * FP
        p.vx = 0
      end
      p.vy = 0
      break
    end
    p.y = ny
    remaining = remaining - step
  end
end

local function waddle(env, p)
  local t = env.terrain
  local px, py = div(p.x, FP), div(p.y, FP)
  local grounded = p.vy == 0 and terrain.solid(t, px, py + 1)
  if grounded and fixed.mod(p.age, rules.WADDLER_HOP_TICKS) ~= 0 then
    walk_on(t, p, px, py)
  else
    if grounded then
      p.vx = p.facing * rules.WADDLER_HOP_VX
      p.vy = rules.WADDLER_HOP_VY
    end
    hop_through_air(t, p)
  end
  px, py = div(p.x, FP), div(p.y, FP)
  if out_of_play(env, px, py) then
    p.alive = false
    env.events[#env.events + 1] = { type = "vanished", projectile = p.id, x = px, y = py }
  end
end

local function blocked(t, from_x, from_y, px, py)
  if terrain.solid(t, px, py) then
    return true
  end
  if px ~= from_x and py ~= from_y then
    return terrain.solid(t, from_x, py) or terrain.solid(t, px, from_y)
  end
  return false
end

local function travel(env, p, weapon)
  local steps = max(div(abs(p.vx) + FP - 1, FP), div(abs(p.vy) + FP - 1, FP), 1)
  local x0, y0 = p.x, p.y
  local near, count = nil, 0
  if not weapon.bounce then
    near, count = gather_nearby(env, p, x0 + p.vx, y0 + p.vy)
  end
  local t = env.terrain
  for i = 1, steps do
    local nx, ny = x0 + round_div(p.vx * i, steps), y0 + round_div(p.vy * i, steps)
    local px, py = div(nx, FP), div(ny, FP)
    if out_of_play(env, px, py) then
      p.alive = false
      env.events[#env.events + 1] = { type = "vanished", projectile = p.id, x = px, y = py }
      return
    end
    local target = count > 0 and hit_cat(near, count, px, py)
    if target then
      impact(env, p, weapon, { x = px, y = py, cat = target })
      return
    end
    if blocked(t, div(p.x, FP), div(p.y, FP), px, py) then
      if weapon.bounce then
        bounce(env, p, weapon, px, py)
      else
        impact(env, p, weapon, { x = px, y = py, cat = nil })
      end
      return
    end
    p.x, p.y = nx, ny
  end
end

function M.step(env, p, weapon)
  if not p.alive then
    return
  end
  p.age = p.age + 1
  if weapon.on_tick then
    weapon.on_tick(env.api, p)
    if not p.alive then
      return
    end
  end
  if p.fuse > 0 then
    p.fuse = p.fuse - 1
    if p.fuse == 0 then
      timer(env, p, weapon)
      return
    end
  end
  if weapon.kind == "walker" then
    waddle(env, p)
    return
  end
  if p.resting then
    if terrain.solid(env.terrain, div(p.x, FP), div(p.y, FP) + 1) then
      return
    end
    p.resting = false
  end
  p.vy = clamp(p.vy + rules.GRAVITY, -rules.MAX_AXIS_SPEED, rules.MAX_AXIS_SPEED)
  p.vx = clamp(
    p.vx + round_div(env.wind * rules.WIND_ACCEL * weapon.wind_percent, 100),
    -rules.MAX_AXIS_SPEED,
    rules.MAX_AXIS_SPEED
  )
  travel(env, p, weapon)
end

return M

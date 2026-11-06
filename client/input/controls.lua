local rules = require("shared.sim.rules")
local trig = require("shared.sim.trig")
local weapons = require("shared.sim.weapons.registry")

local M = {}

M.GRAB_RADIUS = 48
M.CANCEL_RADIUS = 20
M.DRAG_MIN = 12
M.PULL = 130
M.AIM_START = 128
M.AIM_SPEED = 256
M.AIM_LIMIT = 256
M.CHARGE_SECONDS = 1.5

local TURN = 2 * math.pi

local function can_fire(c)
  return c.info.mine and c.info.state == "aiming" and not c.info.hanging
end

local function can_climb(c)
  local held = c.info.hanging == true or c.info.jetting == true
  return c.info.mine and c.info.state == "aiming" and held
end

local function can_move(c)
  return c.info.mine and (c.info.state == "aiming" or c.info.state == "retreat")
end

local function has(list, id)
  for _, v in ipairs(list) do
    if v == id then
      return true
    end
  end
  return false
end

function M.new(fields)
  return {
    authority = fields.authority,
    info = { mine = false, weapons = {} },
    state = false,
    weapon = weapons.list[1].id,
    fuses = {},
    wanted = 0,
    walking = 0,
    climb_wanted = 0,
    climbing = 0,
    grab = nil,
    elevation = M.AIM_START,
    keyboard = false,
    charge = nil,
    column = nil,
    shown = {},
  }
end

local function send_walk(c)
  if can_move(c) and c.wanted ~= c.walking then
    c.walking = c.wanted
    c.authority.send("input", { kind = "move", direction = c.walking })
  end
end

local function send_climb(c)
  if can_climb(c) and c.climb_wanted ~= c.climbing then
    c.climbing = c.climb_wanted
    c.authority.send("input", { kind = "climb", direction = c.climbing })
  end
end

local function climb_mode(info)
  if info.hanging then
    return "rope"
  end
  return info.jetting and "jet" or nil
end

function M.turn(c, info)
  if c.state ~= info.state then
    c.walking = 0
  end
  local mode = climb_mode(info)
  if mode ~= c.climb_mode then
    c.climb_mode, c.climbing = mode, 0
  end
  if info.state ~= "flight" or info.triggerable == nil then
    c.triggered = false
  end
  c.info, c.state = info, info.state
  if info.mine and not has(info.weapons, c.weapon) and info.weapons[1] then
    c.weapon = info.weapons[1]
  end
  if not can_move(c) then
    c.walking = 0
  else
    send_walk(c)
  end
  if not can_climb(c) then
    c.climbing = 0
  else
    send_climb(c)
  end
  if not can_fire(c) then
    c.grab = nil
    c.column = nil
    if c.charge ~= false then
      c.charge = nil
    end
  end
end

function M.weapon(c, id)
  if has(c.info.weapons, id) then
    if id ~= c.weapon then
      c.column = nil
    end
    c.weapon = id
  end
end

function M.targeting(c)
  return can_fire(c) and weapons.get(c.weapon).aim == "target"
end

function M.place_target(c, x)
  if not M.targeting(c) then
    return false
  end
  c.column = math.floor(x)
  return true
end

function M.target(c)
  return c.column
end

function M.strike(c)
  if not M.targeting(c) or c.column == nil then
    return false
  end
  c.authority.send("fire", { weapon = c.weapon, angle = 0, power = 1, target = c.column })
  c.column = nil
  return true
end

function M.current_weapon(c)
  return c.weapon
end

function M.fuse(c)
  local spec = weapons.get(c.weapon).fuse
  if spec == nil then
    return nil
  end
  return c.fuses[c.weapon] or spec.default
end

function M.next_fuse(c)
  local spec = weapons.get(c.weapon).fuse
  if spec == nil then
    return
  end
  local value = M.fuse(c) + 1
  if value > spec.max then
    value = spec.min
  end
  c.fuses[c.weapon] = value
end

local function shot_into(c, out, angle, power)
  out.weapon, out.angle, out.power = c.weapon, angle, power
  out.fuse, out.charging = M.fuse(c), nil
  return out
end

local function key_angle(c)
  local facing = c.walking ~= 0 and c.walking or c.info.facing
  local e = math.floor(c.elevation + 0.5)
  if facing >= 0 then
    return e % trig.ANGLES
  end
  return (trig.ANGLES / 2 - e) % trig.ANGLES
end

local function key_shot(c, out)
  local power = math.floor((c.charge or 0) * rules.POWER_MAX + 0.5)
  power = math.max(1, math.min(rules.POWER_MAX, power))
  return shot_into(c, out or {}, key_angle(c), power)
end

local function quantize(c, x, y, out)
  local g = c.grab
  if not g.dragged then
    return nil
  end
  local dx, dy = x - g.x, y - g.y
  local length = math.sqrt(dx * dx + dy * dy)
  if length < g.cancel then
    return nil
  end
  if not g.toward then
    dx, dy = -dx, -dy
  end
  local angle = math.floor(math.atan2(dy, dx) / TURN * trig.ANGLES + 0.5) % trig.ANGLES
  local power = math.floor((length - g.cancel) / M.PULL * rules.POWER_MAX + 0.5)
  power = math.max(1, math.min(rules.POWER_MAX, power))
  return shot_into(c, out or {}, angle, power)
end

function M.press(c, p)
  if not can_fire(c) or c.grab ~= nil or M.targeting(c) then
    return false
  end
  local cat = c.info.cat
  local radius = cat.radius or 0
  local dx, dy = p.x - cat.x, p.y - cat.y
  local reach = math.max(M.GRAB_RADIUS, radius)
  if dx * dx + dy * dy > reach * reach then
    return false
  end
  c.grab = {
    id = p.id,
    x = cat.x,
    y = cat.y,
    cancel = math.max(M.CANCEL_RADIUS, radius),
    from_x = p.x,
    from_y = p.y,
    at_x = p.x,
    at_y = p.y,
    dragged = false,
    toward = p.mouse == true,
  }
  return true
end

function M.move(c, p)
  local g = c.grab
  if g == nil or g.id ~= p.id then
    return false
  end
  g.at_x, g.at_y = p.x, p.y
  local dx, dy = p.x - g.from_x, p.y - g.from_y
  if dx * dx + dy * dy >= M.DRAG_MIN * M.DRAG_MIN then
    g.dragged = true
  end
  return true
end

function M.release(c, p)
  local g = c.grab
  if g == nil or g.id ~= p.id then
    return false
  end
  M.move(c, p)
  local shot = quantize(c, p.x, p.y)
  c.grab = nil
  if shot and can_fire(c) then
    c.authority.send("fire", shot)
  end
  return true
end

function M.aiming(c)
  return c.grab ~= nil
end

local AIMED = { angle = true, angle_power = true }

function M.aim(c)
  if not AIMED[weapons.get(c.weapon).aim] then
    return nil
  end
  local g = c.grab
  if g ~= nil then
    return quantize(c, g.at_x, g.at_y, c.shown)
  end
  if c.keyboard and can_fire(c) and not c.info.jetting then
    local shot = key_shot(c, c.shown)
    if c.charge then
      shot.charging = true
    end
    return shot
  end
  return nil
end

function M.aim_key(c, direction, dt)
  if not can_fire(c) or c.info.jetting then
    return
  end
  c.keyboard = true
  local e = c.elevation + direction * M.AIM_SPEED * dt
  c.elevation = math.max(-M.AIM_LIMIT, math.min(M.AIM_LIMIT, e))
end

function M.can_trigger(c)
  local info = c.info
  return info.mine == true
    and info.state == "flight"
    and info.triggerable ~= nil
    and not c.triggered
end

function M.trigger(c)
  if not M.can_trigger(c) then
    return false
  end
  c.authority.send("fire", { weapon = c.info.triggerable, angle = 0, power = 1 })
  c.triggered = true
  return true
end

function M.charge(c, dt)
  if M.can_trigger(c) then
    if c.charge ~= false then
      M.trigger(c)
      c.charge = false
    end
    return
  end
  if not can_fire(c) or c.grab ~= nil then
    if c.charge ~= false then
      c.charge = nil
    end
    return
  end
  c.keyboard = true
  if c.charge == false then
    return
  end
  if M.targeting(c) then
    if M.strike(c) then
      c.charge = false
    end
    return
  end
  if weapons.get(c.weapon).aim ~= "angle_power" then
    c.authority.send("fire", key_shot(c))
    c.charge = false
    return
  end
  c.charge = math.min(1, (c.charge or 0) + dt / M.CHARGE_SECONDS)
  if c.charge >= 1 then
    c.authority.send("fire", key_shot(c))
    c.charge = false
  end
end

function M.release_charge(c)
  if c.charge and can_fire(c) then
    c.authority.send("fire", key_shot(c))
  end
  c.charge = nil
end

function M.walk(c, direction)
  c.wanted = direction
  send_walk(c)
end

function M.climb(c, direction)
  c.climb_wanted = direction
  send_climb(c)
end

function M.jump(c)
  if not can_move(c) then
    return
  end
  local direction = c.walking ~= 0 and c.walking or c.info.facing
  c.authority.send("input", { kind = "jump", direction = direction })
end

return M

local camera_rig = require("game.camera_rig")
local controls = require("input.controls")
local hud_model = require("game.hud_model")

local M = {}

M.DOUBLE_TAP_SECONDS = 0.3
M.DOUBLE_TAP_POINTS = 40
M.TAP_POINTS = 12

function M.new(fields)
  return {
    rig = fields.rig,
    controls = fields.controls,
    pointers = {},
    held = {},
    point = { id = 0, x = 0, y = 0, mouse = false },
    last_tap = nil,
  }
end

local function hit(x, y)
  for name, b in pairs(hud_model.buttons) do
    if math.abs(x - b.x) <= b.rx and math.abs(y - b.y) <= b.ry then
      return name
    end
  end
  return nil
end

local function walk_from_held(r)
  local direction = 0
  if r.held.left and not r.held.right then
    direction = -1
  elseif r.held.right and not r.held.left then
    direction = 1
  end
  controls.walk(r.controls, direction)
end

local function climb_from_held(r)
  local direction = 0
  if r.held.climb_up and not r.held.climb_down then
    direction = -1
  elseif r.held.climb_down and not r.held.climb_up then
    direction = 1
  end
  controls.climb(r.controls, direction)
end

local CLIMB = { climb_up = true, climb_down = true }

local function press_button(r, name)
  local c = r.controls
  if name == "left" or name == "right" then
    r.held[name] = true
    walk_from_held(r)
  elseif CLIMB[name] then
    r.held[name] = true
    climb_from_held(r)
  elseif name == "jump" then
    controls.jump(c)
  elseif name == "weapon" then
    hud_model.grid = not hud_model.grid
  elseif name == "fuse" then
    controls.next_fuse(c)
  elseif name == "action" then
    if hud_model.action == "strike" then
      controls.strike(c)
    elseif hud_model.action == "boom" then
      controls.trigger(c)
    end
  elseif name:match("^grid_%d+$") then
    local id = hud_model.weapons[tonumber(name:sub(6))]
    if id then
      controls.weapon(c, id)
    end
    hud_model.grid = false
  end
end

local function release_button(r, name)
  if name == "left" or name == "right" then
    r.held[name] = nil
    walk_from_held(r)
  elseif CLIMB[name] then
    r.held[name] = nil
    climb_from_held(r)
  end
end

local function other_pan(r, id)
  for other, p in pairs(r.pointers) do
    if other ~= id and p.role == "pan" then
      return p
    end
  end
  return nil
end

local function tapped(r, x, y, now)
  local last = r.last_tap
  r.last_tap = { x = x, y = y, at = now }
  if last == nil or now - last.at > M.DOUBLE_TAP_SECONDS then
    return false
  end
  local limit = M.DOUBLE_TAP_POINTS * (hud_model.scale or 1)
  return math.abs(x - last.x) <= limit and math.abs(y - last.y) <= limit
end

local function in_points(r, e)
  local scale = hud_model.scale or 1
  local point = r.point
  point.id, point.x, point.y = e.id, e.x / scale, e.y / scale
  point.mouse = e.mouse == true
  return point
end

local function press(r, e)
  local x, y = e.x, e.y
  local name = hit(x, y)
  if name then
    r.pointers[e.id] = { role = "button", name = name }
    press_button(r, name)
  elseif controls.aiming(r.controls) then
    r.pointers[e.id] = { role = "idle" }
  elseif controls.press(r.controls, in_points(r, e)) then
    r.pointers[e.id] = { role = "aim" }
  else
    r.pointers[e.id] = { role = "pan", x = x, y = y, from_x = x, from_y = y }
    if tapped(r, x, y, e.now) and not controls.targeting(r.controls) then
      camera_rig.recenter(r.rig)
    end
  end
end

local function move(r, e, p)
  local x, y = e.x, e.y
  if p.role == "aim" then
    controls.move(r.controls, in_points(r, e))
  elseif p.role == "pan" and controls.aiming(r.controls) then
    p.x, p.y = x, y
  elseif p.role == "pan" then
    local other = other_pan(r, e.id)
    if other then
      p.pinched, other.pinched = true, true
      local before = math.sqrt((p.x - other.x) ^ 2 + (p.y - other.y) ^ 2)
      local after = math.sqrt((x - other.x) ^ 2 + (y - other.y) ^ 2)
      if before > 1 and after > 1 then
        camera_rig.pinch(r.rig, after / before)
      end
    elseif x ~= p.x or y ~= p.y then
      camera_rig.pan(r.rig, { x = p.x, y = p.y, dx = x - p.x, dy = y - p.y })
    end
    p.x, p.y = x, y
  end
end

function M.pointer(r, e)
  local p = r.pointers[e.id]
  if e.state == "pressed" then
    if p == nil then
      press(r, e)
    end
    return
  end
  if p == nil then
    return
  end
  move(r, e, p)
  if e.state == "released" then
    if p.role == "aim" then
      controls.release(r.controls, in_points(r, e))
    elseif p.role == "button" then
      release_button(r, p.name)
    elseif p.role == "pan" and not p.pinched and controls.targeting(r.controls) then
      local limit = M.TAP_POINTS * (hud_model.scale or 1)
      local x = camera_rig.to_world(r.rig, e.x, e.y)
      local still = math.abs(e.x - p.from_x) <= limit and math.abs(e.y - p.from_y) <= limit
      if still and x >= 0 and x < r.rig.map_width then
        controls.place_target(r.controls, x)
      end
    end
    r.pointers[e.id] = nil
  end
end

function M.key_walk(r, key)
  r.held[key.name] = key.down or nil
  walk_from_held(r)
end

function M.key_climb(r, key)
  r.held[key.name] = key.down or nil
  climb_from_held(r)
end

return M

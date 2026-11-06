local M = {}

local TOUCH, MULTI = hash("touch"), hash("multi")

local touched = false
local mouse = {
  {
    id = 0,
    x = 0,
    y = 0,
    screen_x = 0,
    screen_y = 0,
    pressed = false,
    released = false,
    mouse = true,
  },
}

function M.from(action_id, action)
  if action_id == MULTI and action.touch then
    touched = true
    return action.touch
  end
  if action_id == TOUCH and not touched then
    local p = mouse[1]
    p.x, p.y = action.x, action.y
    p.screen_x, p.screen_y = action.screen_x, action.screen_y
    p.pressed, p.released = action.pressed, action.released
    return mouse
  end
  return nil
end

function M.touch_device()
  if html5 then
    return html5.run("('ontouchstart' in window || navigator.maxTouchPoints > 0) ? 'yes' : 'no'")
      == "yes"
  end
  local system = sys.get_sys_info().system_name
  return system == "Android" or system == "iPhone OS"
end

function M.touched()
  return touched
end

return M

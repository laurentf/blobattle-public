local M = {}

local LANDSCAPE, PORTRAIT = { 844, 390 }, { 390, 844 }

local state = {}
local params = {}
local enabled = false
local dirty = false

function M.init()
  if not html5 then
    return
  end
  local search = html5.run("window.location.search") or ""
  enabled = search:find("[?&]test=1") ~= nil
  if enabled then
    state.errors = {}
    sys.set_error_handler(function(source, message)
      state.errors[#state.errors + 1] = source .. ": " .. message
      dirty = true
    end)
  end
  for key, value in search:gmatch("[?&]([%w_]+)=([%w_]+)") do
    params[key] = value
  end
end

function M.param(key)
  if not enabled then
    return nil
  end
  return params[key]
end

function M.enabled()
  return enabled
end

function M.set(key, value)
  if state[key] ~= value then
    state[key] = value
    dirty = true
  end
end

function M.put(key, value)
  state[key] = value
  dirty = true
end

function M.targets(screen, nodes)
  if not enabled then
    return
  end
  local width, height = window.get_size()
  local ref = height > width and PORTRAIT or LANDSCAPE
  local fit = math.min(width / ref[1], height / ref[2])
  local out = {}
  for name, node in pairs(nodes) do
    if gui.is_enabled(node, true) then
      local p = gui.get_screen_position(node)
      local size, scale = gui.get_size(node), gui.get_scale(node)
      out[name] = { x = p.x, y = p.y, w = size.x * scale.x * fit, h = size.y * scale.y * fit }
    end
  end
  state.targets = state.targets or {}
  state.targets[screen] = out
  dirty = true
end

function M.publish()
  if not enabled or not dirty then
    return
  end
  dirty = false
  html5.run("window.blobattle = " .. json.encode(state))
end

return M

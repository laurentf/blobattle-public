local palette = require("ui.palette")
local pointer = require("ui.pointer")

local M = {}

local LANDSCAPE, PORTRAIT = { 844, 390 }, { 390, 844 }
local DESKTOP_ZOOM = 1.25

local touch, pixel_ratio = nil, nil

function M.reference()
  local width, height = window.get_size()
  local ref = height > width and PORTRAIT or LANDSCAPE
  return ref, math.min(width / ref[1], height / ref[2])
end

function M.desktop_factor()
  if touch == nil then
    touch = pointer.touch_device()
    pixel_ratio = html5 and tonumber(html5.run("window.devicePixelRatio")) or 1
  end
  if touch then
    return 1
  end
  local _, scale = M.reference()
  return math.min(1, pixel_ratio * DESKTOP_ZOOM / scale)
end

function M.fit(state, ids)
  local ref = M.reference()
  local factor = M.desktop_factor()
  local base = state.fit_base
  if base == nil then
    base = {}
    state.fit_base = base
  end
  for _, id in ipairs(ids) do
    local node = gui.get_node(id)
    local b = base[id]
    if b == nil then
      b = { pos = gui.get_position(node), scale = gui.get_scale(node) }
      base[id] = b
    end
    local ax, ay = gui.get_xanchor(node), gui.get_yanchor(node)
    local cx = ref[1] / 2
    if ax == gui.ANCHOR_LEFT then
      cx = 0
    elseif ax == gui.ANCHOR_RIGHT then
      cx = ref[1]
    end
    local cy = ref[2] / 2
    if ay == gui.ANCHOR_BOTTOM then
      cy = 0
    elseif ay == gui.ANCHOR_TOP then
      cy = ref[2]
    end
    gui.set_position(
      node,
      vmath.vector3(cx + (b.pos.x - cx) * factor, cy + (b.pos.y - cy) * factor, b.pos.z)
    )
    gui.set_scale(node, b.scale * factor)
  end
  state.fit_factor = factor
  return factor
end

function M.refit(state, ids)
  state.fit_base = nil
  return M.fit(state, ids)
end

function M.resized(state)
  local width, height = window.get_size()
  if width ~= state.fit_width or height ~= state.fit_height then
    state.fit_width, state.fit_height = width, height
    return true
  end
  return false
end

function M.colour(rgb, alpha)
  return vmath.vector4(rgb[1], rgb[2], rgb[3], alpha or 1)
end

function M.text(name, value, rgb)
  local node = gui.get_node(name)
  gui.set_text(node, value)
  gui.set_color(node, M.colour(rgb or palette.PAPER))
  gui.set_outline(node, M.colour(palette.INK))
  return node
end

function M.button(name, fields)
  local box = gui.get_node(name)
  local label = gui.get_node(name .. "_label")
  gui.set_color(box, M.colour(fields.enabled == false and palette.BUTTON_OFF or palette.BUTTON))
  gui.set_text(label, fields.text)
  gui.set_color(label, M.colour(palette.INK))
  gui.set_outline(label, M.colour(palette.PAPER))
  return box
end

function M.released(action_id, action, names)
  for _, p in ipairs(pointer.from(action_id, action) or {}) do
    if p.released then
      for _, name in ipairs(names) do
        local node = gui.get_node(name)
        if gui.is_enabled(node, true) and gui.pick_node(node, p.x, p.y) then
          return name
        end
      end
    end
  end
  return nil
end

return M

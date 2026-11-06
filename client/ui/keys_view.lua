local i18n = require("ui.i18n")
local keymap = require("input.keymap")
local weapons = require("shared.sim.weapons.registry")

local M = {}

local MOVES = #keymap.COMMANDS - #weapons.list
local LINES = 5
local TALL_LINES = 9

function M.label(map, key)
  return keymap.typed(map, key) or i18n.t("key." .. key:sub(5))
end

local function caption(command, i)
  if i > MOVES then
    return i18n.t("weapon." .. weapons.list[i - MOVES].id)
  end
  return i18n.t("keys." .. command)
end

function M.rows(map, fields)
  local rows = {}
  for i, command in ipairs(keymap.COMMANDS) do
    local waiting = fields.waiting == command
    local lines = fields.portrait and TALL_LINES or LINES
    local column, line = math.floor((i - 1) / lines) + 1, (i - 1) % lines + 1
    rows[i] = {
      command = command,
      caption = caption(command, i),
      key = waiting and i18n.t("keys.press") or M.label(map, keymap.key(map, command)),
      waiting = waiting,
      column = column,
      line = line,
    }
  end
  return rows
end

return M

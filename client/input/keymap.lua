local weapons = require("shared.sim.weapons.registry")

local M = {}

local INPUTS = {
  "SPACE",
  "A",
  "B",
  "C",
  "D",
  "E",
  "F",
  "G",
  "H",
  "I",
  "J",
  "K",
  "L",
  "M",
  "N",
  "O",
  "P",
  "Q",
  "R",
  "S",
  "T",
  "U",
  "V",
  "W",
  "X",
  "Y",
  "Z",
  "0",
  "1",
  "2",
  "3",
  "4",
  "5",
  "6",
  "7",
  "8",
  "9",
  "LEFT",
  "RIGHT",
  "UP",
  "DOWN",
  "ENTER",
  "BACKSPACE",
  "INSERT",
  "DEL",
  "HOME",
  "END",
  "PAGEUP",
  "PAGEDOWN",
  "LSHIFT",
  "RSHIFT",
  "LCTRL",
  "RCTRL",
  "LALT",
  "RALT",
  "KP_0",
  "KP_1",
  "KP_2",
  "KP_3",
  "KP_4",
  "KP_5",
  "KP_6",
  "KP_7",
  "KP_8",
  "KP_9",
  "KP_DIVIDE",
  "KP_MULTIPLY",
  "KP_SUBTRACT",
  "KP_ADD",
  "KP_DECIMAL",
  "KP_ENTER",
}

local PUNCTUATION = {
  "COMMA",
  "PERIOD",
  "SLASH",
  "SEMICOLON",
  "QUOTE",
  "LBRACKET",
  "RBRACKET",
  "BACKSLASH",
  "MINUS",
  "EQUALS",
  "BACKQUOTE",
}

M.KEYS = {}
local OFFERED, TYPED = {}, {}
local function offer(input, typed)
  local id = "key_" .. input:lower()
  M.KEYS[#M.KEYS + 1] = { id = id, input = "KEY_" .. input }
  OFFERED[id] = true
  TYPED[id] = typed
end
for _, input in ipairs(INPUTS) do
  offer(input, false)
end
for _, input in ipairs(PUNCTUATION) do
  offer(input, true)
end

M.ESCAPE = "key_esc"

M.COMMANDS = { "left", "right", "aim_up", "aim_down", "fire", "jump", "fuse" }
M.DEFAULTS = {
  left = "key_left",
  right = "key_right",
  aim_up = "key_up",
  aim_down = "key_down",
  fire = "key_space",
  jump = "key_enter",
  fuse = "key_f",
}
for i = 1, #weapons.list do
  local command = "weapon_" .. i
  M.COMMANDS[#M.COMMANDS + 1] = command
  M.DEFAULTS[command] = "key_" .. i % 10
end

local KNOWN = {}
for _, command in ipairs(M.COMMANDS) do
  KNOWN[command] = true
end

local FIRST_VISIBLE, LAST_VISIBLE = 33, 126

local function visible(text)
  if type(text) ~= "string" or #text ~= 1 then
    return nil
  end
  local byte = text:byte()
  if byte < FIRST_VISIBLE or byte > LAST_VISIBLE then
    return nil
  end
  return text:upper()
end

local function index(map)
  local by_key = {}
  for _, command in ipairs(M.COMMANDS) do
    by_key[map.keys[command]] = command
  end
  map.by_key = by_key
  return map
end

local function valid_keys(keys)
  if type(keys) ~= "table" then
    return false
  end
  local used = {}
  for _, command in ipairs(M.COMMANDS) do
    local key = keys[command]
    if type(key) ~= "string" or not OFFERED[key] or used[key] then
      return false
    end
    used[key] = true
  end
  return true
end

local function fill(map, keys, labels)
  map.keys, map.labels = {}, {}
  for _, command in ipairs(M.COMMANDS) do
    map.keys[command] = keys[command]
  end
  if type(labels) == "table" then
    for _, k in ipairs(M.KEYS) do
      map.labels[k.id] = TYPED[k.id] and visible(labels[k.id]) or nil
    end
  end
  return index(map)
end

function M.read(data)
  local map = {}
  if valid_keys(data.keys) then
    return fill(map, data.keys, data.labels)
  end
  return fill(map, M.DEFAULTS)
end

function M.data(map)
  local keys, labels = {}, {}
  for _, command in ipairs(M.COMMANDS) do
    keys[command] = map.keys[command]
  end
  for _, k in ipairs(M.KEYS) do
    labels[k.id] = map.labels[k.id]
  end
  return { keys = keys, labels = labels }
end

function M.actions(hash_of)
  local names = {}
  for _, k in ipairs(M.KEYS) do
    names[hash_of(k.id)] = k.id
  end
  return names
end

function M.command(map, key)
  return map.by_key[key]
end

function M.key(map, command)
  return map.keys[command]
end

function M.typed(map, key)
  return map.labels[key]
end

function M.assign(map, command, key, typed)
  if not KNOWN[command] or not OFFERED[key] then
    return false
  end
  local before, holder = map.keys[command], map.by_key[key]
  if holder then
    map.keys[holder] = before
  end
  map.keys[command] = key
  map.labels[key] = TYPED[key] and visible(typed) or nil
  index(map)
  return true
end

function M.reset(map)
  fill(map, M.DEFAULTS)
end

local function path()
  return sys.get_save_file("blobattle", "keys")
end

function M.load()
  local ok, data = pcall(sys.load, path())
  return M.read(ok and type(data) == "table" and data or {})
end

function M.save(map)
  sys.save(path(), M.data(map))
end

return M

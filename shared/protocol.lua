local fixed = require("shared.sim.fixed")
local rng = require("shared.sim.rng")
local rules = require("shared.sim.rules")
local trig = require("shared.sim.trig")
local weapons = require("shared.sim.weapons.registry")

local M = {}

M.OPS = {
  lobby_settings = 1,
  lobby_slot = 2,
  start = 3,
  input = 10,
  fire = 11,
  skip = 12,
  snapshot_request = 13,
  rematch = 20,
  lobby_state = 100,
  game_start = 101,
  ticks = 102,
  checksum = 103,
  snapshot = 104,
  game_end = 105,
  refused = 106,
  pilots = 107,
}

M.CLIENT_OPS = {}
for _, name in ipairs({
  "lobby_settings",
  "lobby_slot",
  "start",
  "input",
  "fire",
  "skip",
  "snapshot_request",
  "rematch",
}) do
  M.CLIENT_OPS[M.OPS[name]] = name
end

M.CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ"
M.CODE_LENGTH = 5

M.NICKNAME_MIN = 2
M.NICKNAME_MAX = 16

M.LOBBY_SETTINGS = { "teams", "cats_per_team", "turn_seconds", "map", "bot_level" }

local CODE_PATTERN = "^[" .. M.CODE_ALPHABET .. "]+$"

function M.valid_code(code)
  return type(code) == "string" and #code == M.CODE_LENGTH and code:find(CODE_PATTERN) ~= nil
end

function M.code_from(numbers)
  local letters = {}
  local size = #M.CODE_ALPHABET
  for i = 1, M.CODE_LENGTH do
    local k = fixed.mod(numbers[i], size) + 1
    letters[i] = M.CODE_ALPHABET:sub(k, k)
  end
  return table.concat(letters)
end

function M.valid_nickname(name)
  if type(name) ~= "string" or #name < M.NICKNAME_MIN or #name > M.NICKNAME_MAX then
    return false
  end
  if name:sub(1, 1) == " " or name:sub(-1) == " " then
    return false
  end
  return name:find("^[A-Za-z0-9 _%-]+$") ~= nil
end

local function integer(value, low, high)
  return type(value) == "number" and fixed.mod(value, 1) == 0 and value >= low and value <= high
end

local DECODERS = {}

function DECODERS.lobby_settings(msg)
  local out = {}
  for _, name in ipairs(M.LOBBY_SETTINGS) do
    out[name] = msg[name]
  end
  if msg.seed ~= nil then
    if not integer(msg.seed, 0, rng.MAX_SEED) then
      return nil, "invalid_seed"
    end
    out.seed = msg.seed
  end
  return out
end

function DECODERS.lobby_slot(msg)
  if not integer(msg.seat, 1, rules.SETTINGS.teams.max) then
    return nil, "malformed"
  end
  if msg.kind ~= "open" and msg.kind ~= "bot" then
    return nil, "malformed"
  end
  return { seat = msg.seat, kind = msg.kind }
end

function DECODERS.start()
  return {}
end

function DECODERS.input(msg)
  if msg.kind == "move" then
    if not integer(msg.direction, -1, 1) then
      return nil, "invalid_direction"
    end
  elseif msg.kind == "jump" then
    if msg.direction ~= -1 and msg.direction ~= 1 then
      return nil, "invalid_direction"
    end
  elseif msg.kind == "climb" then
    if not integer(msg.direction, -1, 1) then
      return nil, "invalid_direction"
    end
  else
    return nil, "malformed"
  end
  return { kind = msg.kind, direction = msg.direction }
end

function DECODERS.fire(msg)
  local weapon = type(msg.weapon) == "string"
    and weapons.selectable(msg.weapon)
    and weapons.get(msg.weapon)
  if not weapon then
    return nil, "invalid_weapon"
  end
  if not integer(msg.angle, 0, trig.ANGLES - 1) then
    return nil, "invalid_angle"
  end
  if not integer(msg.power, 1, rules.POWER_MAX) then
    return nil, "invalid_power"
  end
  local out = { weapon = weapon.id, angle = msg.angle, power = msg.power }
  if msg.fuse ~= nil then
    if weapon.fuse == nil or not integer(msg.fuse, weapon.fuse.min, weapon.fuse.max) then
      return nil, "invalid_fuse"
    end
    out.fuse = msg.fuse
  end
  if weapon.aim == "target" then
    if not integer(msg.target, 0, rules.MAP_WIDTH_MAX - 1) then
      return nil, "invalid_target"
    end
    out.target = msg.target
  elseif msg.target ~= nil then
    return nil, "invalid_target"
  end
  return out
end

function DECODERS.skip()
  return {}
end

function DECODERS.snapshot_request(msg)
  if msg.tick ~= nil and not integer(msg.tick, 0, rng.MAX_SEED) then
    return nil, "malformed"
  end
  return { tick = msg.tick }
end

function DECODERS.rematch()
  return {}
end

function M.decode(op, msg)
  local name = M.CLIENT_OPS[op]
  local decoder = name and DECODERS[name]
  if decoder == nil then
    return nil, "unknown_op"
  end
  return decoder(msg)
end

return M

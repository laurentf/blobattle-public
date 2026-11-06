local errors = require("server.errors")
local nk = require("nakama")
local protocol = require("shared.protocol")
local requests = require("server.requests")
local rules = require("shared.sim.rules")
local world = require("shared.sim.world")

local M = {}

M.MODULE = "server.room"

local caller, decode, object = requests.caller, requests.decode, requests.object

local function lobby_settings(input)
  local picked = {}
  for _, name in ipairs(protocol.LOBBY_SETTINGS) do
    picked[name] = input[name]
  end
  return world.resolve_settings(picked)
end

local function lookup(code)
  return nk.match_list(1, true, nil, nil, nil, "+label.code:" .. code)
end

local function draw_code()
  local hex = nk.uuid_v4():gsub("-", "")
  local numbers = {}
  for i = 1, protocol.CODE_LENGTH do
    numbers[i] = tonumber(hex:sub(2 * i - 1, 2 * i), 16)
  end
  return protocol.code_from(numbers)
end

function M.create(context, payload)
  local host = caller(context)
  local request, refused = decode(payload)
  if request == nil then
    errors.raise(refused, errors.INVALID_ARGUMENT)
  end
  if request.settings ~= nil and not object(request.settings) then
    errors.raise("malformed", errors.INVALID_ARGUMENT)
  end
  local settings, reason = lobby_settings(request.settings or {})
  if settings == nil then
    errors.raise(reason, errors.INVALID_ARGUMENT)
  end
  for _ = 1, rules.ROOM_CODE_ATTEMPTS do
    local code = draw_code()
    if #lookup(code) == 0 then
      local match_id = nk.match_create(M.MODULE, { code = code, host = host, settings = settings })
      return nk.json_encode({ code = code, match_id = match_id })
    end
  end
  errors.raise("room_code_unavailable", errors.UNAVAILABLE)
end

function M.find(context, payload)
  caller(context)
  local request = decode(payload) or {}
  local code = request.code
  if type(code) == "string" then
    code = code:upper()
  end
  if not protocol.valid_code(code) then
    errors.raise("room_not_found", errors.NOT_FOUND)
  end
  local found = lookup(code)
  if #found == 0 then
    errors.raise("room_not_found", errors.NOT_FOUND)
  end
  return nk.json_encode({ match_id = found[1].match_id })
end

return M

local errors = require("server.errors")
local nk = require("nakama")
local rules = require("shared.sim.rules")

local M = {}

function M.caller(context)
  if type(context.user_id) ~= "string" or context.user_id == "" then
    errors.raise("unauthenticated", errors.UNAUTHENTICATED)
  end
  return context.user_id
end

function M.object(value)
  return type(value) == "table" and value[1] == nil
end

function M.decode(payload)
  if type(payload) == "string" and #payload > rules.MESSAGE_MAX_BYTES then
    return nil, "too_large"
  end
  local ok, request = pcall(nk.json_decode, payload)
  if not ok or not M.object(request) then
    return nil, "malformed"
  end
  return request
end

return M

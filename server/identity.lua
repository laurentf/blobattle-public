local errors = require("server.errors")
local nk = require("nakama")
local protocol = require("shared.protocol")
local requests = require("server.requests")
local rules = require("shared.sim.rules")

local M = {}

M.COLLECTION = "team"
M.KEY = "team"

local MEMBERS = rules.SETTINGS.cats_per_team.max

function M.authenticate_device(_, payload)
  if payload.username ~= nil and payload.username ~= "" then
    errors.raise("invalid_account", errors.INVALID_ARGUMENT)
  end
  return payload
end

function M.update_account(_, payload)
  for field in pairs(payload) do
    if field ~= "display_name" then
      errors.raise("invalid_account", errors.INVALID_ARGUMENT)
    end
  end
  if payload.display_name ~= nil and not protocol.valid_nickname(payload.display_name) then
    errors.raise("invalid_nickname", errors.INVALID_ARGUMENT)
  end
  return payload
end

local function members_of(list)
  if type(list) ~= "table" or #list ~= MEMBERS then
    return nil
  end
  local out = {}
  for i = 1, MEMBERS do
    if not protocol.valid_nickname(list[i]) then
      return nil
    end
    out[i] = list[i]
  end
  return out
end

function M.team_set(context, payload)
  local user_id = requests.caller(context)
  local request, refused = requests.decode(payload)
  if request == nil then
    errors.raise(refused, errors.INVALID_ARGUMENT)
  end
  if not protocol.valid_nickname(request.name) then
    errors.raise("invalid_team_name", errors.INVALID_ARGUMENT)
  end
  local members = members_of(request.members)
  if members == nil then
    errors.raise("invalid_member_name", errors.INVALID_ARGUMENT)
  end
  local team = { name = request.name, members = members }
  local kept = M.team_of(user_id)
  if
    kept
    and kept.name == team.name
    and table.concat(kept.members, "\n") == table.concat(members, "\n")
  then
    return nk.json_encode(team)
  end
  nk.storage_write({
    {
      collection = M.COLLECTION,
      key = M.KEY,
      user_id = user_id,
      value = team,
      permission_read = 0,
      permission_write = 0,
    },
  })
  return nk.json_encode(team)
end

function M.team_of(user_id)
  local ok, found = pcall(nk.storage_read, {
    { collection = M.COLLECTION, key = M.KEY, user_id = user_id },
  })
  local value = ok and found[1] and found[1].value
  if type(value) ~= "table" or not protocol.valid_nickname(value.name) then
    return nil
  end
  local members = members_of(value.members)
  if members == nil then
    return nil
  end
  return { name = value.name, members = members }
end

return M

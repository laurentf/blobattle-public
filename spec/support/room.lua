local fake = require("spec.support.nakama")

local M = {}

function M.open(nk, settings, host)
  host = host or "host"
  nk.add_user(host, "Host")
  local rooms = require("server.rooms")
  local payload = nk.json_encode({ settings = settings or {} })
  local out = nk.json_decode(rooms.create({ user_id = host }, payload))
  return fake.match(nk, out.match_id), out
end

function M.arrive(nk, room, user, name)
  nk.add_user(user, name or user)
  local p = fake.presence(user)
  local ok, reason = room.join(p)
  assert(ok, reason)
  return p
end

function M.last(room, op_code, presence)
  local list = room.received(op_code, presence)
  return list[#list]
end

return M

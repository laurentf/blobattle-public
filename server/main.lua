local closed = require("server.closed")
local identity = require("server.identity")
local nk = require("nakama")
local rooms = require("server.rooms")

nk.register_rpc(rooms.create, "room_create")
nk.register_rpc(rooms.find, "room_find")
nk.register_rpc(identity.team_set, "team_set")
nk.register_req_before(identity.update_account, "UpdateAccount")
nk.register_req_before(identity.authenticate_device, "AuthenticateDevice")
for _, list in ipairs({ closed.ACCOUNTS, closed.REQUESTS }) do
  for _, request in ipairs(list) do
    nk.register_req_before(closed.refuse, request)
  end
end
for _, message in ipairs(closed.REALTIME) do
  nk.register_rt_before(closed.refuse, message)
end

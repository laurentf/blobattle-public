local lobby = require("server.lobby")
local phase = require("server.phase")
local nk = require("nakama")
local players = require("server.players")
local protocol = require("shared.protocol")
local snapshots = require("server.snapshots")

local M = {}

M.OPS = { rematch = true, snapshot_request = true }
M.join_attempt = players.registered_join

local function tell_host(state, dispatcher)
  if state.game_end.host ~= state.host then
    state.game_end.host = state.host
    dispatcher.broadcast_message(protocol.OPS.game_end, nk.json_encode(state.game_end))
  end
end

function M.join(state, dispatcher, presences)
  for _, p in ipairs(presences) do
    dispatcher.broadcast_message(protocol.OPS.game_start, state.game_start, { p })
    snapshots.send(state, dispatcher, p)
    dispatcher.broadcast_message(protocol.OPS.game_end, nk.json_encode(state.game_end), { p })
  end
  players.transfer_host(state)
  tell_host(state, dispatcher)
end

function M.leave(state, dispatcher, presence)
  snapshots.forget(state, presence)
  tell_host(state, dispatcher)
end

function M.handle(state, dispatcher, sender, name, msg)
  if name == "snapshot_request" then
    return snapshots.request(state, dispatcher, sender, msg)
  end
  if sender.user_id ~= state.host then
    return "not_host"
  end
  for user_id, player in pairs(state.players) do
    if not players.present(state, user_id) then
      local seat = state.seats[player.seat]
      seat.user, seat.name, seat.team = nil, nil, nil
      state.players[user_id] = nil
    end
  end
  state.world, state.driver, state.stats, state.timing = nil, nil, nil, nil
  state.inputs, state.outbox, state.snapshots, state.game_end = nil, nil, nil, nil
  state.snapshot_cache, state.game_start = nil, nil
  phase.set(state, dispatcher, "lobby")
  lobby.broadcast(state, dispatcher)
  return nil
end

return M

local log = require("server.log")
local nk = require("nakama")
local protocol = require("shared.protocol")
local rules = require("shared.sim.rules")
local world = require("shared.sim.world")

local M = {}

function M.send(state, dispatcher, presence)
  local w = state.world
  state.snapshots[presence.session_id] = state.match_tick
  local message = nk.json_encode({ tick = w.tick, state = world.snapshot(w, state.snapshot_cache) })
  dispatcher.broadcast_message(protocol.OPS.snapshot, message, { presence })
end

function M.request(state, dispatcher, sender, msg)
  local last = state.snapshots[sender.session_id]
  if last ~= nil and state.match_tick - last < rules.SNAPSHOT_REQUEST_TICKS then
    return "too_soon"
  end
  local player = state.players[sender.user_id]
  if msg.tick ~= nil then
    log.warn(
      state,
      "🧮 checksum divergence at="
        .. msg.tick
        .. " player="
        .. (player and player.name or "?")
        .. " team="
        .. (player and player.seat or 0)
    )
  end
  M.send(state, dispatcher, sender)
  return nil
end

function M.forget(state, presence)
  state.snapshots[presence.session_id] = nil
end

return M

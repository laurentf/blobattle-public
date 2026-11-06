local M = {}

function M.registered_join(state, presence)
  if state.players[presence.user_id] then
    return true
  end
  return false, "game_in_progress"
end

function M.present(state, user_id)
  for _, p in pairs(state.presences) do
    if p.user_id == user_id then
      return true
    end
  end
  return false
end

local function earliest_present(state)
  local best = nil
  for user_id, player in pairs(state.players) do
    if M.present(state, user_id) and (best == nil or player.arrived < best.arrived) then
      best = player
    end
  end
  return best and best.user_id
end

function M.transfer_host(state)
  if state.host ~= nil and M.present(state, state.host) then
    return
  end
  state.host = earliest_present(state)
end

return M

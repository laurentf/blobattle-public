local log = require("server.log")
local nk = require("nakama")
local protocol = require("shared.protocol")
local rules = require("shared.sim.rules")

local M = {}

function M.new()
  return { presences = {} }
end

local function track(state, presence)
  local g = state.guard.presences[presence.session_id]
  if g == nil then
    g = { user_id = presence.user_id, recent = {}, quiet_until = -1, refusals = {}, codes = {} }
    state.guard.presences[presence.session_id] = g
  end
  return g
end

local function name_of(state, user_id)
  local player = state.players[user_id]
  return player and player.name or "?"
end

function M.admit(state, message)
  local g = track(state, message.sender)
  local recent = g.recent
  local oldest = state.match_tick - rules.TICKS_PER_SECOND + 1
  while recent[1] ~= nil and recent[1] < oldest do
    table.remove(recent, 1)
  end
  if #recent >= rules.MESSAGES_PER_SECOND then
    return nil, "rate_limited"
  end
  recent[#recent + 1] = state.match_tick
  if type(message.data) ~= "string" or #message.data > rules.MESSAGE_MAX_BYTES then
    return nil, "too_large"
  end
  local ok, value = pcall(nk.json_decode, message.data)
  if not ok or type(value) ~= "table" or value[1] ~= nil then
    return nil, "malformed"
  end
  return value
end

function M.refuse(state, dispatcher, sender, reason)
  local g = track(state, sender)
  if g.refusals[reason] == nil then
    g.refusals[reason] = 0
    g.codes[#g.codes + 1] = reason
  end
  g.refusals[reason] = g.refusals[reason] + 1
  local name = name_of(state, sender.user_id)
  log.debug(
    state,
    "🚫 refused " .. reason .. " player=" .. name .. " count=" .. g.refusals[reason]
  )
  if reason == "rate_limited" then
    if state.match_tick < g.quiet_until then
      return
    end
    g.quiet_until = state.match_tick + rules.TICKS_PER_SECOND
    log.warn(state, "🚫 rate limited player=" .. name)
  end
  local payload = nk.json_encode({ code = reason })
  dispatcher.broadcast_message(protocol.OPS.refused, payload, { sender })
end

function M.forget(state, presence)
  local g = state.guard.presences[presence.session_id]
  state.guard.presences[presence.session_id] = nil
  if g == nil or #g.codes == 0 then
    return
  end
  local parts = {}
  for _, code in ipairs(g.codes) do
    parts[#parts + 1] = code .. "=" .. g.refusals[code]
  end
  local name = name_of(state, g.user_id)
  log.info(state, "🚫 refusals player=" .. name .. " " .. table.concat(parts, " "))
end

return M

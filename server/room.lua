local ended = require("server.ended")
local guard = require("server.guard")
local lobby = require("server.lobby")
local log = require("server.log")
local phase = require("server.phase")
local players = require("server.players")
local playing = require("server.playing")
local protocol = require("shared.protocol")
local rules = require("shared.sim.rules")

local M = {}

local PHASES = { lobby = lobby, playing = playing, ended = ended }

function M.match_init(_, params)
  local state = {
    code = params.code,
    host = params.host,
    settings = params.settings,
    seed = 0,
    phase = "lobby",
    seats = lobby.seats(params.settings.teams),
    players = {},
    presences = {},
    arrivals = 0,
    empty_ticks = 0,
    match_tick = 0,
    guard = guard.new(),
  }
  log.info(state, "🏠 room created")
  return state, rules.TICKS_PER_SECOND, phase.label(state)
end

function M.match_join_attempt(_, _, _, state, presence)
  local accepted, reason = PHASES[state.phase].join_attempt(state, presence)
  if accepted then
    return state, true
  end
  return state, false, reason
end

function M.match_join(_, dispatcher, _, state, presences)
  for _, p in ipairs(presences) do
    state.presences[p.session_id] = p
  end
  PHASES[state.phase].join(state, dispatcher, presences)
  players.transfer_host(state)
  return state
end

function M.match_leave(_, dispatcher, _, state, presences)
  for _, p in ipairs(presences) do
    state.presences[p.session_id] = nil
    guard.forget(state, p)
    players.transfer_host(state)
    PHASES[state.phase].leave(state, dispatcher, p)
  end
  return state
end

local function handle(state, dispatcher, message)
  local msg, reason = guard.admit(state, message)
  if msg == nil then
    return reason
  end
  local name = protocol.CLIENT_OPS[message.op_code]
  if name == nil then
    return "unknown_op"
  end
  local current = PHASES[state.phase]
  if not current.OPS[name] then
    return "wrong_phase"
  end
  msg, reason = protocol.decode(message.op_code, msg)
  if msg == nil then
    return reason
  end
  return current.handle(state, dispatcher, message.sender, name, msg)
end

function M.match_loop(_, dispatcher, tick, state, messages)
  state.match_tick = tick
  for _, message in ipairs(messages) do
    if state.presences[message.sender.session_id] then
      local reason = handle(state, dispatcher, message)
      if reason ~= nil then
        guard.refuse(state, dispatcher, message.sender, reason)
      end
    end
  end
  if state.phase == "playing" then
    playing.tick(state, dispatcher)
  end
  if next(state.presences) ~= nil then
    state.empty_ticks = 0
    return state
  end
  state.empty_ticks = state.empty_ticks + 1
  if state.empty_ticks >= rules.ROOM_EMPTY_SECONDS * rules.TICKS_PER_SECOND then
    log.info(state, "🏠 room closed" .. playing.timing(state))
    return nil
  end
  return state
end

function M.match_terminate(_, _, _, state)
  return state
end

function M.match_signal(_, _, _, state, data)
  return state, data
end

return M

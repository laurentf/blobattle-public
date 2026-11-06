local identity = require("server.identity")
local nk = require("nakama")
local players = require("server.players")
local playing = require("server.playing")
local protocol = require("shared.protocol")
local world = require("shared.sim.world")

local M = {}

M.OPS = { lobby_settings = true, lobby_slot = true, start = true }

function M.seats(count)
  local seats = {}
  for i = 1, count do
    seats[i] = { kind = "open" }
  end
  return seats
end

function M.broadcast(state, dispatcher)
  local seats = {}
  for i, seat in ipairs(state.seats) do
    seats[i] = { kind = seat.kind, user = seat.user, name = seat.name, team = seat.team }
  end
  local message = {
    code = state.code,
    host = state.host,
    settings = state.settings,
    seed = state.seed,
    seats = seats,
  }
  dispatcher.broadcast_message(protocol.OPS.lobby_state, nk.json_encode(message))
end

local function nickname(user_id)
  local ok, users = pcall(nk.users_get_id, { user_id })
  local name = ok and users[1] and users[1].display_name
  if protocol.valid_nickname(name) then
    return name
  end
  return nil
end

local function free_seat(state)
  for i, seat in ipairs(state.seats) do
    if seat.kind == "open" and seat.user == nil then
      return i
    end
  end
  return nil
end

function M.join_attempt(state, presence)
  if nickname(presence.user_id) == nil then
    return false, "nickname_required"
  end
  if state.players[presence.user_id] == nil and free_seat(state) == nil then
    return false, "room_full"
  end
  return true
end

local function take_seat(state, presence)
  if state.players[presence.user_id] then
    return true
  end
  local index, name = free_seat(state), nickname(presence.user_id)
  if index == nil or name == nil then
    return false
  end
  local team = identity.team_of(presence.user_id)
  state.arrivals = state.arrivals + 1
  state.players[presence.user_id] = {
    user_id = presence.user_id,
    name = name,
    seat = index,
    arrived = state.arrivals,
    team = team,
  }
  local seat = state.seats[index]
  seat.user, seat.name = presence.user_id, name
  if team then
    seat.team = team.name
  end
  return true
end

function M.join(state, dispatcher, presences)
  for _, p in ipairs(presences) do
    if not take_seat(state, p) then
      state.presences[p.session_id] = nil
      dispatcher.match_kick({ p })
    end
  end
  players.transfer_host(state)
  M.broadcast(state, dispatcher)
end

function M.leave(state, dispatcher, presence)
  local player = state.players[presence.user_id]
  if player and not players.present(state, presence.user_id) then
    local s = state.seats[player.seat]
    s.user, s.name, s.team = nil, nil, nil
    state.players[presence.user_id] = nil
  end
  M.broadcast(state, dispatcher)
end

local function lobby_fields(settings)
  local picked = {}
  for _, name in ipairs(protocol.LOBBY_SETTINGS) do
    picked[name] = settings[name]
  end
  return picked
end

local function change_settings(state, msg)
  local merged = lobby_fields(state.settings)
  for _, name in ipairs(protocol.LOBBY_SETTINGS) do
    if msg[name] ~= nil then
      merged[name] = msg[name]
    end
  end
  local settings, reason = world.resolve_settings(merged)
  if settings == nil then
    return reason
  end
  for i = settings.teams + 1, #state.seats do
    if state.seats[i].user ~= nil then
      return "seat_taken"
    end
  end
  for i = #state.seats, settings.teams + 1, -1 do
    table.remove(state.seats, i)
  end
  for i = #state.seats + 1, settings.teams do
    state.seats[i] = { kind = "open" }
  end
  state.settings = settings
  if msg.seed ~= nil then
    state.seed = msg.seed
  end
  return nil
end

local function change_slot(state, msg)
  local seat = state.seats[msg.seat]
  if seat == nil then
    return "invalid_seat"
  end
  if seat.user ~= nil then
    return "seat_taken"
  end
  seat.kind = msg.kind
  return nil
end

function M.handle(state, dispatcher, sender, name, msg)
  if sender.user_id ~= state.host then
    return "not_host"
  end
  local reason
  if name == "lobby_settings" then
    reason = change_settings(state, msg)
  elseif name == "lobby_slot" then
    reason = change_slot(state, msg)
  else
    playing.start(state, dispatcher)
    return nil
  end
  if reason == nil then
    M.broadcast(state, dispatcher)
  end
  return reason
end

return M

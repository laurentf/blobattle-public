local i18n = require("ui.i18n")
local rules = require("shared.sim.rules")

local M = {}

M.SEATS = rules.SETTINGS.teams.max

local STEPPERS = { teams = "teams", cats = "cats_per_team" }
local CYCLES = {
  turn = { setting = "turn_seconds" },
  map = { setting = "map", prefix = "map." },
  bots = { setting = "bot_level", prefix = "level." },
}

local function seat_view(lobby, i, me, host)
  local seat = lobby.seats[i]
  if seat == nil then
    return { shown = false }
  end
  if seat.user then
    local player = seat.name
    if seat.user == lobby.host then
      player = i18n.format("room.host", { name = seat.name })
    end
    return { shown = true, team = seat.team or seat.name, player = player, mine = seat.user == me }
  end
  local v = {
    shown = true,
    team = i18n.t(seat.kind == "bot" and "room.bot" or "room.open"),
    player = "",
    mine = false,
  }
  if host then
    v.toggle = seat.kind == "bot" and "open" or "bot"
  end
  return v
end

local function held_seats(lobby)
  local last = 0
  for i, seat in ipairs(lobby.seats) do
    if seat.user then
      last = i
    end
  end
  return last
end

local function next_choice(choices, value)
  for i, choice in ipairs(choices) do
    if choice == value then
      return choices[i % #choices + 1]
    end
  end
  return choices[1]
end

local function cycle_text(row, value)
  local cycle = CYCLES[row]
  if cycle.prefix == nil then
    return i18n.format("room.seconds", { seconds = value })
  end
  return i18n.t(cycle.prefix .. value)
end

function M.build(lobby, me)
  local host = lobby.host ~= nil and lobby.host == me
  local v = { host = host, code = lobby.code, seats = {}, settings = {} }
  for i = 1, M.SEATS do
    v.seats[i] = seat_view(lobby, i, me, host)
  end
  local s = lobby.settings
  for row, setting in pairs(STEPPERS) do
    local spec, value = rules.SETTINGS[setting], s[setting]
    local low = spec.min
    if row == "teams" then
      low = math.max(low, held_seats(lobby))
    end
    v.settings[row] = {
      value = value,
      text = tostring(value),
      minus = host and value > low,
      plus = host and value < spec.max,
    }
  end
  for row, cycle in pairs(CYCLES) do
    local value = s[cycle.setting]
    v.settings[row] = {
      value = value,
      text = cycle_text(row, value),
      next = next_choice(rules.SETTINGS[cycle.setting].choices, value),
      cycle = host,
    }
  end
  return v
end

function M.request(v, button)
  if not v.host then
    return nil
  end
  if button == "launch" then
    return "start", {}
  end
  local seat = tonumber(button:match("^seat_(%d+)$") or "")
  if seat then
    local s = v.seats[seat]
    if s == nil or s.toggle == nil then
      return nil
    end
    return "lobby_slot", { seat = seat, kind = s.toggle }
  end
  local row, what = button:match("^(%a+)_(%a+)$")
  local setting = v.settings[row]
  if setting == nil then
    return nil
  end
  if STEPPERS[row] and (what == "minus" or what == "plus") and setting[what] then
    return "lobby_settings", { [STEPPERS[row]] = setting.value + (what == "plus" and 1 or -1) }
  end
  if CYCLES[row] and what == "cycle" then
    return "lobby_settings", { [CYCLES[row].setting] = setting.next }
  end
  return nil
end

return M

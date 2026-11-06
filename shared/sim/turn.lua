local cat = require("shared.sim.cat")
local crate = require("shared.sim.crate")
local fixed = require("shared.sim.fixed")
local quake = require("shared.sim.quake")
local rng = require("shared.sim.rng")
local rules = require("shared.sim.rules")
local weapons = require("shared.sim.weapons.registry")

local M = {}

M.STATES = { "turn_start", "aiming", "flight", "retreat", "settling", "turn_end", "ended", "quake" }

M.CODES = {}
for i, name in ipairs(M.STATES) do
  M.CODES[name] = i
end

local TRANSITIONS = {
  turn_start = { aiming = true },
  aiming = { flight = true, retreat = true, settling = true },
  flight = { retreat = true },
  retreat = { settling = true },
  settling = { turn_end = true },
  turn_end = { turn_start = true, quake = true, ended = true },
  quake = { turn_start = true, ended = true },
  ended = {},
}

function M.transition(w, to)
  local from = w.turn.state
  if not TRANSITIONS[from][to] then
    error("no transition from " .. from .. " to " .. to)
  end
  w.turn.state = to
  w.turn.ticks = 0
end

function M.acting_team(w)
  if w.turn.state == "quake" then
    return 0
  end
  return w.turn.team
end

function M.active_cat(w)
  return w.cats[w.turn.cat]
end

local function next_cat_of(w, team)
  local members = team.cats
  for offset = 1, #members do
    local slot = fixed.mod(team.next_slot - 1 + offset - 1, #members) + 1
    local c = w.cats[members[slot]]
    if c.alive then
      team.next_slot = fixed.mod(slot, #members) + 1
      return c.id
    end
  end
  return nil
end

function M.team_alive(w, team)
  for _, id in ipairs(team.cats) do
    if w.cats[id].alive then
      return true
    end
  end
  return false
end

function M.begin(w, team_id)
  local team = w.teams[team_id]
  w.turn.team = team_id
  w.turn.cat = next_cat_of(w, team)
  local active = M.active_cat(w)
  if active then
    active.gauge = rules.GAUGE
  end
  w.turn.timer = w.settings.turn_seconds * rules.TICKS_PER_SECOND
  w.wind = rng.range(w.rng.sim, -w.settings.wind_max, w.settings.wind_max)
  for _, c in ipairs(w.cats) do
    c.hurt = false
  end
  w.events[#w.events + 1] =
    { type = "turn_started", team = team_id, cat = w.turn.cat, wind = w.wind }
  crate.drop(w)
end

local function stop_walking(w)
  local c = M.active_cat(w)
  if c then
    cat.set_walk(c, 0)
    cat.release(c, w.events)
    cat.cut(c, w.events)
  end
end

local function everything_at_rest(w)
  for _, p in ipairs(w.projectiles) do
    if p.alive then
      return false
    end
  end
  for _, c in ipairs(w.cats) do
    if not cat.at_rest(c) then
      return false
    end
  end
  for _, k in ipairs(w.crates) do
    if not crate.at_rest(k) then
      return false
    end
  end
  return true
end

local function crate_falling(w)
  for _, k in ipairs(w.crates) do
    if k.alive and k.chute then
      return true
    end
  end
  return false
end

function M.has_turn(w)
  local state = w.turn.state
  return state ~= "turn_end" and state ~= "quake" and state ~= "ended"
end

local function freeze(w)
  for _, c in ipairs(w.cats) do
    if c.alive and not cat.at_rest(c) then
      c.vx, c.vy, c.grounded = 0, 0, true
    end
  end
  for _, p in ipairs(w.projectiles) do
    if p.alive then
      p.alive = false
      w.events[#w.events + 1] = {
        type = "vanished",
        projectile = p.id,
        x = fixed.div(p.x, fixed.FP),
        y = fixed.div(p.y, fixed.FP),
      }
    end
  end
  for _, k in ipairs(w.crates) do
    crate.freeze(k, w.events)
  end
end

local function apply_deaths(w)
  for _, c in ipairs(w.cats) do
    if c.alive and c.hp <= 0 then
      c.alive = false
      c.hp = 0
      w.events[#w.events + 1] = { type = "died", cat = c.id, cause = "hp" }
    end
  end
end

local function finish(w, winner)
  M.transition(w, "ended")
  w.result = { winner = winner }
  w.events[#w.events + 1] = { type = "game_ended", winner = winner }
end

local function winner_by_hp(w)
  local best, best_hp, tie = nil, -1, false
  for _, team in ipairs(w.teams) do
    local total = 0
    for _, id in ipairs(team.cats) do
      local c = w.cats[id]
      if c.alive then
        total = total + c.hp
      end
    end
    if total > best_hp then
      best, best_hp, tie = team.id, total, false
    elseif total == best_hp then
      tie = true
    end
  end
  if tie then
    return nil
  end
  return best
end

local function living_teams(w)
  local alive = {}
  for _, team in ipairs(w.teams) do
    if M.team_alive(w, team) then
      alive[#alive + 1] = team
    end
  end
  return alive
end

local function close_rounds(w, alive)
  local played = alive[1].turns
  for _, team in ipairs(alive) do
    played = math.min(played, team.turns)
  end
  local rose, closed = false, false
  while w.rounds < played do
    w.rounds = w.rounds + 1
    closed = true
    if w.liquid.kind == "lava" and w.rounds >= rules.LAVA_RISE_FROM then
      w.liquid.level = w.liquid.level - rules.LAVA_RISE
      w.events[#w.events + 1] = { type = "liquid_rose", level = w.liquid.level }
      rose = true
    end
  end
  if rose then
    local fields = { terrain = w.terrain, liquid = w.liquid.level, events = w.events }
    for _, c in ipairs(w.cats) do
      if c.alive then
        cat.drown(c, fields)
      end
    end
    for _, k in ipairs(w.crates) do
      crate.drown(k, fields)
    end
  end
  return rose, closed
end

local function next_turn(w)
  local count = #w.teams
  for offset = 1, count do
    local id = fixed.mod(w.turn.team - 1 + offset, count) + 1
    if M.team_alive(w, w.teams[id]) then
      M.transition(w, "turn_start")
      M.begin(w, id)
      return
    end
  end
end

local function end_of_turn(w)
  apply_deaths(w)
  w.events[#w.events + 1] = { type = "turn_ended" }
  local current = w.teams[w.turn.team]
  current.turns = current.turns + 1
  local alive = living_teams(w)
  local closed = false
  if #alive >= 2 then
    local rose
    rose, closed = close_rounds(w, alive)
    if rose then
      alive = living_teams(w)
    end
  end
  if #alive <= 1 then
    local survivor = alive[1]
    finish(w, survivor and survivor.id)
    return
  end
  local all_done = true
  for _, team in ipairs(alive) do
    if team.turns < rules.MAX_ROUNDS then
      all_done = false
    end
  end
  if all_done then
    finish(w, winner_by_hp(w))
    return
  end
  if closed and quake.due(w) then
    M.transition(w, "quake")
    quake.begin(w)
    return
  end
  next_turn(w)
end

local function end_of_quake(w)
  apply_deaths(w)
  local alive = living_teams(w)
  if #alive <= 1 then
    local survivor = alive[1]
    finish(w, survivor and survivor.id)
    return
  end
  next_turn(w)
end

local function active_hurt(w)
  local c = M.active_cat(w)
  return c == nil or not c.alive or c.hurt
end

function M.before_physics(w)
  w.turn.ticks = w.turn.ticks + 1
  if w.turn.state == "quake" then
    quake.act(w)
  end
end

function M.after_physics(w)
  local state = w.turn.state
  if state == "turn_start" then
    local waited = w.turn.ticks >= rules.CRATE_WAIT_TICKS
    if w.turn.ticks >= rules.TURN_START_TICKS and (waited or not crate_falling(w)) then
      M.transition(w, "aiming")
    end
  elseif state == "aiming" then
    w.turn.timer = w.turn.timer - 1
    if active_hurt(w) or w.turn.timer <= 0 then
      stop_walking(w)
      M.transition(w, "settling")
    end
  elseif state == "flight" then
    local flying = false
    for _, p in ipairs(w.projectiles) do
      if p.alive then
        flying = true
      end
    end
    for _, c in ipairs(w.cats) do
      if c.dig > 0 then
        flying = true
      end
    end
    if not flying then
      M.transition(w, "retreat")
      w.turn.timer = rules.RETREAT_TICKS
    end
  elseif state == "retreat" then
    w.turn.timer = w.turn.timer - 1
    if active_hurt(w) or w.turn.timer <= 0 then
      stop_walking(w)
      M.transition(w, "settling")
    end
  elseif state == "settling" then
    if everything_at_rest(w) then
      M.transition(w, "turn_end")
    elseif w.turn.ticks >= rules.SETTLE_MAX_TICKS then
      freeze(w)
      M.transition(w, "turn_end")
    end
  elseif state == "turn_end" then
    end_of_turn(w)
  elseif state == "quake" then
    if w.turn.ticks >= quake.LAST_SHAKE and everything_at_rest(w) then
      end_of_quake(w)
    elseif w.turn.ticks >= rules.SETTLE_MAX_TICKS then
      freeze(w)
      end_of_quake(w)
    end
  end
end

function M.fired(w)
  stop_walking(w)
  M.transition(w, "flight")
end

function M.placed(w, ticks)
  stop_walking(w)
  M.transition(w, "retreat")
  w.turn.timer = ticks
  M.active_cat(w).gauge = rules.GAUGE
end

function M.skipped(w)
  stop_walking(w)
  M.transition(w, "settling")
end

function M.triggerable(w)
  for _, p in ipairs(w.projectiles) do
    local owner = w.cats[p.owner]
    if p.alive and weapons.get(p.weapon).trigger and owner and owner.team == w.turn.team then
      return true
    end
  end
  return false
end

function M.accepts(w, kind)
  local state = w.turn.state
  if kind == "move" or kind == "jump" then
    return state == "aiming" or state == "retreat"
  end
  if kind == "fire" and state == "flight" then
    return M.triggerable(w)
  end
  return state == "aiming"
end

return M

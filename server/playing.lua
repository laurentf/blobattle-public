local driver = require("shared.bots.driver")
local log = require("server.log")
local names = require("shared.names")
local nk = require("nakama")
local phase = require("server.phase")
local players = require("server.players")
local protocol = require("shared.protocol")
local rng = require("shared.sim.rng")
local rules = require("shared.sim.rules")
local snapshots = require("server.snapshots")
local stats = require("shared.sim.stats")
local turn = require("shared.sim.turn")
local weapons = require("shared.sim.weapons.registry")
local world = require("shared.sim.world")

local clock = os.clock

local M = {}

M.OPS = { input = true, fire = true, skip = true, snapshot_request = true }
M.join_attempt = players.registered_join

local function draw_seed()
  return tonumber(nk.uuid_v4():sub(1, 8), 16) % rng.MAX_SEED + 1
end

local function roster_of(state, seed)
  local generated = names.game(seed, #state.seats)
  local roster, bots = {}, {}
  for i, seat in ipairs(state.seats) do
    local named = generated[i]
    if seat.user then
      named = state.players[seat.user].team or named
      roster[i] = { team = i, kind = "human", user = seat.user, name = seat.name }
    else
      roster[i] = { team = i, kind = "bot" }
      bots[#bots + 1] = i
    end
    roster[i].team_name, roster[i].members = named.name, named.members
  end
  return roster, bots
end

function M.start(state, dispatcher)
  local seed = state.seed
  if seed == 0 then
    seed = draw_seed()
  end
  local roster, bots = roster_of(state, seed)
  local started = clock()
  local w = assert(world.new(seed, state.settings))
  local generated_ms = (clock() - started) * 1000
  state.world = w
  state.driver = driver.new({
    teams = bots,
    level = state.settings.bot_level,
    seed = seed,
    budget = rules.BOT_SERVER_WORK_PER_TICK,
  })
  state.stats = stats.new(w)
  state.inputs, state.outbox, state.closing = {}, {}, false
  state.snapshots, state.snapshot_cache, state.game_end = {}, {}, nil
  for _, player in pairs(state.players) do
    player.absent, player.returning = false, false
  end
  state.timing = { ticks = 0, total = 0, max = 0 }
  phase.set(state, dispatcher, "playing")
  state.game_start = nk.json_encode({ seed = seed, settings = state.settings, roster = roster })
  dispatcher.broadcast_message(protocol.OPS.game_start, state.game_start)
  log.info(
    state,
    string.format(
      "🎮 game started seed=%d teams=%d cats=%d bots=%d generated_ms=%.0f",
      seed,
      state.settings.teams,
      state.settings.cats_per_team,
      #bots,
      generated_ms
    )
  )
end

local function tell_pilots(state, dispatcher, presences)
  local bots = {}
  for i = 1, #state.seats do
    if state.driver.bots[i] ~= nil then
      bots[#bots + 1] = i
    end
  end
  dispatcher.broadcast_message(protocol.OPS.pilots, nk.json_encode({ bots = bots }), presences)
end

function M.join(state, dispatcher, presences)
  for _, p in ipairs(presences) do
    local player = state.players[p.user_id]
    if player and player.absent and not player.returning then
      player.returning = true
      log.info(state, "🔁 player back team=" .. player.seat .. " player=" .. player.name)
    end
    dispatcher.broadcast_message(protocol.OPS.game_start, state.game_start, { p })
    snapshots.send(state, dispatcher, p)
    tell_pilots(state, dispatcher, { p })
  end
end

function M.leave(state, dispatcher, presence)
  snapshots.forget(state, presence)
  local player = state.players[presence.user_id]
  if player == nil or players.present(state, presence.user_id) then
    return
  end
  player.absent, player.returning = true, false
  driver.take(state.driver, player.seat)
  tell_pilots(state, dispatcher)
  local w = state.world
  if w.turn.team == player.seat and turn.accepts(w, "move") then
    state.inputs[#state.inputs + 1] = { team = player.seat, kind = "move", direction = 0 }
    local c = turn.active_cat(w)
    if c and (c.hanging or c.jet > 0) then
      state.inputs[#state.inputs + 1] = { team = player.seat, kind = "jump", direction = c.facing }
    end
  end
  log.info(state, "🔁 player away, a bot plays team=" .. player.seat .. " player=" .. player.name)
end

local function hand_back(state, dispatcher, events)
  for _, e in ipairs(events) do
    if e.type == "turn_started" then
      local released = false
      for _, player in pairs(state.players) do
        if player.returning then
          player.absent, player.returning = false, false
          driver.release(state.driver, player.seat)
          released = true
          log.info(
            state,
            "🔁 player plays again team=" .. player.seat .. " player=" .. player.name
          )
        end
      end
      if released then
        tell_pilots(state, dispatcher)
      end
      return
    end
  end
end

function M.handle(state, dispatcher, sender, name, msg)
  if name == "snapshot_request" then
    return snapshots.request(state, dispatcher, sender, msg)
  end
  local w = state.world
  local player = state.players[sender.user_id]
  local team = w.turn.team
  if player == nil or player.seat ~= team or state.driver.bots[team] ~= nil then
    return "not_your_turn"
  end
  local kind = name == "input" and msg.kind or name
  if state.closing or not turn.accepts(w, kind) then
    return "not_now"
  end
  local input = { team = team, kind = kind }
  if name == "input" then
    input.direction = msg.direction
  elseif name == "fire" then
    if w.turn.state == "aiming" then
      if w.teams[team].ammo[weapons.index_of(msg.weapon)] == 0 then
        return "no_ammo"
      end
      if msg.target ~= nil and msg.target >= w.terrain.width then
        return "invalid_target"
      end
    end
    input.weapon, input.angle, input.power, input.fuse = msg.weapon, msg.angle, msg.power, msg.fuse
    input.target = msg.target
  end
  if
    kind == "skip"
    or (kind == "fire" and (weapons.ends_turn(msg.weapon) or w.turn.state == "flight"))
  then
    state.closing = true
  end
  state.inputs[#state.inputs + 1] = input
  return nil
end

local function send(dispatcher, op, message)
  dispatcher.broadcast_message(op, nk.json_encode(message))
end

function M.timing(state)
  local w, timing = state.world, state.timing
  if w == nil then
    return ""
  end
  return string.format(
    " ticks=%d tick_ms_avg=%.2f tick_ms_max=%.2f",
    w.tick,
    timing.total * 1000 / math.max(timing.ticks, 1),
    timing.max * 1000
  )
end

local function finish(state, dispatcher)
  local w = state.world
  state.game_end = { winner = w.result.winner or 0, stats = state.stats, host = state.host }
  send(dispatcher, protocol.OPS.game_end, state.game_end)
  phase.set(state, dispatcher, "ended")
  log.info(state, "🎮 game ended winner=" .. (w.result.winner or 0) .. M.timing(state))
end

function M.tick(state, dispatcher)
  local started = clock()
  local w = state.world
  local inputs = state.inputs
  for _, input in ipairs(driver.inputs(state.driver, w) or {}) do
    inputs[#inputs + 1] = input
  end
  local at, acting = w.tick, turn.acting_team(w)
  for _, input in ipairs(inputs) do
    state.outbox[#state.outbox + 1] = { at = at, input = input }
  end
  local events = world.step(w, inputs)
  stats.record(state.stats, w, acting, events)
  hand_back(state, dispatcher, events)
  state.inputs, state.closing = {}, false
  local ended = w.turn.state == "ended"
  if ended or w.tick % rules.TICKS_MESSAGE_EVERY == 0 then
    send(dispatcher, protocol.OPS.ticks, { to = w.tick, inputs = state.outbox })
    state.outbox = {}
  end
  if ended or w.tick % rules.CHECKSUM_EVERY == 0 then
    local a, b = world.checksum(w)
    send(dispatcher, protocol.OPS.checksum, { tick = w.tick, sum = { a, b } })
  end
  local spent = clock() - started
  local timing = state.timing
  timing.ticks, timing.total = timing.ticks + 1, timing.total + spent
  if spent > timing.max then
    timing.max = spent
  end
  if ended then
    finish(state, dispatcher)
  end
end

return M

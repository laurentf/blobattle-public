local driver = require("shared.bots.driver")
local names = require("shared.names")
local protocol = require("shared.protocol")
local rules = require("shared.sim.rules")
local stats = require("shared.sim.stats")
local turn = require("shared.sim.turn")
local weapons = require("shared.sim.weapons.registry")
local world = require("shared.sim.world")

local M = {}

M.HUMAN_SEAT = 1
M.MAX_CATCH_UP = 4

local PLAYING_OPS = { input = true, fire = true, skip = true, snapshot_request = true }
local ENDED_OPS = { snapshot_request = true }
local NONE = {}

local TICK = 1 / rules.TICKS_PER_SECOND
local EPSILON = 1e-9

local function roster_of(seed, teams, player)
  local generated = names.game(seed, teams)
  local roster, bots = {}, {}
  for team = 1, teams do
    if team == M.HUMAN_SEAT then
      roster[team] = {
        team = team,
        kind = "human",
        name = player.nickname,
        team_name = player.team_name,
        members = player.members,
      }
    else
      roster[team] = {
        team = team,
        kind = "bot",
        team_name = generated[team].name,
        members = generated[team].members,
      }
      bots[#bots + 1] = team
    end
  end
  return roster, bots
end

function M.new(fields)
  local self = { budget = fields.budget or rules.BOT_WORK_PER_TICK }
  local w, d, s
  local outbox, pending, messages, drained = {}, {}, {}, {}
  local acc, closing, over = 0, false, false
  local roster, last_snapshot

  local function emit(name, data)
    messages[#messages + 1] = { name = name, data = data }
  end

  function self.start()
    local settings = assert(world.resolve_settings(fields.settings))
    w = assert(world.new(fields.seed, settings))
    local bots
    roster, bots = roster_of(fields.seed, settings.teams, fields.player)
    d = driver.new({
      teams = bots,
      level = settings.bot_level,
      seed = fields.seed,
      budget = self.budget,
    })
    s = stats.new(w)
    self.world = w
    emit("game_start", { seed = fields.seed, settings = settings, roster = roster })
  end

  local function refuse(code)
    emit("refused", { code = code })
  end

  local function accept(name, msg)
    local team = w.turn.team
    if team ~= M.HUMAN_SEAT or d.bots[team] ~= nil then
      return "not_your_turn"
    end
    local kind = name == "input" and msg.kind or name
    if closing or not turn.accepts(w, kind) then
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
      input.weapon, input.angle, input.power, input.fuse =
        msg.weapon, msg.angle, msg.power, msg.fuse
      input.target = msg.target
    end
    if
      kind == "skip"
      or (kind == "fire" and (weapons.ends_turn(msg.weapon) or w.turn.state == "flight"))
    then
      closing = true
    end
    pending[#pending + 1] = input
    return nil
  end

  local function request_snapshot()
    if last_snapshot ~= nil and w.tick - last_snapshot < rules.SNAPSHOT_REQUEST_TICKS then
      return "too_soon"
    end
    last_snapshot = w.tick
    emit("snapshot", { tick = w.tick, state = world.snapshot(w) })
    return nil
  end

  function self.send(name, body)
    local op = protocol.OPS[name]
    if op == nil or protocol.CLIENT_OPS[op] == nil then
      return refuse("unknown_op")
    end
    local phase = over and ENDED_OPS or PLAYING_OPS
    if w == nil or not phase[name] then
      return refuse("wrong_phase")
    end
    local msg, err = protocol.decode(op, body)
    if msg == nil then
      return refuse(err)
    end
    local reason
    if name == "snapshot_request" then
      reason = request_snapshot()
    else
      reason = accept(name, msg)
    end
    if reason then
      refuse(reason)
    end
  end

  local function step()
    local inputs = pending
    for _, input in ipairs(driver.inputs(d, w) or NONE) do
      inputs[#inputs + 1] = input
    end
    local at, acting = w.tick, turn.acting_team(w)
    for _, input in ipairs(inputs) do
      outbox[#outbox + 1] = { at = at, input = input }
    end
    stats.record(s, w, acting, world.step(w, inputs))
    for i = #pending, 1, -1 do
      pending[i] = nil
    end
    closing = false
    local ended = w.turn.state == "ended"
    if ended or w.tick % rules.TICKS_MESSAGE_EVERY == 0 then
      emit("ticks", { to = w.tick, inputs = outbox })
      outbox = {}
    end
    if ended or w.tick % rules.CHECKSUM_EVERY == 0 then
      local a, b = world.checksum(w)
      emit("checksum", { tick = w.tick, sum = { a, b } })
    end
    if ended then
      over = true
      emit("game_end", { winner = w.result.winner or 0, stats = s })
    end
  end

  function self.update(dt)
    if w == nil or over then
      return
    end
    acc = acc + dt
    local steps = 0
    while acc >= TICK - EPSILON and steps < M.MAX_CATCH_UP and not over do
      acc = acc - TICK
      step()
      steps = steps + 1
    end
    if steps == M.MAX_CATCH_UP then
      acc = math.min(acc, TICK)
    end
  end

  function self.team()
    return M.HUMAN_SEAT
  end

  function self.poll()
    for i = #drained, 1, -1 do
      drained[i] = nil
    end
    local out = messages
    messages, drained = drained, out
    return out
  end

  function self.stop()
    over = true
  end

  return self
end

return M

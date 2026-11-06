local nk = require("nakama")

local brain = require("shared.bots.brain")
local mapgen = require("shared.sim.mapgen")
local rules = require("shared.sim.rules")
local runner = require("conformance.runner")
local world = require("shared.sim.world")

local function vector_sums(_, payload)
  local request = nk.json_decode(payload)
  local vector = require("vectors." .. request.name)
  local started = nk.time()
  local sums = runner.run(vector)
  return nk.json_encode({
    name = vector.name,
    sums = sums,
    names = runner.name_lines(runner.names(vector)),
    ms = nk.time() - started,
  })
end

local function bot_ticks(w, level)
  local bot = brain.new({ team = w.turn.team, level = level, seed = 1 })
  local calls, work, spent = {}, 0, 0
  while w.turn.state == "turn_start" or (w.turn.state == "aiming" and bot.decision == nil) do
    local started = os.clock()
    local input = brain.think(bot, w, rules.BOT_SERVER_WORK_PER_TICK)
    local ms = (os.clock() - started) * 1000
    calls[#calls + 1] = ms
    spent, work = spent + ms, work + bot.work
    world.step(w, input and { input } or {})
  end
  table.sort(calls)
  local over = 0
  for _, ms in ipairs(calls) do
    if ms >= 8 then
      over = over + 1
    end
  end
  return {
    level = level,
    calls = #calls,
    avg_ms = spent / #calls,
    p90_ms = calls[math.ceil(#calls * 9 / 10)],
    max_ms = calls[#calls],
    over_8ms = over,
    work = work,
    unit_us = spent * 1000 / work,
  }
end

local function measure(_, payload)
  local request = nk.json_decode(payload)
  if request.what == "map" then
    local started = os.clock()
    mapgen.generate(1, { teams = 8, cats_per_team = 6, map = "random" })
    return nk.json_encode({ largest_map_ms = (os.clock() - started) * 1000 })
  elseif request.what == "snapshot" then
    local w = assert(world.new(4242, { teams = 8, cats_per_team = 6 }))
    local cache = {}
    local started = os.clock()
    world.snapshot(w, cache)
    local cold = (os.clock() - started) * 1000
    started = os.clock()
    local snapshot = world.snapshot(w, cache)
    local warm = (os.clock() - started) * 1000
    started = os.clock()
    local encoded = nk.json_encode({ tick = w.tick, state = snapshot })
    return nk.json_encode({
      snapshot_cold_ms = cold,
      snapshot_cached_ms = warm,
      encode_ms = (os.clock() - started) * 1000,
      bytes = #encoded,
    })
  elseif request.what == "bot" then
    local w = assert(world.new(4242, { teams = 8, cats_per_team = 6 }))
    return nk.json_encode(bot_ticks(w, request.level))
  end
  local brawl = require("vectors.brawl")
  local started = os.clock()
  runner.run(brawl)
  local ticks = brawl.checks[#brawl.checks]
  return nk.json_encode({ brawl_tick_ms = (os.clock() - started) * 1000 / ticks })
end

nk.register_rpc(vector_sums, "conformance_vector")
nk.register_rpc(measure, "conformance_measure")

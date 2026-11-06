local rules = require("shared.sim.rules")
local stats = require("shared.sim.stats")
local turn = require("shared.sim.turn")
local world = require("shared.sim.world")

local M = {}

local function fail(report, text)
  report.errors[#report.errors + 1] = text
end

local function index_by_tick(report, list, what)
  local out = {}
  for _, item in ipairs(list or {}) do
    if out[item.tick] then
      fail(report, what .. " at tick " .. item.tick .. " received twice")
    end
    out[item.tick] = item
  end
  return out
end

local function schedule(recording, report)
  local by_tick, previous = {}, 0
  local count = #recording.ticks
  for i, message in ipairs(recording.ticks) do
    local span = message.to - previous
    local closing = i == count and recording.game_end ~= nil
    if span ~= 2 and not (closing and span == 1) then
      fail(report, "gap in the ticks stream before tick " .. message.to)
    end
    for _, entry in ipairs(message.inputs or {}) do
      if entry.at < previous or entry.at >= message.to then
        fail(
          report,
          "input at tick "
            .. entry.at
            .. " outside its message ["
            .. previous
            .. ", "
            .. message.to
            .. ")"
        )
      end
      local list = by_tick[entry.at] or {}
      list[#list + 1] = entry.input
      by_tick[entry.at] = list
      report.inputs = report.inputs + 1
    end
    previous = message.to
  end
  report.final_tick = previous
  return by_tick
end

local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a == b
  end
  for k, v in pairs(a) do
    if not same(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

local function check_end(recording, w, s, report)
  local ending = recording.game_end
  if ending == nil then
    if w.turn.state == "ended" then
      fail(report, "the replay is over at tick " .. w.tick .. " but no game_end was received")
    end
    return
  end
  if w.turn.state ~= "ended" then
    fail(report, "the replay is not over at tick " .. w.tick .. " although game_end was received")
    return
  end
  if (w.result.winner or 0) ~= ending.winner then
    fail(
      report,
      "winner " .. ending.winner .. " announced, " .. (w.result.winner or 0) .. " replayed"
    )
  end
  if #ending.stats ~= #s then
    fail(report, "stats announced for " .. #ending.stats .. " teams, replayed for " .. #s)
  end
  for i, line in ipairs(s) do
    local told = ending.stats[i] or {}
    if told.team ~= line.team or told.damage ~= line.damage or told.kills ~= line.kills then
      fail(report, "stats of team " .. line.team .. " differ")
    end
  end
end

local function check_schedule(recording, report, compared, ended)
  for tick = rules.CHECKSUM_EVERY, report.final_tick, rules.CHECKSUM_EVERY do
    if not compared[tick] then
      fail(report, "checksum missing at tick " .. tick)
    end
  end
  if ended and not compared[report.final_tick] then
    fail(report, "checksum missing at the final tick " .. report.final_tick)
  end
  for _, sum in ipairs(recording.checksums) do
    if not compared[sum.tick] then
      fail(report, "checksum at tick " .. sum.tick .. " never compared")
    end
  end
  if report.checksums == 0 then
    fail(report, "no checksum received")
  end
end

function M.check(recording)
  local report = { errors = {}, checksums = 0, snapshots = 0, inputs = 0, final_tick = 0 }
  local start = recording.game_start
  local w = assert(world.new(start.seed, start.settings))
  local s = stats.new(w)
  local by_tick = schedule(recording, report)
  local sums = index_by_tick(report, recording.checksums, "checksum")
  local snaps = index_by_tick(report, recording.snapshots, "snapshot")
  local compared, checked = {}, {}
  while w.tick < report.final_tick do
    if w.turn.state == "ended" then
      fail(
        report,
        "the replay ended at tick " .. w.tick .. ", the stream goes on to " .. report.final_tick
      )
      break
    end
    local snap = snaps[w.tick]
    if snap then
      if not same(world.snapshot(w), snap.state) then
        fail(report, "snapshot at tick " .. w.tick .. " differs from the replayed world")
      end
      checked[w.tick] = true
      report.snapshots = report.snapshots + 1
    end
    local acting = turn.acting_team(w)
    stats.record(s, w, acting, world.step(w, by_tick[w.tick]))
    local sum = sums[w.tick]
    if sum then
      local a, b = world.checksum(w)
      if sum.sum[1] ~= a or sum.sum[2] ~= b then
        fail(report, "checksum at tick " .. w.tick .. " differs")
      end
      compared[w.tick] = true
      report.checksums = report.checksums + 1
    end
  end
  for _, snap in ipairs(recording.snapshots or {}) do
    if not checked[snap.tick] then
      fail(report, "snapshot at tick " .. snap.tick .. " never checked")
    end
  end
  check_schedule(recording, report, compared, recording.game_end ~= nil)
  check_end(recording, w, s, report)
  return report
end

return M

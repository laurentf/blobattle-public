local fake = require("spec.support.nakama")
local protocol = require("shared.protocol")
local replay = require("tools.harness.replay")
local room_support = require("spec.support.room")

local OPS = protocol.OPS

local function record_game()
  local nk = fake.install()
  local room = room_support.open(nk, { teams = 3, cats_per_team = 1 })
  local host = room_support.arrive(nk, room, "host", "Host")
  room.loop({ fake.message(host, OPS.lobby_settings, { seed = 8 }) })
  room.loop({ fake.message(host, OPS.start, {}) })
  local w = room.state().world
  local mine = room.state().players.host.seat
  local rejoined = false
  for _ = 1, 30000 do
    if room.state().phase ~= "playing" then
      break
    end
    if w.turn.team == mine and w.turn.state == "aiming" then
      room.loop({
        fake.message(host, OPS.fire, { weapon = "grenade", angle = 256, power = 1, fuse = 1 }),
      })
    else
      room.loop()
    end
    if not rejoined and w.tick == 1000 then
      room.leave(host)
      host = fake.presence("host", "s-again")
      room.join(host)
      rejoined = true
    end
  end
  assert(room.state().phase == "ended")
  local recording = {
    game_start = room.received(OPS.game_start)[1],
    ticks = room.received(OPS.ticks),
    checksums = room.received(OPS.checksum),
    snapshots = room.received(OPS.snapshot),
    game_end = room.received(OPS.game_end)[1],
  }
  return recording
end

describe("🧮 the harness replay (§10.3)", function()
  local recording = record_game()

  it(
    "🧮 finds every checksum, snapshot, the end and the stats of a game played by the server",
    function()
      local report = replay.check(recording)
      assert.are.same({}, report.errors)
      assert.are.equal(#recording.checksums, report.checksums)
      assert.is_true(report.checksums >= 20)
      assert.are.equal(1, report.snapshots)
      assert.is_true(report.inputs > 0)
      assert.are.equal(recording.ticks[#recording.ticks].to, report.final_tick)
    end
  )

  it("🧮 reports a checksum that does not match", function()
    local tampered = recording.checksums[5]
    tampered.sum[1] = tampered.sum[1] + 1
    local report = replay.check(recording)
    tampered.sum[1] = tampered.sum[1] - 1
    assert.are.equal(1, #report.errors)
    assert.truthy(report.errors[1]:find("checksum at tick " .. tampered.tick, 1, true))
  end)

  it(
    "🧮 reports a gap in the ticks stream, an input outside its message, and a wrong winner",
    function()
      local removed = table.remove(recording.ticks, 10)
      local report = replay.check(recording)
      table.insert(recording.ticks, 10, removed)
      assert.truthy(report.errors[1]:find("gap", 1, true))

      local message = recording.ticks[3]
      message.inputs[#message.inputs + 1] =
        { at = message.to + 5, input = { team = 1, kind = "skip" } }
      report = replay.check(recording)
      message.inputs[#message.inputs] = nil
      assert.truthy(report.errors[1]:find("outside", 1, true))

      local winner = recording.game_end.winner
      recording.game_end.winner = winner == 1 and 2 or 1
      report = replay.check(recording)
      recording.game_end.winner = winner
      assert.truthy(report.errors[#report.errors]:find("winner", 1, true))
    end
  )

  it("🧮 reports a recording without any checksum instead of passing it", function()
    local report = replay.check({
      game_start = recording.game_start,
      ticks = {},
      checksums = {},
      snapshots = {},
    })
    assert.truthy(report.errors[1] and report.errors[1]:find("no checksum", 1, true))
  end)

  local function errors_of(change, undo)
    change()
    local report = replay.check(recording)
    undo()
    return table.concat(report.errors, "\n")
  end

  it("🧮 fails, without hanging, when the replayed game ends before the stream", function()
    local ticks = recording.ticks
    local last_message = ticks[#ticks]
    local extra = { to = last_message.to + 2, inputs = {} }
    local text = errors_of(function()
      ticks[#ticks + 1] = extra
    end, function()
      ticks[#ticks] = nil
    end)
    assert.truthy(text:find("ended at tick", 1, true), text)
  end)

  it(
    "🧮 reports a short message in the middle of the stream and an input at its own `to`",
    function()
      local message = recording.ticks[4]
      local text = errors_of(function()
        message.to = message.to - 1
      end, function()
        message.to = message.to + 1
      end)
      assert.truthy(
        text:find("gap in the ticks stream before tick " .. (message.to - 1), 1, true),
        text
      )
      local early = { at = recording.ticks[5].to - 1, input = { team = 1, kind = "skip" } }
      local later = recording.ticks[6].inputs
      text = errors_of(function()
        later[#later + 1] = early
      end, function()
        later[#later] = nil
      end)
      assert.truthy(text:find("outside", 1, true), text)
      local entry = { at = recording.ticks[6].to, input = { team = 1, kind = "skip" } }
      local inputs = recording.ticks[6].inputs
      text = errors_of(function()
        inputs[#inputs + 1] = entry
      end, function()
        inputs[#inputs] = nil
      end)
      assert.truthy(text:find("outside", 1, true), text)
    end
  )

  it("🧮 reports a missing checksum, a duplicate one, and one after the stream", function()
    local sums = recording.checksums
    local removed
    local text = errors_of(function()
      removed = table.remove(sums, 3)
    end, function()
      table.insert(sums, 3, removed)
    end)
    assert.truthy(text:find("missing at tick " .. removed.tick, 1, true), text)
    text = errors_of(function()
      table.insert(sums, 3, sums[3])
    end, function()
      table.remove(sums, 3)
    end)
    assert.truthy(text:find("twice", 1, true), text)
    local final = recording.ticks[#recording.ticks].to
    text = errors_of(function()
      sums[#sums + 1] = { tick = final + 30, sum = { 1, 2 } }
    end, function()
      sums[#sums] = nil
    end)
    assert.truthy(text:find("never compared", 1, true), text)
  end)

  it("🧮 compares a snapshot field by field, and reports one it cannot check", function()
    local snap = recording.snapshots[1]
    local runs = snap.state.terrain
    local text = errors_of(function()
      runs[#runs] = runs[#runs] + 1
      runs[#runs - 1] = runs[#runs - 1] - 1
    end, function()
      runs[#runs] = runs[#runs] - 1
      runs[#runs - 1] = runs[#runs - 1] + 1
    end)
    assert.truthy(text:find("snapshot at tick " .. snap.tick, 1, true), text)
    local late = { tick = recording.ticks[#recording.ticks].to + 10, state = snap.state }
    text = errors_of(function()
      recording.snapshots[2] = late
    end, function()
      recording.snapshots[2] = nil
    end)
    assert.truthy(text:find("never checked", 1, true), text)
  end)

  it("🧮 reports the stats of game_end that the replay does not find, line by line", function()
    local line = recording.game_end.stats[1]
    local text = errors_of(function()
      line.damage = line.damage + 1
    end, function()
      line.damage = line.damage - 1
    end)
    assert.truthy(text:find("stats of team 1", 1, true), text)
    local stats = recording.game_end.stats
    text = errors_of(function()
      stats[#stats + 1] = { team = 9, damage = 0, kills = 0 }
    end, function()
      stats[#stats] = nil
    end)
    assert.truthy(text:find("stats", 1, true), text)
  end)

  it(
    "🧮 reports a game over in the replay but never announced, and an announced end not reached",
    function()
      local ending = recording.game_end
      local text = errors_of(function()
        recording.game_end = nil
      end, function()
        recording.game_end = ending
      end)
      assert.truthy(text:find("no game_end", 1, true), text)
      local removed
      text = errors_of(function()
        removed = table.remove(recording.ticks)
      end, function()
        recording.ticks[#recording.ticks + 1] = removed
      end)
      assert.truthy(text:find("not over", 1, true), text)
    end
  )
end)

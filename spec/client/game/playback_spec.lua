local LocalAuthority = require("authority.local_authority")
local playback = require("game.playback")
local world = require("shared.sim.world")

local FRAME = 1 / 60

local PLAYER = {
  nickname = "Tester",
  team_name = "Pawtesters",
  members = { "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot" },
}

local function session(settings)
  local a = LocalAuthority.new({ seed = 70, settings = settings, player = PLAYER })
  local events = {}
  local p = playback.new({
    on_events = function(list)
      for _, e in ipairs(list) do
        events[#events + 1] = e
      end
    end,
  })
  a.start()
  return a, p, events
end

local function pump(a, p)
  a.update(FRAME)
  local confirmed = nil
  for _, m in ipairs(a.poll()) do
    p.receive(m)
    if m.name == "ticks" then
      confirmed = m.data.to
    end
  end
  return confirmed
end

describe("🎞️ the client playback of the authority's stream (§6.5, §7.1, D-03)", function()
  it("🎞️ never simulates past the confirmed tick and finds every checksum", function()
    local a, p = session({ teams = 2, cats_per_team = 1, bot_level = "hard" })
    local confirmed = 0
    for _ = 1, 20000 do
      confirmed = pump(a, p) or confirmed
      local alpha = p.advance(FRAME)
      assert.is_true(p.world.tick <= confirmed, p.world.tick .. " past " .. confirmed)
      assert.is_true(alpha >= 0 and alpha <= 1)
      if p.world.turn.team == 1 and a.world.turn.state == "aiming" then
        a.send("skip", {})
      end
      if p.result then
        break
      end
    end
    local checks = p.checked
    assert.is_table(p.result)
    assert.are.equal(0, p.divergences)
    assert.is_true(checks > 5, checks .. " checksums compared")
    assert.are.same({ world.checksum(a.world) }, { world.checksum(p.world) })
  end)

  it("🎞️ keeps up with the authority, one or two ticks behind at most", function()
    local a, p = session({ teams = 2, cats_per_team = 1 })
    local worst = 0
    for _ = 1, 600 do
      pump(a, p)
      p.advance(FRAME)
      worst = math.max(worst, a.world.tick - p.world.tick)
    end
    assert.is_true(worst <= 2, worst .. " ticks behind")
    assert.is_true(p.world.tick >= 290)
  end)

  it("🎞️ hands the renderer every event of every step, in order", function()
    local a, p, events = session({ teams = 2, cats_per_team = 1 })
    local fired = false
    for _ = 1, 3000 do
      pump(a, p)
      p.advance(FRAME)
      if not fired and a.world.turn.team == 1 and a.world.turn.state == "aiming" then
        a.send("fire", { weapon = "bazooka", angle = 768, power = 5 })
        fired = true
      end
    end
    local kinds = {}
    for _, e in ipairs(events) do
      kinds[e.type] = true
    end
    assert.is_true(kinds.turn_started and kinds.exploded and kinds.damaged)
  end)

  it("🎞️ keeps each cat's position of the previous tick to interpolate from", function()
    local a, p = session({ teams = 2, cats_per_team = 1 })
    local moved, steps = false, 0
    for _ = 1, 3000 do
      pump(a, p)
      local w = p.world
      if w.turn.team == 1 and w.turn.state == "aiming" and not moved then
        a.send("input", { kind = "move", direction = -1 })
        moved = true
      end
      local c = w.cats[w.teams[1].cats[1]]
      local x, y, tick = c.x, c.y, w.tick
      p.advance(FRAME)
      if w.tick == tick + 1 and x ~= c.x then
        steps = steps + 1
        if steps == 3 then
          local before = p.before(c.id)
          assert.are.same({ x, y }, { before.x, before.y })
          return
        end
      end
    end
    error("the player's cat never walked")
  end)

  local TICK = 1 / 30

  local function silent_start()
    local a = LocalAuthority.new({
      seed = 77,
      settings = { teams = 2, cats_per_team = 1 },
      player = PLAYER,
    })
    local p = playback.new({})
    a.start()
    for _, m in ipairs(a.poll()) do
      p.receive(m)
    end
    return p
  end

  local function ticks_to(p, from, to)
    for t = from + 2, to, 2 do
      p.receive({ name = "ticks", data = { to = t, inputs = {} } })
    end
  end

  it("🎞️ counts a checksum that does not match as a divergence", function()
    local p = silent_start()
    ticks_to(p, 0, 30)
    p.receive({ name = "checksum", data = { tick = 30, sum = { 1, 2 } } })
    for _ = 1, 60 do
      p.advance(TICK)
    end
    assert.are.equal(30, p.world.tick)
    assert.are.equal(1, p.checked)
    assert.are.equal(1, p.divergences)
  end)

  it("🎞️ catches up at once when it lags more than MAX_LAG ticks, and not further", function()
    local p = silent_start()
    ticks_to(p, 0, 40)
    p.advance(0)
    assert.are.equal(40 - playback.MAX_LAG, p.world.tick)
    p.advance(0)
    assert.are.equal(40 - playback.MAX_LAG, p.world.tick)
  end)

  it("🎞️ does not bank the time spent waiting for the authority", function()
    local p = silent_start()
    ticks_to(p, 0, 2)
    p.advance(1)
    assert.are.equal(2, p.world.tick)
    ticks_to(p, 2, 6)
    p.advance(0)
    assert.are.equal(3, p.world.tick)
  end)

  it("🎞️ reports the end only once its own world has ended", function()
    local p = silent_start()
    ticks_to(p, 0, 4)
    p.receive({ name = "game_end", data = { winner = 1, stats = {} } })
    for _ = 1, 10 do
      p.advance(TICK)
    end
    assert.are.equal(4, p.world.tick)
    assert.is_nil(p.result)
  end)

  it(
    "🎞️ restores a snapshot, then applies only the inputs from its tick on (§6.6)",
    function()
      local a, p = session({ teams = 2, cats_per_team = 1, bot_level = "hard" })
      local deaf, restored_at, missed = false, nil, 0
      for _ = 1, 20000 do
        a.update(FRAME)
        for _, m in ipairs(a.poll()) do
          if deaf and m.name == "ticks" then
            missed = missed + #m.data.inputs
          end
          if not deaf or m.name == "snapshot" then
            p.receive(m)
          end
          if m.name == "snapshot" then
            restored_at = m.data.tick
            assert.are.equal(restored_at, p.world.tick)
            assert.are.equal(restored_at, p.confirmed)
            for _, c in ipairs(p.world.cats) do
              assert.are.same({ c.x, c.y }, { p.before(c.id).x, p.before(c.id).y })
            end
          end
        end
        p.advance(FRAME)
        if a.world.tick >= 240 and not deaf and restored_at == nil then
          deaf = true
        elseif a.world.tick >= 480 and deaf then
          deaf = false
          a.send("snapshot_request", { tick = 480 })
        end
        if a.world.turn.team == 1 and a.world.turn.state == "aiming" then
          if deaf then
            a.send("input", { kind = "move", direction = a.world.tick % 60 < 30 and 1 or -1 })
          else
            a.send("skip", {})
          end
        end
        if p.result then
          break
        end
      end
      assert.is_number(restored_at)
      assert.is_true(missed > 0, "the deaf window carried no input")
      assert.are.equal(1, p.restored)
      assert.are.equal(0, p.divergences)
      assert.is_table(p.result)
      assert.are.same({ world.checksum(a.world) }, { world.checksum(p.world) })
    end
  )

  it(
    "🎞️ refuses a snapshot whose tick is not its state's, and banks no time across a restore",
    function()
      local a, p = session({ teams = 2, cats_per_team = 1 })
      for _ = 1, 100 do
        pump(a, p)
        p.advance(FRAME)
      end
      local odd = world.snapshot(a.world)
      p.receive({ name = "snapshot", data = { tick = odd.tick + 2, state = odd } })
      assert.are.equal(1, p.rejected)
      a.send("snapshot_request", {})
      local snap
      for _, m in ipairs(a.poll()) do
        if m.name == "snapshot" then
          snap = m
        end
      end
      while p.world.tick < p.confirmed do
        p.advance(FRAME)
      end
      p.advance(1 / 30)
      p.receive(snap)
      local tick = p.world.tick
      p.receive({ name = "ticks", data = { to = tick + 2, inputs = {} } })
      p.advance(0)
      assert.are.equal(tick, p.world.tick)
    end
  )

  it("🎞️ asks for the tick of the first divergence, not of a later one", function()
    local p = silent_start()
    ticks_to(p, 0, 60)
    p.receive({ name = "checksum", data = { tick = 30, sum = { 1, 2 } } })
    p.receive({ name = "checksum", data = { tick = 60, sum = { 3, 4 } } })
    for _ = 1, 80 do
      p.advance(TICK)
    end
    assert.are.equal(2, p.divergences)
    assert.are.equal(30, p.resync)
  end)

  it(
    "🎞️ a snapshot catches up a client that has lost ticks, and play goes on from it",
    function()
      local a, p = session({ teams = 2, cats_per_team = 1 })
      for _ = 1, 200 do
        pump(a, p)
        p.advance(FRAME)
      end
      local before = p.world
      for _ = 1, 150 do
        a.update(FRAME)
        a.poll()
      end
      a.send("snapshot_request", {})
      local snap
      for _, m in ipairs(a.poll()) do
        if m.name == "snapshot" then
          snap = m
        end
      end
      p.receive(snap)
      assert.are_not.equal(before, p.world)
      assert.are.equal(snap.data.tick, p.world.tick)
      assert.are.equal(snap.data.tick, p.confirmed)
      assert.are.same({ world.checksum(a.world) }, { world.checksum(p.world) })
      for _ = 1, 300 do
        pump(a, p)
        p.advance(FRAME)
      end
      for _ = 1, 10 do
        p.advance(FRAME)
      end
      assert.are.equal(p.confirmed, p.world.tick)
      assert.is_true(a.world.tick - p.world.tick <= 1)
      assert.are.equal(0, p.divergences)
      assert.is_true(p.checked >= 8, p.checked .. " checksums compared after the snapshot")
    end
  )

  it("🎞️ refuses a snapshot that does not restore, and keeps its world", function()
    local a, p = session({ teams = 2, cats_per_team = 1 })
    for _ = 1, 100 do
      pump(a, p)
      p.advance(FRAME)
    end
    local w = p.world
    local bad = world.snapshot(a.world)
    bad.cells = { 1, 2 }
    p.receive({ name = "snapshot", data = { tick = a.world.tick, state = bad } })
    assert.are.equal(w, p.world)
    assert.are.equal(1, p.rejected)
    assert.are.equal(0, p.restored)
  end)

  it("🎞️ asks to be set right after a divergence, until a snapshot does it", function()
    local p = silent_start()
    ticks_to(p, 0, 30)
    assert.is_nil(p.resync)
    p.receive({ name = "checksum", data = { tick = 30, sum = { 1, 2 } } })
    for _ = 1, 40 do
      p.advance(TICK)
    end
    assert.are.equal(30, p.resync)
    local fresh = LocalAuthority.new({
      seed = 77,
      settings = { teams = 2, cats_per_team = 1 },
      player = PLAYER,
    })
    fresh.start()
    fresh.poll()
    for _ = 1, 40 do
      fresh.update(TICK)
    end
    fresh.poll()
    fresh.send("snapshot_request", {})
    local snap = fresh.poll()[1]
    assert.are.equal("snapshot", snap.name)
    p.receive(snap)
    assert.is_nil(p.resync)
    assert.are.equal(1, p.restored)
  end)

  it("🎞️ hands the renderer the inputs of each step with its events", function()
    local a = LocalAuthority.new({
      seed = 70,
      settings = { teams = 2, cats_per_team = 1 },
      player = PLAYER,
    })
    local seen, sent = {}, false
    local p = playback.new({
      on_events = function(_, inputs)
        for _, input in ipairs(inputs or {}) do
          seen[#seen + 1] = input.kind
        end
      end,
    })
    a.start()
    for _ = 1, 3000 do
      a.update(FRAME)
      for _, m in ipairs(a.poll()) do
        p.receive(m)
      end
      p.advance(FRAME)
      if p.world.turn.team == 1 and a.world.turn.state == "aiming" and not sent then
        a.send("input", { kind = "move", direction = 1 })
        sent = true
      end
      if #seen > 0 then
        break
      end
    end
    assert.are.same({ "move" }, seen)
  end)
end)

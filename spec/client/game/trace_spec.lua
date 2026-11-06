local trace = require("game.trace")

local function feed(t, script)
  for _, s in ipairs(script) do
    if s.mood then
      trace.face(t, s.tick, s.cat, s.mood)
    else
      trace.step(t, s.tick, s.inputs, s.events or {}, s.active)
    end
  end
end

local function game(direction)
  local script = {}
  for tick = 1, 95 do
    local entry = { tick = tick, events = {}, active = { x = 2560 + tick, y = 51200 } }
    if tick == 10 then
      entry.inputs = { { team = 1, kind = "move", direction = direction } }
    elseif tick == 20 then
      entry.inputs = { { team = 1, kind = "jump", direction = 1 } }
    elseif tick == 40 then
      entry.inputs = { { team = 1, kind = "fire", weapon = "bazooka", angle = 200, power = 70 } }
      entry.events = { { type = "fired", cat = 1, weapon = "bazooka" } }
    elseif tick == 60 then
      entry.events = {
        { type = "exploded", x = 40, y = 90, radius = 12 },
        { type = "damaged", cat = 2, amount = 31, cause = "explosion" },
        { type = "rebounded", cat = 2 },
      }
    elseif tick == 61 then
      script[#script + 1] = { mood = "angry", tick = 60, cat = 2 }
    elseif tick == 90 then
      entry.events = { { type = "died", cat = 2, cause = "hp" } }
    end
    script[#script + 1] = entry
  end
  return script
end

describe("🔎 the trace two players compare, in test mode (§10.5, D-03)", function()
  it("🔎 two clients fed the same steps reach the same checkpoints", function()
    local a, b = trace.new(), trace.new()
    feed(a, game(-1))
    feed(b, game(-1))
    assert.are.same(
      { 30, 60, 90 },
      { a.checkpoints[1].tick, a.checkpoints[2].tick, a.checkpoints[3].tick }
    )
    assert.are.same(a.checkpoints, b.checkpoints)
  end)

  it("🔎 one different input changes every checkpoint from its tick on, not before", function()
    local a, b = trace.new(), trace.new()
    feed(a, game(-1))
    feed(b, game(1))
    assert.are_not.same(a.checkpoints[1], b.checkpoints[1])
    local c, d = trace.new(), trace.new()
    local late = game(-1)
    feed(c, late)
    late[50].events = { { type = "landed", cat = 1 } }
    feed(d, late)
    assert.are.same(c.checkpoints[1], d.checkpoints[1])
    assert.are_not.same(c.checkpoints[2], d.checkpoints[2])
    assert.are_not.same(c.checkpoints[3], d.checkpoints[3])
  end)

  it("🔎 a face, a position or an event field counts in the digest", function()
    local base = trace.new()
    feed(base, game(-1))
    local without_face = game(-1)
    table.remove(without_face, 61)
    local moved = game(-1)
    moved[70].active = { x = 1, y = 2 }
    local weaker = game(-1)
    weaker[60].events[2].amount = 30
    for _, script in ipairs({ without_face, moved, weaker }) do
      local t = trace.new()
      feed(t, script)
      assert.are_not.same(base.checkpoints[3], t.checkpoints[3])
    end
  end)

  it(
    "🔎 counts what the game showed: walks, jumps, shots by weapon, damage by cause, faces, deaths",
    function()
      local t = trace.new()
      feed(t, game(-1))
      assert.are.same({
        walk = 1,
        jump = 1,
        ["fire:bazooka"] = 1,
        fired = 1,
        exploded = 1,
        ["damaged:explosion"] = 1,
        rebounded = 1,
        ["face:angry"] = 1,
        died = 1,
      }, t.counts)
    end
  )

  it("🔎 keeps only its last checkpoints", function()
    local t = trace.new()
    for tick = 1, (trace.KEEP + 5) * trace.EVERY do
      trace.step(t, tick, nil, {}, nil)
    end
    assert.are.equal(trace.KEEP, #t.checkpoints)
    assert.are.equal((trace.KEEP + 5) * trace.EVERY, t.checkpoints[trace.KEEP].tick)
  end)

  it("🔎 a name counts in the digest: an event's type, a weapon, a face", function()
    local base = trace.new()
    feed(base, game(-1))
    local other_type = game(-1)
    other_type[60].events[3] = { type = "landed", cat = 2 }
    local other_weapon = game(-1)
    other_weapon[40].inputs[1].weapon = "grenade"
    local other_face = game(-1)
    other_face[61].mood = "scared"
    for _, script in ipairs({ other_type, other_weapon, other_face }) do
      local t = trace.new()
      feed(t, script)
      assert.are_not.same(base.checkpoints[3], t.checkpoints[3])
    end
  end)

  it("🔎 checks the tick the game ends on, whatever its tick", function()
    local t = trace.new()
    trace.step(t, 41, nil, { { type = "game_ended", winner = 1 } }, nil)
    assert.are.same(41, t.checkpoints[1].tick)
  end)

  it(
    "🔎 a quake counts in the digest: its number, and each crack's column, width and top",
    function()
      local function quaked(change)
        local events = {
          { type = "quaked", n = 2 },
          { type = "cracked", x = 140, width = 6, top = 96 },
          { type = "shook", n = 2 },
        }
        change(events)
        local t = trace.new()
        trace.step(t, 30, {}, events, nil)
        return t.checkpoints[1].sum, t.counts
      end
      local base, counts = quaked(function() end)
      assert.are.same({ quaked = 1, cracked = 1, shook = 1 }, counts)
      for _, change in ipairs({
        function(e)
          e[1].n = 3
        end,
        function(e)
          e[2].x = 141
        end,
        function(e)
          e[2].width = 8
        end,
        function(e)
          e[2].top = 95
        end,
        function(e)
          e[3].n = 1
        end,
      }) do
        assert.are_not.equal(base, (quaked(change)))
      end
    end
  )
end)

local fake = require("spec.support.nakama")
local protocol = require("shared.protocol")
local room_support = require("spec.support.room")
local rules = require("shared.sim.rules")

local OPS = protocol.OPS

describe("🚫 the message guard (D-14, §6.8)", function()
  local nk, room, host

  before_each(function()
    nk = fake.install()
    room = room_support.open(nk)
    host = room_support.arrive(nk, room, "host", "Host")
  end)

  local function refusals(presence)
    local codes = {}
    for _, msg in ipairs(room.received(OPS.refused, presence)) do
      codes[#codes + 1] = msg.code
    end
    return codes
  end

  it("🚫 refuses to its sender a message that is not a JSON object", function()
    room.loop({
      fake.message(host, OPS.lobby_settings, "{not json"),
      fake.message(host, OPS.lobby_settings, "[1,2]"),
      fake.message(host, OPS.lobby_settings, '"text"'),
    })
    assert.are.same({ "malformed", "malformed", "malformed" }, refusals(host))
  end)

  it("🚫 refuses a message over 1 KiB before reading it", function()
    local big = '{"teams":3,"pad":"' .. string.rep("x", rules.MESSAGE_MAX_BYTES) .. '"}'
    room.loop({ fake.message(host, OPS.lobby_settings, big) })
    assert.are.same({ "too_large" }, refusals(host))
    assert.are.equal(4, room.state().settings.teams)
  end)

  it("🚫 refuses an unknown opcode and a game message in the lobby", function()
    room.loop({ fake.message(host, 99, {}), fake.message(host, OPS.fire, {}) })
    assert.are.same({ "unknown_op", "wrong_phase" }, refusals(host))
  end)

  it("🚫 admits 20 messages a second, drops the rest, answers once, and warns", function()
    local burst = {}
    for i = 1, rules.MESSAGES_PER_SECOND + 5 do
      burst[i] = fake.message(host, OPS.lobby_settings, { teams = 2 + (i % 2) })
    end
    local before = #room.received(OPS.lobby_state)
    room.loop(burst)
    assert.are.equal(before + rules.MESSAGES_PER_SECOND, #room.received(OPS.lobby_state))
    assert.are.same({ "rate_limited" }, refusals(host))
    assert.are.equal(1, #nk.logged("🚫 rate limited"))
    assert.are.equal("warn", nk.logged("🚫 rate limited")[1].level)
    for _ = 1, rules.TICKS_PER_SECOND - 1 do
      room.loop()
    end
    room.loop({ fake.message(host, OPS.lobby_settings, { teams = 5 }) })
    assert.are.equal(5, room.state().settings.teams)
  end)

  it("🚫 never admits more than 20 messages in any second, across a window edge", function()
    local function burst(n)
      local list = {}
      for i = 1, n do
        list[i] = fake.message(host, OPS.lobby_settings, { teams = 2 + (i % 2) })
      end
      return list
    end
    for _ = 1, rules.TICKS_PER_SECOND - 2 do
      room.loop()
    end
    local before = #room.received(OPS.lobby_state)
    room.loop(burst(rules.MESSAGES_PER_SECOND))
    room.loop(burst(rules.MESSAGES_PER_SECOND))
    room.loop(burst(rules.MESSAGES_PER_SECOND))
    assert.are.equal(before + rules.MESSAGES_PER_SECOND, #room.received(OPS.lobby_state))
  end)

  it("🚫 answers a sustained flood once a second, not once per admitted message", function()
    for _ = 1, 3 * rules.TICKS_PER_SECOND do
      local flood = {}
      for i = 1, 4 do
        flood[i] = fake.message(host, OPS.lobby_settings, { teams = 2 + (i % 2) })
      end
      room.loop(flood)
    end
    local codes = refusals(host)
    assert.are.equal(3, #codes)
    assert.are.equal(3, #nk.logged("🚫 rate limited"))
  end)

  it("🚫 counts oversized messages against the rate too", function()
    local big = '{"pad":"' .. string.rep("x", rules.MESSAGE_MAX_BYTES) .. '"}'
    local flood = {}
    for i = 1, rules.MESSAGES_PER_SECOND + 10 do
      flood[i] = fake.message(host, OPS.lobby_settings, big)
    end
    room.loop(flood)
    local codes = refusals(host)
    assert.are.equal(rules.MESSAGES_PER_SECOND + 1, #codes)
    assert.are.equal("rate_limited", codes[#codes])
  end)

  it("🚫 forgets a presence that left, even if its last message comes after", function()
    local guest = room_support.arrive(nk, room, "g1", "Guest")
    room.leave(guest)
    room.loop({ fake.message(guest, OPS.lobby_settings, { teams = 2 }) })
    assert.are.equal(0, #room.received(OPS.refused, guest))
    assert.is_nil(room.state().guard.presences[guest.session_id])
    assert.are.equal(4, room.state().settings.teams)
  end)

  it("🚫 counts refusals per code and presence, and logs the totals when it leaves", function()
    local guest = room_support.arrive(nk, room, "g1", "Guest")
    room.loop({
      fake.message(guest, OPS.lobby_settings, { teams = 2 }),
      fake.message(guest, OPS.lobby_settings, { teams = 3 }),
      fake.message(guest, 99, {}),
      fake.message(host, 99, {}),
    })
    assert.are.equal(4, #nk.logged("🚫 refused"))
    assert.are.equal("debug", nk.logged("🚫 refused")[1].level)
    room.leave(guest)
    local totals = nk.logged("🚫 refusals")
    assert.are.equal(1, #totals)
    assert.are.equal("info", totals[1].level)
    assert.truthy(totals[1].message:find("player=Guest", 1, true))
    assert.truthy(totals[1].message:find("not_host=2", 1, true))
    assert.truthy(totals[1].message:find("unknown_op=1", 1, true))
  end)

  it("🚫 never logs the content of a refused message", function()
    local guest = room_support.arrive(nk, room, "g1", "Guest")
    room.loop({
      fake.message(guest, OPS.lobby_settings, { map = "SECRET-MARKER" }),
      fake.message(host, OPS.lobby_settings, { map = "SECRET-MARKER" }),
      fake.message(host, OPS.lobby_settings, "{SECRET-MARKER"),
    })
    room.leave(guest)
    assert.are.equal(0, #nk.logged("SECRET%-MARKER"))
    assert.are.same({ "invalid_map", "malformed" }, refusals(host))
  end)
end)

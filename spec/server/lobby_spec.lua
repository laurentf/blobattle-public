local fake = require("spec.support.nakama")
local protocol = require("shared.protocol")
local room_support = require("spec.support.room")

local OPS = protocol.OPS
local last = room_support.last

describe("🏠 the lobby (§6.3, D-08)", function()
  local nk, room, host

  before_each(function()
    nk = fake.install()
    room = room_support.open(nk)
    host = room_support.arrive(nk, room, "host", "Host")
  end)

  it("🚫 a guest who sends lobby_settings receives refused", function()
    local guest = room_support.arrive(nk, room, "g1", "Guest")
    room.loop({ fake.message(guest, OPS.lobby_settings, { teams = 2 }) })
    assert.are.same({ code = "not_host" }, last(room, OPS.refused, guest))
    assert.is_nil(last(room, OPS.refused, host))
    assert.are.equal(4, room.state().settings.teams)
  end)

  it("🏠 each arriving human takes the first open seat, and everyone sees it", function()
    room_support.arrive(nk, room, "g1", "Guest")
    local seats = last(room, OPS.lobby_state).seats
    assert.are.same({ kind = "open", user = "host", name = "Host" }, seats[1])
    assert.are.same({ kind = "open", user = "g1", name = "Guest" }, seats[2])
    assert.are.same({ kind = "open" }, seats[3])
    assert.are.equal(4, #seats)
    local state = last(room, OPS.lobby_state)
    assert.are.equal("host", state.host)
    assert.are.equal(room.state().code, state.code)
    assert.are.equal(0, state.seed)
    assert.are.equal(4, state.settings.teams)
  end)

  it(
    "🏠 a seat shows the team its human deposited, and loses it when they leave (§6.1)",
    function()
      local identity = require("server.identity")
      local members = { "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot" }
      identity.team_set(
        { user_id = "g1" },
        nk.json_encode({ name = "Gel Gang", members = members })
      )
      local guest = room_support.arrive(nk, room, "g1", "Guest")
      local seats = last(room, OPS.lobby_state).seats
      assert.are.same({ kind = "open", user = "g1", name = "Guest", team = "Gel Gang" }, seats[2])
      assert.are.same({ kind = "open", user = "host", name = "Host" }, seats[1])
      room.leave(guest)
      assert.are.same({ kind = "open" }, last(room, OPS.lobby_state).seats[2])
    end
  )

  it("🏠 a human without a valid nickname cannot join", function()
    nk.add_user("anon", "")
    local ok, reason = room.join(fake.presence("anon"))
    assert.is_false(ok)
    assert.are.equal("nickname_required", reason)
  end)

  it("🏠 a Bot seat is never taken, and a room without an open seat is full", function()
    room.loop({
      fake.message(host, OPS.lobby_settings, { teams = 3 }),
      fake.message(host, OPS.lobby_slot, { seat = 2, kind = "bot" }),
    })
    room_support.arrive(nk, room, "g1", "Guest")
    local seats = last(room, OPS.lobby_state).seats
    assert.are.same({ kind = "bot" }, seats[2])
    assert.are.equal("g1", seats[3].user)
    nk.add_user("g2", "Late")
    local ok, reason = room.join(fake.presence("g2"))
    assert.is_false(ok)
    assert.are.equal("room_full", reason)
  end)

  it("🏠 the host changes the settings and the seed, and everyone sees them", function()
    room.loop({
      fake.message(host, OPS.lobby_settings, { teams = 6, map = "volcano", seed = 42 }),
    })
    local state = last(room, OPS.lobby_state)
    assert.are.equal(6, #state.seats)
    assert.are.equal("volcano", state.settings.map)
    assert.are.equal(42, state.seed)
    room.loop({ fake.message(host, OPS.lobby_settings, { seed = 0, teams = 2 }) })
    state = last(room, OPS.lobby_state)
    assert.are.equal(0, state.seed)
    assert.are.equal(2, #state.seats)
    assert.are.equal("volcano", state.settings.map)
  end)

  it("🏠 an out-of-bounds setting is refused with the sim's reason", function()
    room.loop({ fake.message(host, OPS.lobby_settings, { teams = 9, map = "volcano" }) })
    assert.are.same({ code = "invalid_teams" }, last(room, OPS.refused, host))
    assert.are.equal(4, room.state().settings.teams)
    assert.are.equal("random", room.state().settings.map)
  end)

  it("🏠 the host switches seats between Open and Bot, never one a human holds", function()
    room_support.arrive(nk, room, "g1", "Guest")
    room.loop({
      fake.message(host, OPS.lobby_slot, { seat = 4, kind = "bot" }),
      fake.message(host, OPS.lobby_slot, { seat = 2, kind = "bot" }),
      fake.message(host, OPS.lobby_slot, { seat = 7, kind = "bot" }),
    })
    local seats = last(room, OPS.lobby_state).seats
    assert.are.equal("bot", seats[4].kind)
    assert.are.same({ kind = "open", user = "g1", name = "Guest" }, seats[2])
    local codes = {}
    for _, msg in ipairs(room.received(OPS.refused, host)) do
      codes[#codes + 1] = msg.code
    end
    assert.are.same({ "seat_taken", "invalid_seat" }, codes)
    room.loop({ fake.message(host, OPS.lobby_slot, { seat = 4, kind = "open" }) })
    assert.are.equal("open", last(room, OPS.lobby_state).seats[4].kind)
  end)

  it("🏠 the number of teams never drops under a seat a human holds", function()
    room.loop({ fake.message(host, OPS.lobby_slot, { seat = 2, kind = "bot" }) })
    room.loop({ fake.message(host, OPS.lobby_slot, { seat = 3, kind = "bot" }) })
    room_support.arrive(nk, room, "g1", "Guest")
    room.loop({ fake.message(host, OPS.lobby_settings, { teams = 3 }) })
    assert.are.same({ code = "seat_taken" }, last(room, OPS.refused, host))
    assert.are.equal(4, room.state().settings.teams)
  end)

  it("🏠 a human who leaves frees their seat", function()
    local guest = room_support.arrive(nk, room, "g1", "Guest")
    room.leave(guest)
    assert.are.same({ kind = "open" }, last(room, OPS.lobby_state).seats[2])
    room_support.arrive(nk, room, "g2", "Other")
    assert.are.equal("g2", last(room, OPS.lobby_state).seats[2].user)
  end)

  it("🏠 when the host leaves, the earliest arrived human becomes host", function()
    local first = room_support.arrive(nk, room, "g1", "First")
    local second = room_support.arrive(nk, room, "g2", "Second")
    room.leave(host)
    assert.are.equal("g1", last(room, OPS.lobby_state).host)
    room.loop({
      fake.message(second, OPS.lobby_settings, { teams = 5 }),
      fake.message(first, OPS.lobby_settings, { teams = 6 }),
    })
    assert.are.same({ code = "not_host" }, last(room, OPS.refused, second))
    assert.are.equal(6, room.state().settings.teams)
    assert.is_true(room.join(host))
    assert.are.equal("g1", last(room, OPS.lobby_state).host)
  end)

  it("🏠 a join attempt that never completes holds no seat", function()
    nk.add_user("ghost", "Ghost")
    local m = nk.matches[nk.order[1]]
    local accepted = m.handler.match_join_attempt(
      { match_id = m.match_id },
      room.dispatcher,
      room.tick,
      m.state,
      fake.presence("ghost"),
      {}
    )
    assert.is_not_nil(accepted)
    room.loop({ fake.message(host, OPS.lobby_slot, { seat = 2, kind = "bot" }) })
    assert.are.equal("bot", last(room, OPS.lobby_state).seats[2].kind)
    assert.is_nil(room.state().players.ghost)
  end)

  it("🏠 a reconnection whose old session leaves late keeps the human seated and host", function()
    local again = fake.presence("host", "s-host-2")
    local m = nk.matches[nk.order[1]]
    local ctx = { match_id = m.match_id }
    local state, accepted =
      m.handler.match_join_attempt(ctx, room.dispatcher, 0, m.state, again, {})
    assert.is_true(accepted)
    m.state = m.handler.match_leave(ctx, room.dispatcher, 0, state, { host })
    m.state = m.handler.match_join(ctx, room.dispatcher, 0, m.state, { again })
    local lobby = last(room, OPS.lobby_state)
    assert.are.equal("host", lobby.host)
    assert.are.equal("host", lobby.seats[1].user)
    room.loop({ fake.message(again, OPS.lobby_settings, { teams = 3 }) })
    assert.are.equal(3, room.state().settings.teams)
  end)

  it("🏠 the first human to arrive hosts a room whose creator never came", function()
    nk.add_user("creator", "Creator")
    local other = room_support.open(nk, {}, "creator")
    local guest = room_support.arrive(nk, other, "g1", "Guest")
    assert.are.equal("g1", last(other, OPS.lobby_state).host)
    other.loop({ fake.message(guest, OPS.lobby_settings, { teams = 3 }) })
    assert.are.equal(3, other.state().settings.teams)
  end)

  it("🏠 a room emptied then joined again gets a host", function()
    room.leave(host)
    assert.is_nil(last(room, OPS.lobby_state).host)
    room_support.arrive(nk, room, "g1", "Guest")
    assert.are.equal("g1", last(room, OPS.lobby_state).host)
  end)
  it("🏠 two humans admitted for the last seat: the second to arrive is kicked", function()
    room.loop({ fake.message(host, OPS.lobby_settings, { teams = 2 }) })
    nk.add_user("g1", "First")
    nk.add_user("g2", "Second")
    local first, second = fake.presence("g1"), fake.presence("g2")
    local m = nk.matches[nk.order[1]]
    local ctx = { match_id = m.match_id }
    local _, ok1 = m.handler.match_join_attempt(ctx, room.dispatcher, 0, m.state, first, {})
    local _, ok2 = m.handler.match_join_attempt(ctx, room.dispatcher, 0, m.state, second, {})
    assert.is_true(ok1 and ok2)
    m.state = m.handler.match_join(ctx, room.dispatcher, 0, m.state, { first, second })
    assert.are.same({ second }, room.kicked)
    assert.are.equal("g1", last(room, OPS.lobby_state).seats[2].user)
    assert.is_nil(room.state().presences[second.session_id])
    assert.is_nil(room.state().players.g2)
  end)
end)

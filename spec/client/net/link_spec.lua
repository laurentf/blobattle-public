local fake = require("spec.support.nakama_client")
local json = require("dkjson")
local link = require("net.link")
local protocol = require("shared.protocol")

local OPS = protocol.OPS

local PROFILE = {
  nickname = "Mia",
  team_name = "Blue Paws",
  members = { "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot" },
  device = "0b5e2f3c-7d41-4c8e-9a0f-3f2d1e6b7a90",
}

local function open(server, profile)
  return link.new({
    nakama = server.nakama,
    engine = { name = "engine" },
    endpoint = { host = "192.168.0.21", port = 7550, ssl = false },
    server_key = "secret-key",
    json = { encode = json.encode, decode = json.decode },
    after = server.after,
    clock = server.clock,
    disconnect = server.disconnect,
    profile = profile or PROFILE,
  })
end

local function names(list)
  local out = {}
  for i, m in ipairs(list) do
    out[i] = m.name
  end
  return out
end

describe("🌐 the link to a room (§6.1, §6.2, §7.1)", function()
  local server

  before_each(function()
    server = fake.new()
  end)

  it(
    "🌐 creates a room: device, nickname and team on the account, then its socket and match",
    function()
      local l = open(server)
      link.enter(l, { settings = { teams = 3, map = "forest" } })
      assert.are.equal("joined", l.status)
      assert.are.equal("ABCDE", l.code)
      assert.are.equal("match-ABCDE", l.match_id)
      assert.are.equal("user-" .. PROFILE.device, l.user_id)
      local config = server.called("create_client")[1]
      assert.are.equal("192.168.0.21", config.host)
      assert.are.equal(7550, config.port)
      assert.is_false(config.use_ssl)
      assert.are.equal("secret-key", config.username)
      assert.are.equal("", config.password)
      assert.are.same(
        { id = PROFILE.device, create = true },
        server.called("authenticate_device")[1]
      )
      assert.are.same({ "Mia" }, server.called("update_account"))
      local rpcs = server.called("rpc")
      assert.are.same(
        { id = "team_set", payload = { name = "Blue Paws", members = PROFILE.members } },
        rpcs[1]
      )
      assert.are.same(
        { id = "room_create", payload = { settings = { teams = 3, map = "forest" } } },
        rpcs[2]
      )
      assert.are.same({ "match-ABCDE" }, server.called("match_join"))
      assert.is_number(l.measures.joined_s)
    end
  )

  it("🌐 joins a room by its code, waiting while Nakama indexes a new room's label", function()
    link.enter(open(server), { settings = {} })
    server.find_misses = 2
    local l = open(server, {
      nickname = "Zed",
      team_name = "Gel Gang",
      members = PROFILE.members,
      device = "1c6f3a4d-8e52-4d9f-8b1a-4a3e2f7c8b01",
    })
    link.enter(l, { code = "ABCDE" })
    assert.are.equal("connecting", l.status)
    server.advance(link.FIND_WAIT)
    assert.are.equal("connecting", l.status)
    server.advance(link.FIND_WAIT)
    assert.are.equal("joined", l.status)
    assert.are.equal("ABCDE", l.code)
    assert.are.same({ "match-ABCDE", "match-ABCDE" }, server.called("match_join"))
  end)

  it("🚫 gives the reason when it cannot enter", function()
    local l = open(server)
    link.enter(l, { code = "ZZZZZ" })
    for _ = 1, link.FIND_ATTEMPTS do
      server.advance(link.FIND_WAIT)
    end
    assert.are.equal("failed", l.status)
    assert.are.equal("room_not_found", l.reason)

    link.enter(open(server), { settings = {} })
    server.join_error = "room_full"
    l = open(server)
    link.enter(l, { code = "ABCDE" })
    assert.are.same({ "failed", "room_full" }, { l.status, l.reason })
    assert.is_true(server.socket().closed)

    server.join_error = nil
    server.auth_error = true
    l = open(server)
    link.enter(l, { settings = {} })
    assert.are.same({ "failed", "offline" }, { l.status, l.reason })

    server.auth_error = false
    server.connect_error = true
    l = open(server)
    link.enter(l, { settings = {} })
    assert.are.same({ "failed", "offline" }, { l.status, l.reason })
  end)

  it("🌐 hands lobby messages to the Salon and game messages to the game, in order", function()
    local l = open(server)
    link.enter(l, { settings = {} })
    server.push(OPS.lobby_state, { code = "ABCDE", host = l.user_id, seats = {} })
    server.push(OPS.refused, { code = "not_host" })
    assert.are.equal("lobby", l.phase)
    assert.are.equal("ABCDE", l.lobby.code)
    assert.are.same({ "lobby_state", "refused" }, names(link.lobby_messages(l)))
    assert.are.same({}, link.lobby_messages(l))
    server.push(OPS.game_start, { seed = 7, settings = {}, roster = {} })
    server.push(OPS.ticks, { to = 2, inputs = {} })
    server.push(OPS.refused, { code = "not_now" })
    server.push(OPS.checksum, { tick = 30, sum = { 1, 2 } })
    assert.are.equal("playing", l.phase)
    assert.are.equal(1, l.game)
    local game = link.game_messages(l)
    assert.are.same({ "game_start", "ticks", "refused", "checksum" }, names(game))
    assert.are.same({ to = 2, inputs = {} }, game[2].data)
    server.push(OPS.game_end, { winner = 1, stats = {} })
    assert.are.equal("ended", l.phase)
    assert.are.same({ "game_end" }, names(link.game_messages(l)))
    server.push(99, {})
    server.push(OPS.ticks, "not json")
    assert.are.same({}, link.game_messages(l))
  end)

  it("🌐 a new game_start starts a new game and forgets what was left of the last one", function()
    local l = open(server)
    link.enter(l, { settings = {} })
    server.push(OPS.game_start, { seed = 7, settings = {}, roster = {} })
    server.push(OPS.ticks, { to = 2, inputs = {} })
    server.push(OPS.lobby_state, { code = "ABCDE", seats = {} })
    server.push(OPS.game_start, { seed = 7, settings = {}, roster = {} })
    assert.are.equal(2, l.game)
    assert.are.same({ "game_start" }, names(link.game_messages(l)))
  end)

  it("🌐 sends a client message as JSON under its op code, only while in the room", function()
    local l = open(server)
    assert.is_false(link.send(l, "input", { kind = "move", direction = 1 }))
    link.enter(l, { settings = {} })
    assert.is_true(link.send(l, "input", { kind = "move", direction = 1 }))
    assert.is_true(link.send(l, "start", {}))
    assert.are.same({
      { match_id = "match-ABCDE", op = OPS.input, data = { kind = "move", direction = 1 } },
      { match_id = "match-ABCDE", op = OPS.start, data = {} },
    }, server.sent)
    assert.is_false(link.send(l, "lobby_state", {}))
    assert.is_false(link.send(l, "nothing", {}))
  end)

  it("🔁 comes back into the same match after losing its socket (§6.7)", function()
    local l = open(server)
    link.enter(l, { settings = {} })
    server.push(OPS.game_start, { seed = 7, settings = {}, roster = {} })
    link.game_messages(l)
    local first = server.socket()
    server.drop(first)
    assert.are.equal("reconnecting", l.status)
    assert.is_false(link.send(l, "skip", {}))
    link.update(l)
    assert.are.equal("reconnecting", l.status)
    server.advance(link.RETRY_SECONDS)
    link.update(l)
    assert.are.equal("joined", l.status)
    assert.are_not.equal(first, server.socket())
    assert.are.same({ "match-ABCDE", "match-ABCDE" }, server.called("match_join"))
    assert.are.equal(1, l.measures.rejoins)
    server.push(OPS.game_start, { seed = 7, settings = {}, roster = {} })
    server.push(OPS.snapshot, { tick = 90, state = { version = 6 } })
    server.push(OPS.ticks, { to = 92, inputs = {} }, first)
    assert.are.equal(1, l.game)
    assert.are.same({ "snapshot" }, names(link.game_messages(l)))
    assert.is_true(l.measures.snapshot_bytes > 20)
  end)

  it(
    "🔁 keeps trying while the server cannot be reached, and gives up on a room that is gone",
    function()
      local l = open(server)
      link.enter(l, { settings = {} })
      server.drop()
      server.connect_error = true
      server.advance(link.RETRY_SECONDS)
      link.update(l)
      assert.are.equal("reconnecting", l.status)
      server.connect_error = false
      server.join_error = "room_not_found"
      server.advance(link.RETRY_SECONDS)
      link.update(l)
      assert.are.same({ "failed", "room_not_found" }, { l.status, l.reason })
    end
  )

  it("🌐 leaves the match and closes its socket", function()
    local l = open(server)
    link.enter(l, { settings = {} })
    local socket = server.socket()
    link.leave(l)
    assert.are.equal("closed", l.status)
    assert.are.same({ "match-ABCDE" }, server.called("match_leave"))
    assert.is_true(socket.closed)
    socket.handlers.disconnect()
    assert.are.equal("closed", l.status)
  end)

  it(
    "📏 measures an input's round trip: sent, then seen for its team in a ticks message",
    function()
      local l = open(server)
      link.enter(l, { settings = {} })
      server.push(OPS.game_start, {
        seed = 7,
        settings = {},
        roster = { { team = 1, kind = "bot" }, { team = 2, kind = "human", user = l.user_id } },
      })
      assert.are.equal(2, l.team)
      server.now = 10
      link.send(l, "input", { kind = "move", direction = 1 })
      server.now = 10.02
      link.send(l, "input", { kind = "move", direction = 0 })
      server.now = 10.05
      server.push(OPS.ticks, {
        to = 40,
        inputs = { { at = 38, input = { team = 1, kind = "move", direction = 1 } } },
      })
      assert.is_nil(l.measures.rtt_ms)
      server.now = 10.08
      server.push(OPS.ticks, {
        to = 42,
        inputs = { { at = 40, input = { team = 2, kind = "move", direction = 1 } } },
      })
      assert.are.equal(80, math.floor(l.measures.rtt_ms + 0.5))
      assert.are.equal(1, l.measures.rtt_n)
      server.now = 11
      link.send(l, "input", { kind = "move", direction = -1 })
      server.now = 11.03
      server.push(OPS.ticks, {
        to = 44,
        inputs = { { at = 42, input = { team = 2, kind = "move", direction = -1 } } },
      })
      assert.are.equal(30, math.floor(l.measures.rtt_ms + 0.5))
      assert.are.equal(2, l.measures.rtt_n)
      assert.are.equal(55, math.floor(l.measures.rtt_avg_ms + 0.5))
      server.now = 20
      link.send(l, "input", { kind = "jump", direction = 1 })
      server.now = 20 + link.PROBE_SECONDS + 1
      link.send(l, "input", { kind = "climb", direction = -1 })
      server.now = server.now + 0.04
      server.push(OPS.ticks, {
        to = 46,
        inputs = { { at = 44, input = { team = 2, kind = "climb", direction = -1 } } },
      })
      assert.are.equal(40, math.floor(l.measures.rtt_ms + 0.5))
    end
  )

  it("🔁 Back while it looks for the room cancels it: nothing joins later", function()
    link.enter(open(server), { settings = {} })
    server.find_misses = 2
    local l = open(server)
    link.enter(l, { code = "ABCDE" })
    link.leave(l)
    for _ = 1, link.FIND_ATTEMPTS do
      server.advance(link.FIND_WAIT)
    end
    assert.are.equal("closed", l.status)
    assert.are.same({ "match-ABCDE" }, server.called("match_join"))
  end)

  it(
    "🔁 a join that never answers fails after the watchdog, and its late answer is ignored",
    function()
      local l = open(server)
      server.hold_join = true
      link.enter(l, { settings = {} })
      assert.are.equal("connecting", l.status)
      server.advance(link.WATCHDOG_SECONDS + 1)
      link.update(l)
      assert.are.same({ "failed", "offline" }, { l.status, l.reason })
      local socket = server.socket()
      server.release()
      assert.are.equal("failed", l.status)
      assert.is_true(socket.closed)
    end
  )

  it("🔁 a rejoin that never answers is dropped by the watchdog, then tried again", function()
    local l = open(server)
    link.enter(l, { settings = {} })
    server.advance(link.KICK_SECONDS + 1)
    server.drop()
    server.hold_join = true
    server.advance(link.RETRY_SECONDS)
    link.update(l)
    assert.are.equal(1, #server.held)
    server.advance(link.WATCHDOG_SECONDS + 1)
    link.update(l)
    assert.are.equal("reconnecting", l.status)
    server.hold_join = false
    link.update(l)
    assert.are.equal("joined", l.status)
    server.release()
    assert.are.equal("joined", l.status)
    assert.are.equal(1, l.measures.rejoins)
  end)

  it("🔁 leaving during a rejoin ignores its late answer", function()
    local l = open(server)
    link.enter(l, { settings = {} })
    server.advance(link.KICK_SECONDS + 1)
    server.drop()
    server.hold_join = true
    server.advance(link.RETRY_SECONDS)
    link.update(l)
    link.leave(l)
    local socket = server.socket()
    server.release()
    assert.are.equal("closed", l.status)
    assert.is_true(socket.closed)
  end)

  it("🔁 stops coming back when another window keeps taking the account's socket", function()
    local l = open(server)
    link.enter(l, { settings = {} })
    for _ = 1, link.MAX_KICKS - 1 do
      server.drop()
      assert.are.equal("reconnecting", l.status)
      server.advance(link.RETRY_SECONDS)
      link.update(l)
      assert.are.equal("joined", l.status)
    end
    server.drop()
    assert.are.same({ "failed", "elsewhere" }, { l.status, l.reason })
    local slow = open(server)
    link.enter(slow, { settings = {} })
    for _ = 1, link.MAX_KICKS + 1 do
      server.advance(link.KICK_SECONDS + 1)
      server.drop()
      server.advance(link.RETRY_SECONDS)
      link.update(slow)
    end
    assert.are.equal("joined", slow.status)
  end)

  it("🔁 back into a room that has started a new game, it is a new game", function()
    local l = open(server)
    link.enter(l, { settings = {} })
    server.push(OPS.game_start, { seed = 7, settings = {}, roster = {} })
    server.advance(link.KICK_SECONDS + 1)
    server.drop()
    server.advance(link.RETRY_SECONDS)
    link.update(l)
    server.push(OPS.game_start, { seed = 8, settings = {}, roster = {} })
    assert.are.equal(2, l.game)
  end)

  it("🏠 knows who hosts, from the lobby and from the end of a game", function()
    local l = open(server)
    link.enter(l, { settings = {} })
    server.push(OPS.lobby_state, { code = "ABCDE", host = "someone-else", seats = {} })
    assert.is_false(link.hosting(l))
    server.push(OPS.game_start, { seed = 7, settings = {}, roster = {} })
    server.push(OPS.game_end, { winner = 1, stats = {}, host = l.user_id })
    assert.is_true(link.hosting(l))
  end)

  it(
    "🔁 a message sent after the network dropped, before the socket says so, is lost quietly",
    function()
      local l = open(server)
      link.enter(l, { settings = {} })
      server.cut()
      assert.is_false(link.send(l, "input", { kind = "move", direction = 1 }))
      server.drop()
      assert.are.equal("reconnecting", l.status)
    end
  )

  it("🔁 the game_start that comes back before the join's answer is not a new game", function()
    local l = open(server)
    link.enter(l, { settings = {} })
    server.push(OPS.game_start, { seed = 7, settings = {}, roster = {} })
    link.game_messages(l)
    server.advance(link.KICK_SECONDS + 1)
    server.drop()
    server.hold_join = true
    server.advance(link.RETRY_SECONDS)
    link.update(l)
    server.push(OPS.game_start, { seed = 7, settings = {}, roster = {} })
    server.push(OPS.snapshot, { tick = 90, state = { version = 6 } })
    server.release()
    assert.are.equal("joined", l.status)
    assert.are.equal(1, l.game)
    assert.are.same({ "snapshot" }, names(link.game_messages(l)))
  end)
end)

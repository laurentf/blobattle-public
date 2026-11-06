local LocalAuthority = require("authority.local_authority")
local NakamaAuthority = require("authority.nakama_authority")
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

local function joined(server)
  local l = link.new({
    nakama = server.nakama,
    engine = {},
    endpoint = { host = "127.0.0.1", port = 7550, ssl = false },
    server_key = "k",
    json = { encode = json.encode, decode = json.decode },
    after = server.after,
    clock = server.clock,
    disconnect = server.disconnect,
    profile = PROFILE,
  })
  link.enter(l, { settings = {} })
  return l
end

local function interface(authority)
  local names = {}
  for name, value in pairs(authority) do
    if type(value) == "function" then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

local function names(list)
  local out = {}
  for i, m in ipairs(list) do
    out[i] = m.name
  end
  return out
end

describe("🌐 NakamaAuthority, the online side of the one seam (§7.1)", function()
  local server, l, a

  before_each(function()
    server = fake.new()
    l = joined(server)
    a = NakamaAuthority.new({ link = l })
  end)

  it("🌐 has exactly the interface of LocalAuthority", function()
    local offline = LocalAuthority.new({ seed = 7, settings = {}, player = PROFILE })
    assert.are.same(interface(offline), interface(a))
    assert.are.same({ "poll", "send", "start", "stop", "team", "update" }, interface(a))
  end)

  it("🌐 hands over the game messages of the room, a list valid until the next poll", function()
    local roster = {
      { team = 1, kind = "human", user = "someone-else" },
      { team = 2, kind = "human", user = l.user_id },
    }
    server.push(OPS.game_start, { seed = 9, settings = {}, roster = roster })
    server.push(OPS.ticks, { to = 2, inputs = {} })
    a.start()
    a.update(1 / 60)
    local first = a.poll()
    assert.are.same({ "game_start", "ticks" }, names(first))
    assert.are.equal(2, a.team())
    server.push(OPS.pilots, { bots = { 1 } })
    server.push(OPS.checksum, { tick = 30, sum = { 1, 2 } })
    assert.are.same({ "pilots", "checksum" }, names(a.poll()))
    assert.are.same({}, a.poll())
  end)

  it(
    "🌐 knows no team before the game starts, nor after it for a player not in the roster",
    function()
      assert.is_nil(a.team())
      server.push(OPS.game_start, {
        seed = 9,
        settings = {},
        roster = { { team = 1, kind = "bot" }, { team = 2, kind = "human", user = l.user_id } },
      })
      a.poll()
      assert.are.equal(2, a.team())
      server.push(OPS.lobby_state, { code = "ABCDE", seats = {} })
      server.push(
        OPS.game_start,
        { seed = 10, settings = {}, roster = { { team = 1, kind = "bot" } } }
      )
      a.poll()
      assert.is_nil(a.team())
    end
  )

  it(
    "🌐 sends what the controls send to the match, and refuses an unknown operation itself",
    function()
      a.send("input", { kind = "move", direction = -1 })
      a.send("fire", { weapon = "bazooka", angle = 200, power = 60 })
      a.send("snapshot_request", { tick = 30 })
      assert.are.same({ OPS.input, OPS.fire, OPS.snapshot_request }, {
        server.sent[1].op,
        server.sent[2].op,
        server.sent[3].op,
      })
      assert.are.same({ kind = "move", direction = -1 }, server.sent[1].data)
      a.send("game_start", {})
      a.send("teleport", {})
      local out = a.poll()
      assert.are.same({ "refused", "refused" }, names(out))
      assert.are.same({ code = "unknown_op" }, out[1].data)
      assert.are.equal(3, #server.sent)
    end
  )

  it("🌐 is silent once stopped", function()
    a.stop()
    server.push(OPS.ticks, { to = 2, inputs = {} })
    a.send("skip", {})
    assert.are.same({}, a.poll())
    assert.are.equal(0, #server.sent)
  end)
end)

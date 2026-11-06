local fake = require("spec.support.nakama")
local protocol = require("shared.protocol")
local rules = require("shared.sim.rules")

describe("🏠 room_create and room_find (§6.2)", function()
  local nk, rooms
  local host = { user_id = "u1", username = "u-u1", session_id = "s1" }

  before_each(function()
    nk = fake.install()
    rooms = require("server.rooms")
  end)

  local function create(settings)
    return nk.json_decode(rooms.create(host, nk.json_encode({ settings = settings or {} })))
  end

  it("🏠 an unknown code gives room_not_found", function()
    local message, code = fake.rpc_error(rooms.find, host, '{"code":"ZZZZZ"}')
    assert.are.equal("room_not_found", message)
    assert.are.equal(fake.CODES.NOT_FOUND, code)
  end)

  it("🏠 a malformed code gives room_not_found too", function()
    for _, payload in ipairs({
      '{"code":"ABCD"}',
      '{"code":"ABCDI"}',
      '{"code":12345}',
      "{}",
      "nope",
    }) do
      assert.are.equal("room_not_found", (fake.rpc_error(rooms.find, host, payload)), payload)
    end
  end)

  it("🏠 room_create returns a code and the match that carries it in its label", function()
    local out = create({ teams = 3 })
    assert.is_true(protocol.valid_code(out.code))
    local m = nk.matches[out.match_id]
    assert.are.same({ code = out.code, phase = "lobby" }, nk.json_decode(m.label))
    assert.are.equal("u1", m.state.host)
    assert.are.equal(3, m.state.settings.teams)
  end)

  it("🏠 room_find returns the match of a known code, written in any case", function()
    local out = create()
    local found = nk.json_decode(rooms.find(host, nk.json_encode({ code = out.code })))
    assert.are.equal(out.match_id, found.match_id)
    found = nk.json_decode(rooms.find(host, nk.json_encode({ code = out.code:lower() })))
    assert.are.equal(out.match_id, found.match_id)
  end)

  it("🏠 room_create draws again while the code is taken", function()
    local taken = "00010203-0400-4000-8000-000000000000"
    nk.uuids = { taken, taken, "0a0b0c0d-0e00-4000-8000-000000000000" }
    local first = create()
    local second = create()
    assert.are.equal("ABCDE", first.code)
    assert.are.equal("LMNPQ", second.code)
    assert.are.equal(0, #nk.uuids)
  end)

  it("🏠 room_create gives up after a bounded number of draws", function()
    local taken = "00010203-0400-4000-8000-000000000000"
    nk.uuids = { taken }
    assert.are.equal("ABCDE", create().code)
    for i = 1, rules.ROOM_CODE_ATTEMPTS do
      nk.uuids[i] = taken
    end
    local message, code = fake.rpc_error(rooms.create, host, "{}")
    assert.are.equal("room_code_unavailable", message)
    assert.are.equal(fake.CODES.UNAVAILABLE, code)
    assert.are.equal(1, #nk.order)
    assert.are.equal(0, #nk.uuids)
  end)

  it("🏠 room_create returns the sim's reason for an out-of-bounds setting", function()
    local message, code = fake.rpc_error(rooms.create, host, '{"settings":{"teams":9}}')
    assert.are.equal("invalid_teams", message)
    assert.are.equal(fake.CODES.INVALID_ARGUMENT, code)
    message = fake.rpc_error(rooms.create, host, '{"settings":{"map":"desert"}}')
    assert.are.equal("invalid_map", message)
    assert.are.equal(0, #nk.order)
  end)

  it("🏠 room_create reads only the lobby settings", function()
    local out = create({ wind_max = 0, cats_per_team = 2 })
    local settings = nk.matches[out.match_id].state.settings
    assert.are.equal(rules.SETTINGS.wind_max.default, settings.wind_max)
    assert.are.equal(2, settings.cats_per_team)
  end)

  it("🏠 room_create refuses a payload that is not a JSON object", function()
    for _, payload in ipairs({ "nope", "[1,2]", '"x"', '{"settings":3}', '{"settings":[4]}' }) do
      assert.are.equal("malformed", (fake.rpc_error(rooms.create, host, payload)), payload)
    end
  end)

  it("🚫 room_create refuses a payload over 1 KiB (D-14)", function()
    local payload = nk.json_encode({ settings = { teams = 2 }, pad = string.rep("x", 1100) })
    assert.are.equal("too_large", (fake.rpc_error(rooms.create, host, payload)))
  end)

  it("🏠 both calls refuse a caller without a session", function()
    for _, context in ipairs({ {}, { user_id = "" } }) do
      local message, code = fake.rpc_error(rooms.create, context, "{}")
      assert.are.equal("unauthenticated", message)
      assert.are.equal(fake.CODES.UNAUTHENTICATED, code)
      assert.are.equal("unauthenticated", (fake.rpc_error(rooms.find, context, '{"code":"ABCDE"}')))
    end
  end)
end)

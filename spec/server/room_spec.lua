local fake = require("spec.support.nakama")
local rules = require("shared.sim.rules")

describe("🏠 the room match (§6.3)", function()
  local nk, rooms

  before_each(function()
    nk = fake.install()
    rooms = require("server.rooms")
  end)

  local function new_room()
    nk.add_user("u1", "Host")
    local out = nk.json_decode(rooms.create({ user_id = "u1" }, "{}"))
    return fake.match(nk, out.match_id), out
  end

  it("🏠 ticks at 30 Hz and is labelled with its code and phase", function()
    local _, out = new_room()
    local m = nk.matches[out.match_id]
    assert.are.equal(rules.TICKS_PER_SECOND, m.rate)
    assert.are.same({ code = out.code, phase = "lobby" }, nk.json_decode(m.label))
  end)

  it("🏠 closes after 60 s without any human present", function()
    local room = new_room()
    local limit = rules.ROOM_EMPTY_SECONDS * rules.TICKS_PER_SECOND
    for _ = 1, limit - 1 do
      assert.is_true(room.loop())
    end
    assert.is_false(room.loop())
    assert.are.equal(1, #nk.logged("🏠 room closed"))
  end)

  it(
    "🏠 stays open while a human is present, and counts again once the last one leaves",
    function()
      local room = new_room()
      local host = fake.presence("u1")
      local limit = rules.ROOM_EMPTY_SECONDS * rules.TICKS_PER_SECOND
      for _ = 1, limit - 10 do
        assert.is_true(room.loop())
      end
      assert.is_true(room.join(host))
      for _ = 1, 2 * limit do
        assert.is_true(room.loop())
      end
      room.leave(host)
      for _ = 1, limit - 1 do
        assert.is_true(room.loop())
      end
      assert.is_false(room.loop())
    end
  )
end)

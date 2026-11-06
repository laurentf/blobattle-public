local room_view = require("ui.room_view")

local function lobby(fields)
  local out = {
    code = "ABCDE",
    host = "u-host",
    seed = 0,
    settings = {
      teams = 4,
      cats_per_team = 2,
      turn_seconds = 45,
      map = "random",
      bot_level = "medium",
    },
    seats = {
      { kind = "open", user = "u-host", name = "Mia", team = "Blue Paws" },
      { kind = "open", user = "u-guest", name = "Zed" },
      { kind = "bot" },
      { kind = "open" },
    },
  }
  for k, v in pairs(fields or {}) do
    out[k] = v
  end
  return out
end

describe("🏠 the Salon as the lobby state says (§6.3, §7.2)", function()
  it(
    "🏠 names each seat: team and nickname, the host marked, Open or Bot for the others",
    function()
      local v = room_view.build(lobby(), "u-guest")
      assert.is_false(v.host)
      assert.are.equal("ABCDE", v.code)
      assert.are.same(
        { shown = true, team = "Blue Paws", player = "Mia (host)", mine = false },
        v.seats[1]
      )
      assert.are.same({ shown = true, team = "Zed", player = "Zed", mine = true }, v.seats[2])
      assert.are.same({ shown = true, team = "Bot", player = "", mine = false }, v.seats[3])
      assert.are.same({ shown = true, team = "Open", player = "", mine = false }, v.seats[4])
      for i = 5, 8 do
        assert.are.same({ shown = false }, v.seats[i])
      end
    end
  )

  it(
    "🏠 only the host may switch a free seat between Open and Bot, or change a setting",
    function()
      local guest = room_view.build(lobby(), "u-guest")
      for _, button in ipairs({ "seat_3", "seat_4", "teams_plus", "map_cycle", "launch" }) do
        assert.is_nil(room_view.request(guest, button), button)
      end
      local host = room_view.build(lobby(), "u-host")
      assert.is_true(host.host)
      assert.are.same(
        { "lobby_slot", { seat = 3, kind = "open" } },
        { room_view.request(host, "seat_3") }
      )
      assert.are.same(
        { "lobby_slot", { seat = 4, kind = "bot" } },
        { room_view.request(host, "seat_4") }
      )
      assert.is_nil(room_view.request(host, "seat_1"))
      assert.is_nil(room_view.request(host, "seat_2"))
      assert.is_nil(room_view.request(host, "seat_7"))
      assert.are.same({ "start", {} }, { room_view.request(host, "launch") })
    end
  )

  it("🏠 steps and cycles the settings within their bounds (§5.2)", function()
    local host = room_view.build(lobby(), "u-host")
    assert.are.same({ "lobby_settings", { teams = 5 } }, { room_view.request(host, "teams_plus") })
    assert.are.same({ "lobby_settings", { teams = 3 } }, { room_view.request(host, "teams_minus") })
    assert.are.same(
      { "lobby_settings", { cats_per_team = 1 } },
      { room_view.request(host, "cats_minus") }
    )
    assert.are.same(
      { "lobby_settings", { turn_seconds = 60 } },
      { room_view.request(host, "turn_cycle") }
    )
    assert.are.same(
      { "lobby_settings", { map = "forest" } },
      { room_view.request(host, "map_cycle") }
    )
    assert.are.same(
      { "lobby_settings", { bot_level = "hard" } },
      { room_view.request(host, "bots_cycle") }
    )
    local edge = room_view.build(
      lobby({
        settings = {
          teams = 8,
          cats_per_team = 1,
          turn_seconds = 90,
          map = "random",
          bot_level = "hard",
        },
      }),
      "u-host"
    )
    assert.is_nil(room_view.request(edge, "teams_plus"))
    assert.is_nil(room_view.request(edge, "cats_minus"))
    assert.are.same(
      { "lobby_settings", { turn_seconds = 30 } },
      { room_view.request(edge, "turn_cycle") }
    )
    assert.are.same(
      { "lobby_settings", { map = "forest" } },
      { room_view.request(edge, "map_cycle") }
    )
    assert.are.same(
      { "lobby_settings", { bot_level = "easy" } },
      { room_view.request(edge, "bots_cycle") }
    )
    assert.is_false(edge.settings.teams.plus)
    assert.is_true(edge.settings.teams.minus)
  end)

  it("🏠 never offers to drop the teams under a seat a player holds", function()
    local held = lobby({
      settings = {
        teams = 2,
        cats_per_team = 2,
        turn_seconds = 45,
        map = "random",
        bot_level = "medium",
      },
      seats = {
        { kind = "open", user = "u-host", name = "Mia" },
        { kind = "open", user = "u-guest", name = "Zed" },
      },
    })
    local v = room_view.build(held, "u-host")
    assert.is_false(v.settings.teams.minus)
    assert.is_nil(room_view.request(v, "teams_minus"))
    local three = lobby()
    three.settings.teams = 3
    three.seats[3] = { kind = "open", user = "u-third", name = "Kai" }
    three.seats[4] = nil
    assert.is_false(room_view.build(three, "u-host").settings.teams.minus)
  end)

  it("🏠 shows every setting's value as the catalogue writes it", function()
    local v = room_view.build(lobby(), "u-guest")
    assert.are.equal("4", v.settings.teams.text)
    assert.are.equal("2", v.settings.cats.text)
    assert.are.equal("45 s", v.settings.turn.text)
    assert.are.equal("Random", v.settings.map.text)
    assert.are.equal("Medium", v.settings.bots.text)
  end)
end)

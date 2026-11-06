local protocol = require("shared.protocol")

describe("🏠 room codes (§6.3)", function()
  it("🏠 accepts five letters of the alphabet", function()
    assert.is_true(protocol.valid_code("ABCDE"))
    assert.is_true(protocol.valid_code("ZZZZZ"))
    assert.is_true(protocol.valid_code("HJKLM"))
  end)

  it("🏠 rejects I and O, the wrong length, lowercase and non-strings", function()
    for _, code in ipairs({ "ABCDI", "OABCD", "ABCD", "ABCDEF", "", "abcde", "ABC E", "ABC1E" }) do
      assert.is_false(protocol.valid_code(code), code)
    end
    assert.is_false(protocol.valid_code(12345))
    assert.is_false(protocol.valid_code(nil))
    assert.is_false(protocol.valid_code({ "ABCDE" }))
  end)

  it("🏠 turns five numbers into a code, each wrapped into the alphabet", function()
    assert.are.equal("ABCDE", protocol.code_from({ 0, 1, 2, 3, 4 }))
    assert.are.equal("ZABCD", protocol.code_from({ 23, 24, 25, 26, 27 }))
    assert.are.equal("RRRRR", protocol.code_from({ 255, 255, 255, 255, 255 }))
  end)
end)

describe("🏠 nicknames (§6.1)", function()
  it("🏠 accepts 2 to 16 ASCII letters, digits, spaces, _ and -", function()
    for _, name in ipairs({ "Al", "Mimi 2", "le_chat-noir", "ABCDEFGHIJKLMNOP", "07" }) do
      assert.is_true(protocol.valid_nickname(name), name)
    end
  end)

  it("🏠 rejects the wrong length, other characters and edge spaces", function()
    for _, name in ipairs({
      "A",
      "ABCDEFGHIJKLMNOPQ",
      "Zoé",
      "a.b",
      "<script>",
      " Al",
      "Al ",
      "  ",
      "tab\tcat",
    }) do
      assert.is_false(protocol.valid_nickname(name), name)
    end
    assert.is_false(protocol.valid_nickname(nil))
    assert.is_false(protocol.valid_nickname(42))
  end)
end)

describe("🚫 op codes (§6.4)", function()
  it(
    "🚫 are those of the table, client to server below 100, server to clients from 100",
    function()
      assert.are.same({
        lobby_settings = 1,
        lobby_slot = 2,
        start = 3,
        input = 10,
        fire = 11,
        skip = 12,
        snapshot_request = 13,
        rematch = 20,
        lobby_state = 100,
        game_start = 101,
        ticks = 102,
        checksum = 103,
        snapshot = 104,
        game_end = 105,
        refused = 106,
        pilots = 107,
      }, protocol.OPS)
      for op, name in pairs(protocol.CLIENT_OPS) do
        assert.is_true(op < 100, name)
      end
    end
  )
end)

describe("🚫 lobby message shapes (§6.4)", function()
  local OPS = protocol.OPS

  it("🚫 keeps only the lobby settings and a seed", function()
    local msg = protocol.decode(OPS.lobby_settings, { teams = 3, wind_max = 0, seed = 7, x = "y" })
    assert.are.same({ teams = 3, seed = 7 }, msg)
  end)

  it("🚫 refuses a seed that is not an integer from 0 to 2147483646", function()
    for _, seed in ipairs({ -1, 2147483647, 3.5, "7", true }) do
      local msg, reason = protocol.decode(OPS.lobby_settings, { seed = seed })
      assert.is_nil(msg)
      assert.are.equal("invalid_seed", reason)
    end
  end)

  it("🚫 reads a lobby_slot with an integer seat and a known kind", function()
    assert.are.same(
      { seat = 2, kind = "bot" },
      protocol.decode(OPS.lobby_slot, { seat = 2, kind = "bot" })
    )
    for _, bad in ipairs({
      { seat = 0, kind = "bot" },
      { seat = 9, kind = "open" },
      { seat = 1.5, kind = "open" },
      { seat = "1", kind = "open" },
      { seat = 1, kind = "human" },
      { seat = 1 },
    }) do
      local msg, reason = protocol.decode(OPS.lobby_slot, bad)
      assert.is_nil(msg)
      assert.are.equal("malformed", reason)
    end
  end)

  it("🚫 reads start and rematch as empty messages", function()
    assert.are.same({}, protocol.decode(OPS.start, { anything = 1 }))
    assert.are.same({}, protocol.decode(OPS.rematch, {}))
  end)

  it("🚫 refuses an unknown opcode", function()
    local msg, reason = protocol.decode(99, {})
    assert.is_nil(msg)
    assert.are.equal("unknown_op", reason)
    assert.are.equal("unknown_op", select(2, protocol.decode(OPS.lobby_state, {})))
  end)
end)

describe("🚫 game message shapes (§6.4, §6.8)", function()
  local OPS = protocol.OPS

  local function reason(op, msg)
    return select(2, protocol.decode(op, msg))
  end

  it("🚫 reads move and jump inputs with their directions", function()
    assert.are.same(
      { kind = "move", direction = -1 },
      protocol.decode(OPS.input, {
        kind = "move",
        direction = -1,
        team = 3,
      })
    )
    assert.are.same(
      { kind = "move", direction = 0 },
      protocol.decode(OPS.input, {
        kind = "move",
        direction = 0,
      })
    )
    assert.are.same(
      { kind = "jump", direction = 1 },
      protocol.decode(OPS.input, {
        kind = "jump",
        direction = 1,
      })
    )
    assert.are.same(
      { kind = "climb", direction = -1 },
      protocol.decode(OPS.input, { kind = "climb", direction = -1, extra = true })
    )
    assert.are.same(
      { kind = "climb", direction = 0 },
      protocol.decode(OPS.input, { kind = "climb", direction = 0 })
    )
    assert.are.equal("invalid_direction", reason(OPS.input, { kind = "climb", direction = 2 }))
    assert.are.equal("invalid_direction", reason(OPS.input, { kind = "climb", direction = 0.5 }))
    assert.are.equal("invalid_direction", reason(OPS.input, { kind = "climb" }))
    assert.are.equal("invalid_direction", reason(OPS.input, { kind = "jump", direction = 0 }))
    assert.are.equal("invalid_direction", reason(OPS.input, { kind = "move", direction = 2 }))
    assert.are.equal("invalid_direction", reason(OPS.input, { kind = "move", direction = "1" }))
    assert.are.equal("invalid_direction", reason(OPS.input, { kind = "move", direction = 0.5 }))
    assert.are.equal("malformed", reason(OPS.input, { kind = "fire", direction = 1 }))
    assert.are.equal("malformed", reason(OPS.input, { direction = 1 }))
  end)

  it("🚫 reads a fire within the bounds of §6.8, and nothing else", function()
    assert.are.same(
      { weapon = "bazooka", angle = 0, power = 1 },
      protocol.decode(OPS.fire, { weapon = "bazooka", angle = 0, power = 1, team = 2 })
    )
    assert.are.same(
      { weapon = "grenade", angle = 1023, power = 100, fuse = 5 },
      protocol.decode(OPS.fire, { weapon = "grenade", angle = 1023, power = 100, fuse = 5 })
    )
    assert.are.same(
      { weapon = "grenade", angle = 10, power = 10 },
      protocol.decode(OPS.fire, { weapon = "grenade", angle = 10, power = 10 })
    )
    assert.are.same(
      { weapon = "airstrike", angle = 0, power = 1, target = 1023 },
      protocol.decode(OPS.fire, { weapon = "airstrike", angle = 0, power = 1, target = 1023 })
    )
    assert.are.same(
      { weapon = "cluster", angle = 10, power = 10, fuse = 1 },
      protocol.decode(OPS.fire, { weapon = "cluster", angle = 10, power = 10, fuse = 1 })
    )
    local cases = {
      { { weapon = "laser", angle = 0, power = 1 }, "invalid_weapon" },
      { { weapon = "cluster_bit", angle = 0, power = 1 }, "invalid_weapon" },
      { { weapon = "airstrike_shell", angle = 0, power = 1 }, "invalid_weapon" },
      { { weapon = "airstrike", angle = 0, power = 1 }, "invalid_target" },
      { { weapon = "airstrike", angle = 0, power = 1, target = -1 }, "invalid_target" },
      { { weapon = "airstrike", angle = 0, power = 1, target = 1024 }, "invalid_target" },
      { { weapon = "airstrike", angle = 0, power = 1, target = 2.5 }, "invalid_target" },
      { { weapon = "airstrike", angle = 0, power = 1, target = "9" }, "invalid_target" },
      { { weapon = "bazooka", angle = 0, power = 1, target = 9 }, "invalid_target" },
      { { weapon = 1, angle = 0, power = 1 }, "invalid_weapon" },
      { { weapon = "bazooka", angle = 1024, power = 1 }, "invalid_angle" },
      { { weapon = "bazooka", angle = -1, power = 1 }, "invalid_angle" },
      { { weapon = "bazooka", angle = 1.5, power = 1 }, "invalid_angle" },
      { { weapon = "bazooka", power = 1 }, "invalid_angle" },
      { { weapon = "bazooka", angle = 0, power = 0 }, "invalid_power" },
      { { weapon = "bazooka", angle = 0, power = 101 }, "invalid_power" },
      { { weapon = "bazooka", angle = 0, power = "50" }, "invalid_power" },
      { { weapon = "grenade", angle = 0, power = 1, fuse = 0 }, "invalid_fuse" },
      { { weapon = "grenade", angle = 0, power = 1, fuse = 6 }, "invalid_fuse" },
      { { weapon = "grenade", angle = 0, power = 1, fuse = 2.5 }, "invalid_fuse" },
      { { weapon = "bazooka", angle = 0, power = 1, fuse = 3 }, "invalid_fuse" },
      { { weapon = "dynamite", angle = 0, power = 1, fuse = 3 }, "invalid_fuse" },
    }
    for _, case in ipairs(cases) do
      assert.are.equal(case[2], reason(OPS.fire, case[1]))
    end
  end)

  it("🚫 reads skip as an empty message", function()
    assert.are.same({}, protocol.decode(OPS.skip, { team = 1 }))
  end)

  it("🚫 reads a snapshot request with an optional divergence tick", function()
    assert.are.same({}, protocol.decode(OPS.snapshot_request, {}))
    assert.are.same({ tick = 60 }, protocol.decode(OPS.snapshot_request, { tick = 60 }))
    for _, tick in ipairs({ -1, 1.5, "60", true }) do
      assert.are.equal("malformed", reason(OPS.snapshot_request, { tick = tick }))
    end
  end)
end)

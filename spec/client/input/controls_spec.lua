local controls = require("input.controls")

local function fake_authority()
  local sent = {}
  return {
    sent = sent,
    send = function(name, body)
      sent[#sent + 1] = { name = name, body = body }
    end,
  }
end

local CAT = { x = 300, y = 200, radius = 0 }
local R = controls.CANCEL_RADIUS

local function info(fields)
  return {
    mine = fields.mine ~= false,
    state = fields.state or "aiming",
    cat = fields.cat or CAT,
    facing = fields.facing or 1,
    weapons = fields.weapons or { "bazooka", "grenade", "tentacle", "uppercut" },
    hanging = fields.hanging,
    jetting = fields.jetting,
    triggerable = fields.triggerable,
  }
end

local function open(fields)
  local authority = fake_authority()
  local c = controls.new({ authority = authority })
  controls.turn(c, info(fields or {}))
  return c, authority
end

local function drag(c, points, id, mouse)
  id = id or 1
  controls.press(c, { id = id, x = points[1][1], y = points[1][2], mouse = mouse })
  for i = 2, #points do
    controls.move(c, { id = id, x = points[i][1], y = points[i][2], mouse = mouse })
  end
  controls.release(c, { id = id, x = points[#points][1], y = points[#points][2], mouse = mouse })
end

describe("🎯 the slingshot aim and the controls (§7.3, D-04)", function()
  it(
    "🎯 a drag back from the blob fires the opposite way with integer angle and power",
    function()
      local c, authority = open()
      drag(c, { { 305, 204 }, { 330, 170 }, { 360, 140 } })
      assert.are.same(
        { { name = "fire", body = { weapon = "bazooka", angle = 384, power = 50 } } },
        authority.sent
      )
    end
  )

  it("🎯 quantizes to the sim's integers before anything leaves the input layer", function()
    local c, authority = open()
    drag(c, { { 300, 200 }, { 300 - 37.3, 200 + 0.7 } })
    assert.are.same({ weapon = "bazooka", angle = 1021, power = 13 }, authority.sent[1].body)
  end)

  it("🎯 pulling beyond the full length keeps the power at 100", function()
    local c, authority = open()
    drag(c, { { 300, 200 }, { 300, 200 - controls.PULL * 3 } })
    assert.are.same({ weapon = "bazooka", angle = 256, power = 100 }, authority.sent[1].body)
  end)

  it("🎯 a press farther than 48 points from the blob is not an aim", function()
    local c, authority = open()
    drag(c, { { 300 + 49, 200 }, { 450, 60 } })
    assert.are.same({}, authority.sent)
    assert.is_nil(controls.aim(c))
  end)

  it("🎯 a tap next to the blob, without a drag, sends nothing", function()
    local c, authority = open()
    drag(c, { { 335, 200 }, { 338, 203 } })
    assert.are.same({}, authority.sent)
  end)

  it("🎯 bringing the finger back on the blob cancels, and nothing is sent", function()
    local c, authority = open()
    drag(c, { { 300, 200 }, { 380, 120 }, { 302, 199 } })
    assert.are.same({}, authority.sent)
  end)

  it("🎯 on a close-up, anywhere on the blob cancels and the pull starts at its edge", function()
    local close = { x = 300, y = 200, radius = 40 }
    local c, authority = open({ cat = close })
    drag(c, { { 300, 200 }, { 400, 100 }, { 326, 200 } })
    assert.are.same({}, authority.sent)
    drag(c, { { 300, 200 }, { 300 + 40 + 65, 200 } })
    assert.are.same({ weapon = "bazooka", angle = 512, power = 50 }, authority.sent[1].body)
  end)

  it(
    "🎯 aims from where the blob was when the finger pressed, even if the view drifts",
    function()
      local c, authority = open()
      controls.press(c, { id = 1, x = 300, y = 200 })
      controls.turn(c, info({ cat = { x = 320, y = 190, radius = 0 } }))
      controls.move(c, { id = 1, x = 360, y = 140 })
      controls.release(c, { id = 1, x = 360, y = 140 })
      assert.are.same({ weapon = "bazooka", angle = 384, power = 50 }, authority.sent[1].body)
    end
  )

  it("🎯 a second finger never takes the aim over", function()
    local c, authority = open()
    controls.press(c, { id = 1, x = 300, y = 200 })
    assert.is_false(controls.press(c, { id = 2, x = 302, y = 201 }))
    assert.is_false(controls.move(c, { id = 2, x = 200, y = 300 }))
    controls.move(c, { id = 1, x = 360, y = 140 })
    assert.is_false(controls.release(c, { id = 2, x = 200, y = 300 }))
    controls.release(c, { id = 1, x = 360, y = 140 })
    assert.are.same({ weapon = "bazooka", angle = 384, power = 50 }, authority.sent[1].body)
  end)

  it("🎯 shows the live aim while dragging, from the same integers", function()
    local c = open()
    controls.press(c, { id = 1, x = 300, y = 200 })
    controls.move(c, { id = 1, x = 300 - R - controls.PULL, y = 200 })
    assert.are.same({ angle = 0, power = 100, weapon = "bazooka" }, controls.aim(c))
  end)

  it("🎯 sends the grenade with its fuse, and the fuse turns from 1 to 5 s", function()
    local c, authority = open()
    controls.weapon(c, "grenade")
    assert.are.equal(3, controls.fuse(c))
    controls.next_fuse(c)
    controls.next_fuse(c)
    controls.next_fuse(c)
    assert.are.equal(1, controls.fuse(c))
    drag(c, { { 300, 200 }, { 300, 200 - R - controls.PULL } })
    assert.are.same(
      { weapon = "grenade", angle = 256, power = 100, fuse = 1 },
      authority.sent[1].body
    )
  end)

  it("🎯 walks while a direction is held, stops when released, jumps where it walks", function()
    local c, authority = open()
    controls.walk(c, 1)
    controls.walk(c, 1)
    controls.walk(c, 0)
    controls.jump(c)
    controls.walk(c, -1)
    controls.jump(c)
    assert.are.same({
      { name = "input", body = { kind = "move", direction = 1 } },
      { name = "input", body = { kind = "move", direction = 0 } },
      { name = "input", body = { kind = "jump", direction = 1 } },
      { name = "input", body = { kind = "move", direction = -1 } },
      { name = "input", body = { kind = "jump", direction = -1 } },
    }, authority.sent)
  end)

  it("🎯 a direction still held walks again as soon as the retreat allows it", function()
    local c, authority = open()
    controls.walk(c, 1)
    controls.turn(c, info({ state = "flight" }))
    controls.turn(c, info({ state = "retreat" }))
    controls.walk(c, 0)
    assert.are.same({
      { name = "input", body = { kind = "move", direction = 1 } },
      { name = "input", body = { kind = "move", direction = 1 } },
      { name = "input", body = { kind = "move", direction = 0 } },
    }, authority.sent)
  end)

  it(
    "🎯 a direction held while placing walks again in the retreat, on the table the game reuses",
    function()
      local c, authority = open()
      local shared = info({ state = "aiming" })
      controls.walk(c, 1)
      controls.turn(c, shared)
      shared.state = "retreat"
      controls.turn(c, shared)
      controls.turn(c, shared)
      assert.are.same({
        { name = "input", body = { kind = "move", direction = 1 } },
        { name = "input", body = { kind = "move", direction = 1 } },
      }, authority.sent)
    end
  )

  it("🎯 a direction let go between turns does not walk on the next turn", function()
    local c, authority = open()
    controls.walk(c, 1)
    controls.turn(c, info({ state = "flight" }))
    controls.walk(c, 0)
    controls.turn(c, info({ mine = false }))
    controls.turn(c, info({}))
    controls.walk(c, 1)
    assert.are.same({
      { name = "input", body = { kind = "move", direction = 1 } },
      { name = "input", body = { kind = "move", direction = 1 } },
    }, authority.sent)
  end)

  it("🎯 walks but never fires during the retreat", function()
    local c, authority = open({ state = "retreat", facing = -1, weapons = { "bazooka" } })
    drag(c, { { 300, 200 }, { 300, 100 } })
    controls.jump(c)
    assert.are.same(
      { { name = "input", body = { kind = "jump", direction = -1 } } },
      authority.sent
    )
  end)

  it("🎯 sends nothing when it is not the player's turn to aim", function()
    local c, authority = open({ mine = false, weapons = { "bazooka" } })
    drag(c, { { 300, 200 }, { 300, 100 } })
    controls.walk(c, -1)
    controls.jump(c)
    assert.are.same({}, authority.sent)
  end)

  it("🖱️ with the mouse, the shot goes toward the cursor, with the same integers", function()
    local c, authority = open()
    drag(c, { { 300, 200 }, { 300 + R + controls.PULL, 200 } }, 1, true)
    assert.are.same({ weapon = "bazooka", angle = 0, power = 100 }, authority.sent[1].body)
    local finger, by_finger = open()
    local mouse, by_mouse = open()
    local path = { { 305, 204 }, { 330, 170 }, { 360, 140 } }
    drag(finger, path)
    drag(mouse, path, 1, true)
    local f, m = by_finger.sent[1].body, by_mouse.sent[1].body
    assert.are.equal((f.angle + 512) % 1024, m.angle)
    assert.are.equal(f.power, m.power)
  end)

  it("🖱️ bringing the cursor back on the blob cancels, as with a finger", function()
    local c, authority = open()
    drag(c, { { 300, 200 }, { 380, 120 }, { 302, 199 } }, 1, true)
    assert.are.same({}, authority.sent)
  end)

  it("⌨️ ↑ and ↓ turn the aim on the side the blob faces, from 45° up", function()
    local c = open()
    controls.aim_key(c, 0, 0)
    assert.are.equal(128, controls.aim(c).angle)
    controls.aim_key(c, 1, 0.5)
    assert.are.equal(128 + controls.AIM_SPEED / 2, controls.aim(c).angle)
    controls.aim_key(c, -1, 10)
    assert.are.equal(768, controls.aim(c).angle)
    local left = open({ facing = -1 })
    controls.aim_key(left, 0, 0)
    assert.are.equal(384, controls.aim(left).angle)
  end)

  it("⌨️ Space held charges the power, released fires with integer angle and power", function()
    local c, authority = open()
    controls.charge(c, controls.CHARGE_SECONDS / 2)
    assert.are.equal(50, controls.aim(c).power)
    controls.release_charge(c)
    assert.are.same(
      { { name = "fire", body = { weapon = "bazooka", angle = 128, power = 50 } } },
      authority.sent
    )
    assert.is_nil(controls.aim(c).charging)
  end)

  it("⌨️ a full charge fires by itself, once", function()
    local c, authority = open()
    controls.charge(c, controls.CHARGE_SECONDS * 2)
    controls.charge(c, 0.1)
    controls.release_charge(c)
    assert.are.same(
      { { name = "fire", body = { weapon = "bazooka", angle = 128, power = 100 } } },
      authority.sent
    )
  end)

  it("🐙 the tentacle is picked like a weapon and thrown by the same slingshot", function()
    local c, authority = open()
    controls.weapon(c, "tentacle")
    drag(c, { { 305, 204 }, { 330, 170 }, { 360, 140 } })
    assert.are.same(
      { { name = "fire", body = { weapon = "tentacle", angle = 384, power = 50 } } },
      authority.sent
    )
  end)

  it("🐙 hanging, nothing fires, ◀ ▶ swing, ▲ ▼ climb and jump lets go", function()
    local c, authority = open({ hanging = true })
    drag(c, { { 305, 204 }, { 330, 170 }, { 360, 140 } })
    controls.charge(c, 2)
    controls.release_charge(c)
    assert.are.same({}, authority.sent)
    assert.is_nil(controls.aim(c))
    controls.walk(c, 1)
    controls.climb(c, -1)
    controls.climb(c, -1)
    controls.climb(c, 0)
    controls.jump(c)
    assert.are.same({
      { name = "input", body = { kind = "move", direction = 1 } },
      { name = "input", body = { kind = "climb", direction = -1 } },
      { name = "input", body = { kind = "climb", direction = 0 } },
      { name = "input", body = { kind = "jump", direction = 1 } },
    }, authority.sent)
  end)

  it("🐙 a climb held before the tentacle hooks is sent once it does, not before", function()
    local c, authority = open()
    controls.climb(c, 1)
    assert.are.same({}, authority.sent)
    controls.turn(c, info({ hanging = true }))
    assert.are.same(
      { { name = "input", body = { kind = "climb", direction = 1 } } },
      authority.sent
    )
    controls.turn(c, info({ hanging = false }))
    controls.turn(c, info({ hanging = true }))
    assert.are.equal(2, #authority.sent)
    controls.turn(c, info({ hanging = true, state = "settling" }))
    controls.climb(c, -1)
    assert.are.equal(2, #authority.sent)
  end)

  it("⌨️ Space throws the tentacle at once, without charging, and only once", function()
    local c, authority = open()
    controls.weapon(c, "tentacle")
    controls.aim_key(c, 1, 0.25)
    controls.charge(c, 1 / 60)
    assert.are.equal(1, #authority.sent)
    controls.turn(c, info({ hanging = true }))
    controls.turn(c, info({ hanging = false }))
    controls.charge(c, 1 / 60)
    controls.release_charge(c)
    assert.are.equal(1, #authority.sent)
    local shot = authority.sent[1].body
    assert.are.same(
      { weapon = "tentacle", angle = 192 },
      { weapon = shot.weapon, angle = shot.angle }
    )
    assert.is_true(shot.power >= 1 and shot.power <= 100)
  end)

  it("⌨️ Space held while hanging and after letting go throws nothing more", function()
    local c, authority = open()
    controls.weapon(c, "tentacle")
    controls.charge(c, 1 / 60)
    controls.turn(c, info({ hanging = true }))
    controls.charge(c, 1 / 60)
    controls.turn(c, info({ hanging = false }))
    controls.charge(c, 1 / 60)
    assert.are.equal(1, #authority.sent)
    controls.release_charge(c)
    controls.charge(c, 1 / 60)
    assert.are.equal(2, #authority.sent)
  end)

  it("🥊 the uppercut is struck by the same slingshot, and no aim line is shown", function()
    local c, authority = open()
    controls.weapon(c, "uppercut")
    controls.press(c, { id = 1, x = 305, y = 204 })
    controls.move(c, { id = 1, x = 360, y = 140 })
    assert.is_true(controls.aiming(c))
    assert.is_nil(controls.aim(c))
    controls.release(c, { id = 1, x = 360, y = 140 })
    assert.are.equal(1, #authority.sent)
    local shot = authority.sent[1].body
    assert.are.same({ "fire", "uppercut" }, { authority.sent[1].name, shot.weapon })
    drag(c, { { 305, 204 }, { 330, 170 }, { 302, 202 } })
    assert.are.equal(1, #authority.sent)
  end)

  it("⌨️ Space strikes the uppercut at once, without charging, and only once", function()
    local c, authority = open()
    controls.weapon(c, "uppercut")
    controls.aim_key(c, 1, 0.25)
    assert.is_nil(controls.aim(c))
    controls.charge(c, 1 / 60)
    assert.are.equal(1, #authority.sent)
    assert.are.equal("uppercut", authority.sent[1].body.weapon)
    controls.charge(c, 1 / 60)
    controls.release_charge(c)
    assert.are.equal(1, #authority.sent)
  end)

  it("🐙 hanging, ↑ ↓ leave the angle alone, and no aim is shown or started", function()
    local c, authority = open()
    controls.aim_key(c, 1, 0.25)
    local before = controls.aim(c).angle
    controls.turn(c, info({ hanging = true }))
    controls.aim_key(c, 1, 0.5)
    assert.is_nil(controls.aim(c))
    assert.is_false(controls.press(c, { id = 1, x = CAT.x, y = CAT.y }))
    assert.is_false(controls.aiming(c))
    controls.turn(c, info({ hanging = false }))
    assert.are.equal(before, controls.aim(c).angle)
    assert.are.same({}, authority.sent)
  end)

  it("⌨️ fires nothing from the keyboard outside the player's aiming turn", function()
    local c, authority = open({ state = "retreat" })
    controls.charge(c, 1)
    controls.release_charge(c)
    assert.are.same({}, authority.sent)
  end)

  it("🎒 on the player's turn, a weapon that ran out gives way to the first left", function()
    local c = open({ weapons = { "bazooka", "grenade", "tentacle" } })
    controls.weapon(c, "grenade")
    controls.turn(c, info({ mine = false, weapons = { "bazooka", "tentacle" } }))
    assert.are.equal("grenade", controls.current_weapon(c))
    controls.turn(c, info({ weapons = { "bazooka", "tentacle" } }))
    assert.are.equal("bazooka", controls.current_weapon(c))
  end)

  it("🎒 a weapon that is not left cannot be picked", function()
    local c = open({ weapons = { "grenade", "tentacle" } })
    controls.weapon(c, "bazooka")
    assert.are.equal("grenade", controls.current_weapon(c))
  end)

  local STRIKE = { "bazooka", "airstrike" }

  it(
    "📡 the air strike takes a column from a tap on the map, and Strike sends it there",
    function()
      local c, authority = open({ weapons = STRIKE })
      controls.weapon(c, "airstrike")
      assert.is_true(controls.targeting(c))
      assert.is_nil(controls.target(c))
      assert.is_false(controls.press(c, { id = 1, x = CAT.x, y = CAT.y }))
      assert.is_true(controls.place_target(c, 140.7))
      assert.are.equal(140, controls.target(c))
      assert.is_true(controls.place_target(c, 212))
      controls.strike(c)
      assert.are.same({
        { name = "fire", body = { weapon = "airstrike", angle = 0, power = 1, target = 212 } },
      }, authority.sent)
      assert.is_nil(controls.target(c))
    end
  )

  it("📡 without a column, Strike and the fire key send nothing", function()
    local c, authority = open({ weapons = STRIKE })
    controls.weapon(c, "airstrike")
    controls.strike(c)
    controls.charge(c, 0.1)
    assert.are.same({}, authority.sent)
  end)

  it("📡 the fire key lets the strike go on the placed column", function()
    local c, authority = open({ weapons = STRIKE })
    controls.weapon(c, "airstrike")
    controls.place_target(c, 33)
    controls.charge(c, 0.1)
    controls.charge(c, 0.1)
    assert.are.same(
      { { name = "fire", body = { weapon = "airstrike", angle = 0, power = 1, target = 33 } } },
      authority.sent
    )
  end)

  it("📡 another weapon, or the end of the aiming, forgets the column", function()
    local c, authority = open({ weapons = STRIKE })
    assert.is_false(controls.targeting(c))
    assert.is_false(controls.place_target(c, 50))
    controls.weapon(c, "airstrike")
    controls.place_target(c, 50)
    controls.weapon(c, "bazooka")
    controls.weapon(c, "airstrike")
    assert.is_nil(controls.target(c))
    controls.place_target(c, 50)
    controls.turn(c, info({ weapons = STRIKE, state = "flight" }))
    assert.is_nil(controls.target(c))
    assert.is_false(controls.place_target(c, 50))
    controls.strike(c)
    assert.are.same({}, authority.sent)
  end)

  it("🐑 while my Waddler walks, the fire key sets it off, once", function()
    local c, authority = open({ weapons = { "bazooka" } })
    controls.turn(c, info({ weapons = { "bazooka" }, state = "flight", triggerable = "waddler" }))
    assert.is_true(controls.can_trigger(c))
    controls.charge(c, 0.1)
    controls.charge(c, 0.1)
    controls.release_charge(c)
    controls.charge(c, 0.1)
    assert.are.same(
      { { name = "fire", body = { weapon = "waddler", angle = 0, power = 1 } } },
      authority.sent
    )
  end)

  it("🐑 with no Waddler walking, or not mine, nothing goes off", function()
    local c, authority = open({ state = "flight" })
    assert.is_false(controls.can_trigger(c))
    controls.trigger(c)
    controls.turn(c, info({ state = "flight", triggerable = "waddler", mine = false }))
    controls.trigger(c)
    assert.are.same({}, authority.sent)
  end)

  it(
    "🚀 on the jetpack, ▲ thrusts like it climbs a rope, and stops when the engine does",
    function()
      local c, authority = open({ jetting = true })
      controls.climb(c, -1)
      controls.climb(c, 0)
      controls.turn(c, info({ jetting = false }))
      controls.climb(c, -1)
      assert.are.same({
        { name = "input", body = { kind = "climb", direction = -1 } },
        { name = "input", body = { kind = "climb", direction = 0 } },
      }, authority.sent)
    end
  )

  it("🐑 a Waddler outside flight is no trigger", function()
    for _, state in ipairs({ "aiming", "retreat", "settling" }) do
      local c, authority = open({ weapons = { "bazooka" } })
      controls.turn(c, info({ weapons = { "bazooka" }, state = state, triggerable = "waddler" }))
      assert.is_false(controls.can_trigger(c))
      assert.is_false(controls.trigger(c))
      for _, sent in ipairs(authority.sent) do
        assert.are_not.equal("waddler", sent.body.weapon)
      end
    end
  end)

  it("🐑 Boom tapped again before the Waddler is gone sends nothing more", function()
    local c, authority = open({ weapons = { "bazooka" } })
    local flying = info({ weapons = { "bazooka" }, state = "flight", triggerable = "waddler" })
    controls.turn(c, flying)
    assert.is_true(controls.trigger(c))
    controls.turn(c, flying)
    assert.is_false(controls.can_trigger(c))
    assert.is_false(controls.trigger(c))
    assert.are.equal(1, #authority.sent)
    controls.turn(c, info({ weapons = { "bazooka" }, state = "flight" }))
    controls.turn(c, flying)
    assert.is_true(controls.trigger(c))
  end)

  it("🚀 ▲ held while the jetpack hands over to the tentacle is sent again", function()
    local c, authority = open({ jetting = true, weapons = { "tentacle" } })
    controls.climb(c, -1)
    controls.turn(c, info({ hanging = true, jetting = false, weapons = { "tentacle" } }))
    assert.are.same({
      { name = "input", body = { kind = "climb", direction = -1 } },
      { name = "input", body = { kind = "climb", direction = -1 } },
    }, authority.sent)
  end)

  it("🚀 ▲ held on the jetpack thrusts without swinging the keyboard aim", function()
    local c = open({ jetting = true })
    local before = controls.aim(c)
    controls.aim_key(c, 1, 0.9)
    assert.are.same(before, controls.aim(c))
  end)
end)

local camera_rig = require("game.camera_rig")
local director = require("game.director")
local rules = require("shared.sim.rules")

local function view(fields)
  return {
    now = fields.now or 0,
    state = fields.state or "aiming",
    projectile = fields.projectile,
    thrown = fields.thrown,
    dead = fields.dead,
    crate = fields.crate,
    active = fields.active or { x = 1, y = 1 },
  }
end

describe("🎥 what the camera looks at (§7.3)", function()
  it("🎥 follows the projectile first, then a blob thrown by the blast", function()
    local d = director.new()
    local kind = director.target(d, view({ state = "flight", projectile = { x = 5, y = 5 } }))
    assert.are.equal("projectile", kind)
    director.event(d, { type = "exploded" }, { now = 1, x = 40, y = 20 })
    local k, x =
      director.target(d, view({ now = 1, state = "retreat", thrown = { x = 60, y = 30 } }))
    assert.are.same({ "thrown", 60 }, { k, x })
  end)

  it("📦 shows the last blast, then the crate under its chute, then the blob (§5.10)", function()
    local d = director.new()
    director.event(d, { type = "exploded" }, { now = 10, x = 40, y = 20 })
    director.event(d, { type = "turn_started" }, { now = 10.4 })
    local crate = { x = 90, y = 70 }
    local k = director.target(d, view({ now = 11, state = "turn_start", crate = crate }))
    assert.are.equal("blast", k)
    local kind, x, y = director.target(d, view({ now = 11.3, state = "turn_start", crate = crate }))
    assert.are.same({ "crate", 90, 70 }, { kind, x, y })
    assert.are.equal("active", (director.target(d, view({ now = 13, state = "aiming" }))))
  end)

  it("🎥 follows a shot in flight, never a placed weapon (§7.3)", function()
    assert.is_true(director.follows("airstrike_shell") and director.follows("cluster_bit"))
    assert.is_true(director.follows("bazooka") and director.follows("grenade"))
    assert.is_false(director.follows("dynamite"))
  end)

  it("🎥 stays on a blast for 1.2 s, even once the next turn has started", function()
    local d = director.new()
    director.event(d, { type = "exploded" }, { now = 10, x = 40, y = 20 })
    director.event(d, { type = "turn_started" }, { now = 10.4 })
    local k, x, y = director.target(d, view({ now = 11.1, state = "turn_start" }))
    assert.are.same({ "blast", 40, 20 }, { k, x, y })
    assert.are.equal("active", (director.target(d, view({ now = 11.3, state = "turn_start" }))))
    local turn_start = rules.TURN_START_TICKS / rules.TICKS_PER_SECOND
    assert.is_true(director.HOLD_SECONDS + camera_rig.GLIDE_SECONDS <= turn_start)
  end)

  it("🎥 keeps showing the blast for the whole aftermath of the turn", function()
    local d = director.new()
    director.event(d, { type = "exploded" }, { now = 10, x = 40, y = 20 })
    assert.are.equal("blast", (director.target(d, view({ now = 13, state = "retreat" }))))
    assert.are.equal("blast", (director.target(d, view({ now = 14, state = "settling" }))))
  end)

  it("🎥 shows a blob that dies for 1.2 s, before the blast, then the next blob", function()
    local d = director.new()
    director.event(d, { type = "exploded" }, { now = 10, x = 40, y = 20 })
    director.event(d, { type = "died", cat = 3 }, { now = 10.5 })
    local dead = { x = 70, y = 10 }
    local k, x = director.target(d, view({ now = 11.6, state = "turn_start", dead = dead }))
    assert.are.same({ "death", 70 }, { k, x })
    assert.are.equal(3, director.dying(d))
    assert.are.equal("active", (director.target(d, view({ now = 11.8, state = "turn_start" }))))
  end)

  it(
    "🎥 holds on the crack a quake opens for 1.2 s, even once the next turn has started",
    function()
      local d = director.new()
      director.event(d, { type = "quaked", n = 1 }, { now = 20 })
      director.event(d, { type = "cracked", x = 150, width = 4 }, { now = 20.1, x = 152, y = 90 })
      director.event(d, { type = "turn_started" }, { now = 20.9 })
      local k, x, y = director.target(d, view({ now = 21.2, state = "turn_start" }))
      assert.are.same({ "crack", 152, 90 }, { k, x, y })
      assert.are.equal("active", (director.target(d, view({ now = 21.4, state = "turn_start" }))))
    end
  )

  it("🎥 shows the crack for the whole quake, over the blobs its shakes lift", function()
    local d = director.new()
    director.event(d, { type = "cracked", x = 150, width = 4 }, { now = 30, x = 152, y = 90 })
    local hop = { x = 170, y = 95 }
    local k = director.target(d, view({ now = 30.1, state = "quake", thrown = hop }))
    assert.are.equal("crack", k)
    assert.are.equal(
      "crack",
      (director.target(d, view({ now = 32, state = "quake", thrown = hop })))
    )
  end)

  it("🎥 a quake drops the last blast, and the next turn drops the crack", function()
    local d = director.new()
    director.event(d, { type = "exploded" }, { now = 40, x = 40, y = 20 })
    director.event(d, { type = "quaked", n = 1 }, { now = 42 })
    assert.are.equal("active", (director.target(d, view({ now = 42.5, state = "quake" }))))
    director.event(d, { type = "cracked", x = 150, width = 4 }, { now = 43, x = 152, y = 90 })
    director.event(d, { type = "turn_started" }, { now = 45 })
    director.event(d, { type = "exploded" }, { now = 50, x = 60, y = 30 })
    local k, x = director.target(d, view({ now = 52, state = "retreat" }))
    assert.are.same({ "blast", 60 }, { k, x })
  end)
end)

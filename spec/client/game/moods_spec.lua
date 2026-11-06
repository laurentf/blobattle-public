local moods = require("game.moods")
local terrains = require("spec.support.terrains")
local world = require("shared.sim.world")

local TICK = 1 / 30

local function scene()
  return world.from_terrain({
    terrain = terrains.flat(400),
    liquid = terrains.LIQUID,
    settings = { teams = 2, cats_per_team = 2, wind_max = 0 },
    spawns = {
      { team = 1, index = 1, x = 200, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 350, y = terrains.GROUND - 1 },
      { team = 1, index = 2, x = 230, y = terrains.GROUND - 1 },
      { team = 2, index = 2, x = 20, y = terrains.GROUND - 1 },
    },
  })
end

local function play(w, m, ticks, inputs)
  local exploded = false
  for i = 1, ticks do
    local events = world.step(w, i == 1 and inputs or nil)
    moods.react(m, events, { world = w, now = w.tick * TICK })
    for _, e in ipairs(events) do
      exploded = exploded or e.type == "exploded"
    end
    if exploded then
      return true
    end
  end
  return false
end

local function cat_of(w, team, index)
  for _, c in ipairs(w.cats) do
    if c.team == team and c.index == index then
      return c
    end
  end
end

describe("😠 the blobs' moods in a game (§7.4)", function()
  it("😠 a blob hit gets angry, a blob near the blast gets scared, one far stays calm", function()
    local w, m = scene(), moods.new()
    while w.turn.state ~= "aiming" do
      world.step(w)
    end
    local shooter = w.cats[w.turn.cat]
    local fire = { team = w.turn.team, kind = "fire", weapon = "bazooka", angle = 768, power = 5 }
    assert.is_true(play(w, m, 120, { fire }))
    local mate = cat_of(w, shooter.team, shooter.index == 1 and 2 or 1)
    local far = cat_of(w, shooter.team == 1 and 2 or 1, 1)
    local now = w.tick * TICK
    assert.is_true(shooter.hp < 100)
    assert.are.equal(100, mate.hp)
    assert.are.equal("angry", moods.face(m, shooter.id, now))
    assert.are.equal("scared", moods.face(m, mate.id, now))
    assert.are.equal("calm", moods.face(m, far.id, now))
    now = now + moods.SECONDS + TICK
    for _, c in ipairs(w.cats) do
      assert.are.equal("calm", moods.face(m, c.id, now))
    end
  end)

  it("🦷 a blob that eats opens and shuts its mouth, then calms down", function()
    local w, m = scene(), moods.new()
    while w.turn.state ~= "aiming" do
      world.step(w)
    end
    local eater = w.cats[w.turn.cat]
    local fire = { team = w.turn.team, kind = "fire", weapon = "chomp", angle = 0, power = 1 }
    local seen = {}
    for i = 1, 60 do
      local events = world.step(w, i == 1 and { fire } or nil)
      local now = w.tick * TICK
      moods.react(m, events, { world = w, now = now })
      seen[moods.face(m, eater.id, now)] = true
    end
    assert.are.same({ munch = true, chew = true }, seen)
    local later = w.tick * TICK + moods.MUNCH_HOLD + TICK
    assert.are.equal("calm", moods.face(m, eater.id, later))
  end)

  it("😠 fright never hides anger: an angry blob caught by another blast stays angry", function()
    local m = moods.new()
    local w = scene()
    local c = w.cats[1]
    moods.react(m, { { type = "damaged", cat = c.id, amount = 20 } }, { world = w, now = 1 })
    local cx, cy = math.floor(c.x / 256), math.floor(c.y / 256)
    moods.react(m, { { type = "exploded", x = cx, y = cy, radius = 16 } }, { world = w, now = 1.5 })
    assert.are.equal("angry", moods.face(m, c.id, 1.6))
  end)

  it("😠 tells the caller every face it gives, when asked, for the test trace", function()
    local m = moods.new()
    local onsets = {}
    moods.react(m, {
      { type = "damaged", cat = 3, amount = 12, cause = "explosion" },
      { type = "damaged", cat = 4, amount = 0, cause = "fall" },
      { type = "chomped", cat = 1, x = 10, y = 10, radius = 5 },
    }, { now = 1, world = { cats = {} }, onsets = onsets })
    assert.are.same({ { id = 3, face = "angry" }, { id = 1, face = "munch" } }, onsets)
    moods.react(
      m,
      { { type = "damaged", cat = 3, amount = 5, cause = "fall" } },
      { now = 2, world = { cats = {} } }
    )
  end)

  it("😨 tells the caller of a blob scared by a blast near it", function()
    local m = moods.new()
    local onsets = {}
    local w = { cats = { { id = 1, alive = true, x = 40 * 256, y = 50 * 256 } } }
    moods.react(m, { { type = "exploded", x = 42, y = 47, radius = 12 } }, {
      now = 1,
      world = w,
      onsets = onsets,
    })
    assert.are.same({ { id = 1, face = "scared" } }, onsets)
  end)
end)

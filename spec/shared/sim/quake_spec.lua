local cat = require("shared.sim.cat")
local fixed = require("shared.sim.fixed")
local quake = require("shared.sim.quake")
local rng = require("shared.sim.rng")
local rules = require("shared.sim.rules")
local terrain = require("shared.sim.terrain")
local terrains = require("spec.support.terrains")
local turn = require("shared.sim.turn")
local world = require("shared.sim.world")

local WIDE = 400
local BOTTOM = terrains.LIQUID + 4
local QUAKE_EVENTS = { quaked = true, shook = true, cracked = true }

local function forest(fields)
  fields = fields or {}
  return world.from_terrain({
    terrain = fields.terrain or terrains.flat(WIDE),
    liquid = terrains.LIQUID,
    liquid_kind = fields.kind or "water",
    seed = fields.seed or 1,
    wells = fields.wells,
    settings = { teams = 2, cats_per_team = fields.per_team or 2, wind_max = 0 },
    spawns = fields.spawns or {
      { team = 1, index = 1, x = 20, y = terrains.GROUND - 1 },
      { team = 1, index = 2, x = 40, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 360, y = terrains.GROUND - 1 },
      { team = 2, index = 2, x = 380, y = terrains.GROUND - 1 },
    },
  })
end

local function step(w)
  local inputs = nil
  if w.turn.state == "aiming" then
    inputs = { { team = w.turn.team, kind = "skip" } }
  end
  return world.step(w, inputs)
end

local function find(events, kind)
  for _, e in ipairs(events) do
    if e.type == kind then
      return e
    end
  end
  return nil
end

local function until_event(w, kind, limit)
  local seen = {}
  for _ = 1, limit or 20000 do
    local events = step(w)
    for _, e in ipairs(events) do
      if QUAKE_EVENTS[e.type] and e.type ~= kind then
        seen[#seen + 1] = e.type
      end
    end
    local e = find(events, kind)
    if e then
      return e, seen
    end
    if w.turn.state == "ended" then
      break
    end
  end
  error("no " .. kind .. " event")
end

local function through_quake(w)
  local start = w.tick
  local log = { shook = {}, cracked = {}, hurt = {}, moved = false }
  while w.turn.state == "quake" do
    for _, e in ipairs(world.step(w)) do
      if e.type == "shook" then
        log.shook[#log.shook + 1] = { w.tick - start, e.n }
      elseif e.type == "cracked" then
        log.cracked[#log.cracked + 1] = { w.tick - start, e.x, e.width }
      elseif e.type == "damaged" or e.type == "died" then
        log.hurt[#log.hurt + 1] = e.type
      end
    end
    for _, c in ipairs(w.cats) do
      if not cat.at_rest(c) then
        log.moved = true
      end
    end
  end
  log.ticks = w.tick - start
  return log
end

local function gap(a, b)
  return math.max(b.x - (a.x + a.width - 1), a.x - (b.x + b.width - 1))
end

local function crack_cells_air(w, crack)
  for y = 0, BOTTOM do
    local base = crack.x + quake.offset(crack, y)
    for x = base, base + crack.width - 1 do
      if terrain.solid(w.terrain, x, y) then
        return false, x .. "," .. y
      end
    end
  end
  return true
end

describe("🌍 the forest quake (§5.3)", function()
  it("🌍 uses §5.3's figures", function()
    assert.are.same({ 8, 3, 15, 192, 64, 704, 256 }, {
      rules.QUAKE_FROM,
      rules.QUAKE_SHAKES,
      rules.QUAKE_SHAKE_EVERY,
      rules.QUAKE_PUSH,
      rules.QUAKE_PUSH_STEP,
      rules.QUAKE_PUSH_MAX,
      rules.QUAKE_LIFT,
    })
    assert.are.same({ 4, 2, 4, 24, 8, 20, 80, 4, 1 }, {
      rules.CRACK_WIDTH,
      rules.CRACK_WIDEN,
      rules.CRACK_BELOW,
      rules.CRACK_DISTANCE,
      rules.CRACK_TRIES,
      rules.CRACK_ZONE_START_PERCENT,
      rules.CRACK_ZONE_END_PERCENT,
      rules.CRACK_ZIGZAG_EVERY,
      rules.CRACK_ZIGZAG_MAX,
    })
  end)

  it("🌍 grows stronger with every quake: P = 192 + 64 × n, capped at 704", function()
    assert.are.same({ 256, 320, 384, 704, 704, 704 }, {
      quake.strength(1),
      quake.strength(2),
      quake.strength(3),
      quake.strength(8),
      quake.strength(9),
      quake.strength(22),
    })
  end)

  it(
    "🌍 after the 8th forest round: 3 shakes 15 ticks apart, a crack, then a turn once all is still",
    function()
      local w = forest()
      local q, before = until_event(w, "quaked")
      assert.are.same({}, before)
      assert.are.same({ 8, 1, "quake" }, { w.rounds, q.n, w.turn.state })
      local played = w.turn.team
      local log = through_quake(w)
      assert.are.same({ { 1, 1 }, { 16, 1 }, { 31, 1 } }, log.shook)
      assert.are.equal(1, #w.cracks)
      local crack = w.cracks[1]
      assert.are.same({ { 1, crack.x, 4 } }, log.cracked)
      assert.are.same({}, log.hurt)
      assert.is_true(log.moved)
      assert.is_true(log.ticks > 31)
      assert.are.equal("turn_start", w.turn.state)
      assert.are.equal(3 - played, w.turn.team)
      for _, c in ipairs(w.cats) do
        assert.is_true(c.alive and cat.at_rest(c))
      end
      assert.is_true(crack_cells_air(w, crack))
      assert.are.equal(terrains.GROUND, crack.top)
    end
  )

  it(
    "🌍 the next quake is stronger, widens the open crack 1 px each side, opens another apart",
    function()
      local w = forest()
      until_event(w, "quaked")
      through_quake(w)
      local first = { x = w.cracks[1].x, width = w.cracks[1].width }
      local q = until_event(w, "quaked")
      assert.are.same({ 9, 2 }, { w.rounds, q.n })
      local log = through_quake(w)
      assert.are.same({ { 1, 2 }, { 16, 2 }, { 31, 2 } }, log.shook)
      assert.are.equal(2, #w.cracks)
      local widened, opened = w.cracks[1], w.cracks[2]
      assert.are.same({ first.x - 1, first.width + 2 }, { widened.x, widened.width })
      assert.are.same({ { 1, widened.x, 6 }, { 1, opened.x, 4 } }, log.cracked)
      assert.is_true(gap(widened, opened) > 24, "gap " .. gap(widened, opened))
      assert.is_true(crack_cells_air(w, widened))
      assert.is_true(crack_cells_air(w, opened))
    end
  )

  it("🌋 the volcano never quakes", function()
    local w = forest({
      kind = "lava",
      terrain = terrains.cliff(40),
      spawns = {
        { team = 1, index = 1, x = 20, y = terrains.GROUND - 41 },
        { team = 1, index = 2, x = 40, y = terrains.GROUND - 41 },
        { team = 2, index = 1, x = 60, y = terrains.GROUND - 41 },
        { team = 2, index = 2, x = 80, y = terrains.GROUND - 41 },
      },
    })
    for _ = 1, 20000 do
      for _, e in ipairs(step(w)) do
        assert.is_nil(QUAKE_EVENTS[e.type], e.type)
      end
      assert.are_not.equal("quake", w.turn.state)
      if w.rounds >= 10 then
        break
      end
    end
    assert.are.same({ 10, 0 }, { w.rounds, #w.cracks })
  end)

  it(
    "🌍 pushes each grounded living blob, in order, from the sim stream: sideways within ±P, 256 up",
    function()
      local well = terrains.well(8)
      local w = forest({
        terrain = well,
        per_team = 2,
        spawns = {
          { team = 1, index = 1, x = 20, y = terrains.GROUND - 1 },
          { team = 1, index = 2, x = 60, y = 40 },
          { team = 2, index = 1, x = 103, y = terrains.LIQUID + 6 },
          { team = 2, index = 2, x = 160, y = terrains.GROUND - 1 },
        },
      })
      local flying, drowned = w.cats[2], w.cats[3]
      assert.are.same({ false, true }, { flying.grounded, flying.alive })
      assert.is_false(drowned.alive)
      local vy = flying.vy
      local copy = { state = w.rng.sim.state, multiplier = w.rng.sim.multiplier }
      quake.shake(w, 3)
      local p = quake.strength(3)
      for _, id in ipairs({ 1, 4 }) do
        local c = w.cats[id]
        assert.are.same(
          { rng.range(copy, -p, p), -256, false },
          { c.vx, c.vy, c.grounded },
          "cat " .. id
        )
      end
      assert.are.equal(copy.state, w.rng.sim.state)
      assert.are.same({ 0, vy }, { flying.vx, flying.vy })
      assert.are.same({ type = "shook", n = 3 }, w.events[#w.events])
    end
  )

  it(
    "🌍 opens a 4 px crack from the surface to L + 4, zigzagging ≤ 1 px every 4 rows, ≤ 1 px off",
    function()
      local moved = false
      for seed = 1, 20 do
        local w = forest({ seed = seed })
        local fresh = terrains.flat(WIDE)
        local crack = quake.open(w, 200)
        assert.are.same({ 200, 4, terrains.GROUND }, { crack.x, crack.width, crack.top })
        assert.are.equal(fixed.div(BOTTOM - terrains.GROUND, 4) + 1, #crack.path)
        assert.are.equal(0, crack.path[1])
        for k = 2, #crack.path do
          assert.is_true(fixed.abs(crack.path[k] - crack.path[k - 1]) <= 1)
          assert.is_true(fixed.abs(crack.path[k]) <= 1)
          moved = moved or crack.path[k] ~= 0
        end
        local wrong = {}
        for y = 0, terrains.HEIGHT - 1 do
          local k = math.min(fixed.div(math.max(y - crack.top, 0), 4) + 1, #crack.path)
          if crack.path[k] ~= quake.offset(crack, y) then
            wrong[#wrong + 1] = "offset " .. y
          end
          local base = 200 + crack.path[k]
          for x = 0, WIDE - 1 do
            local inside = y <= BOTTOM and x >= base and x < base + 4
            local expected = terrain.solid(fresh, x, y) and not inside
            if expected ~= terrain.solid(w.terrain, x, y) and #wrong < 5 then
              wrong[#wrong + 1] = x .. "," .. y
            end
          end
        end
        assert.are.same({}, wrong, "seed " .. seed)
        assert.are.same(
          { type = "cracked", x = 200, width = 4, top = terrains.GROUND },
          w.events[#w.events]
        )
      end
      assert.is_true(moved)
    end
  )

  it(
    "🌍 carves a crack cell by cell into the terrain journal, solid cells only, row by row",
    function()
      local w = forest({ seed = 7 })
      local expected = terrains.flat(WIDE)
      local crack = quake.open(w, 150)
      for y = 0, BOTTOM do
        local base = crack.x + quake.offset(crack, y)
        for x = base, base + 3 do
          if terrain.solid(expected, x, y) then
            terrain.carve(expected, x, y, 0)
          end
        end
      end
      assert.are.same({ terrain.log_digest(expected) }, { terrain.log_digest(w.terrain) })
      assert.are.same(expected.cells, w.terrain.cells)
    end
  )

  it("🌍 widens a crack by 1 px on each side, each new edge from its own surface", function()
    local w = forest({
      terrain = terrains.stairs(10),
      per_team = 1,
      spawns = {
        { team = 1, index = 1, x = 20, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 180, y = terrains.GROUND - 11 },
      },
    })
    local crack = quake.open(w, 96)
    assert.are.same({ terrains.GROUND, 0 }, { crack.top, crack.path[1] })
    assert.is_true(terrain.solid(w.terrain, 100, terrains.GROUND - 10))
    local first = #w.events + 1
    quake.crack(w)
    assert.are.same({ 95, 6 }, { crack.x, crack.width })
    assert.are.same(
      { type = "cracked", x = 95, width = 6, top = terrains.GROUND - 10 },
      w.events[first]
    )
    for y = terrains.GROUND - 10, terrains.GROUND - 1 do
      assert.is_false(terrain.solid(w.terrain, 100, y), "100," .. y)
      assert.is_true(terrain.solid(w.terrain, 101, y), "101," .. y)
    end
    assert.is_false(terrain.solid(w.terrain, 95, terrains.GROUND))
    assert.is_true(terrain.solid(w.terrain, 94, terrains.GROUND))
    assert.is_true(crack_cells_air(w, crack))
  end)

  it("🌍 widening edges from a higher left side, or both lower, report the right top", function()
    local left = terrains.flat()
    local pillar = terrains.flat()
    for x = 0, 199 do
      for y = terrains.GROUND - 10, terrains.GROUND - 1 do
        if x <= 95 then
          terrain.set(left, x, y, terrain.SOIL)
        end
        if x >= 96 and x <= 99 then
          terrain.set(pillar, x, y, terrain.SOIL)
        end
      end
    end
    local tops = {}
    for _, t in ipairs({ left, pillar }) do
      local w = forest({
        terrain = t,
        per_team = 1,
        spawns = {
          { team = 1, index = 1, x = 20, y = terrains.GROUND - 11 },
          { team = 2, index = 1, x = 180, y = terrains.GROUND - 1 },
        },
      })
      local crack = quake.open(w, 96)
      local first = #w.events + 1
      quake.crack(w)
      tops[#tops + 1] = { crack.top, w.events[first].top }
      assert.is_false(terrain.solid(w.terrain, 95, terrains.GROUND - 10))
    end
    assert.are.same({
      { terrains.GROUND, terrains.GROUND - 10 },
      { terrains.GROUND - 10, terrains.GROUND - 10 },
    }, tops)
  end)

  it(
    "🌍 a blob astride a fresh crack stays on its edges, falls in once it widens, and drowns",
    function()
      local w = forest({
        terrain = terrains.flat(),
        per_team = 1,
        spawns = {
          { team = 1, index = 1, x = 98, y = terrains.GROUND - 1 },
          { team = 2, index = 1, x = 20, y = terrains.GROUND - 1 },
        },
      })
      local blob = w.cats[1]
      quake.open(w, 96)
      for _ = 1, 20 do
        world.step(w)
      end
      assert.is_true(blob.alive and blob.grounded)
      assert.are.equal(terrains.GROUND - 1, select(2, cat.pixel(blob)))
      quake.crack(w)
      for _ = 1, 20 do
        world.step(w)
      end
      assert.is_true(select(2, cat.pixel(blob)) > terrains.GROUND - 1)
      local died = nil
      for _ = 1, 3 do
        if blob.alive then
          quake.crack(w)
        end
        for _ = 1, 60 do
          for _, e in ipairs(world.step(w)) do
            if e.type == "died" and e.cat == blob.id then
              died = e
            end
          end
        end
      end
      assert.are.same({ "liquid", false }, { died and died.cause, blob.alive })
      local px = cat.pixel(blob)
      assert.is_true(px >= 93 and px <= 102, "x " .. px)
    end
  )

  it(
    "🌍 opens the new crack in the central 60 %, more than 24 px from every well and crack",
    function()
      local opened = 0
      for seed = 1, 60 do
        local w = forest({ seed = seed, wells = { { x = 150, width = 10 } } })
        for _ = 1, 6 do
          local count = #w.cracks
          quake.crack(w)
          if #w.cracks > count then
            opened = opened + 1
            local c = w.cracks[#w.cracks]
            assert.is_true(c.x >= 80 and c.x + c.width <= 320, "x " .. c.x)
            assert.is_true(gap(c, w.wells[1]) > 24, "well gap " .. gap(c, w.wells[1]))
            for i = 1, #w.cracks - 1 do
              assert.is_true(gap(c, w.cracks[i]) > 24, "crack gap " .. gap(c, w.cracks[i]))
            end
          end
        end
      end
      assert.is_true(opened > 120)
    end
  )

  it("🌍 gives up a new crack after 8 draws that all fall too close", function()
    local w = forest({
      terrain = terrains.flat(),
      per_team = 1,
      wells = { { x = 40, width = 10 }, { x = 100, width = 10 }, { x = 150, width = 10 } },
      spawns = {
        { team = 1, index = 1, x = 20, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 180, y = terrains.GROUND - 1 },
      },
    })
    local copy = { state = w.rng.sim.state, multiplier = w.rng.sim.multiplier }
    local log = { terrain.log_digest(w.terrain) }
    quake.crack(w)
    for _ = 1, 8 do
      rng.next(copy)
    end
    assert.are.same({ 0, copy.state }, { #w.cracks, w.rng.sim.state })
    assert.are.same(log, { terrain.log_digest(w.terrain) })
  end)

  it(
    "🌍 leaves the game to the round limit: no quake once the game ends at a round's end",
    function()
      local w = forest({
        terrain = terrains.pockets({ { 10, 100 }, { 190, 100 } }),
        per_team = 1,
        spawns = {
          { team = 1, index = 1, x = 10, y = 100 },
          { team = 2, index = 1, x = 190, y = 100 },
        },
      })
      local quakes = 0
      for _ = 1, 40000 do
        for _, e in ipairs(step(w)) do
          if e.type == "quaked" then
            quakes = quakes + 1
            assert.are.equal(w.rounds - 7, e.n)
          end
        end
        if w.turn.state == "ended" then
          break
        end
      end
      assert.are.same({ "ended", 30, 22 }, { w.turn.state, w.rounds, quakes })
    end
  )
end)

describe("⏱️ the end of a quake (§5.3, §5.6)", function()
  it(
    "⏱️ lasts 300 ticks at most: whatever still moves is set down, and the next turn starts",
    function()
      local w = forest({ terrain = terrains.ceiling(60, WIDE) })
      until_event(w, "quaked")
      local start = w.tick
      local swinger = w.cats[1]
      assert.is_true(cat.grapple(swinger, { terrain = w.terrain, angle = 256, events = w.events }))
      assert.is_true(swinger.hanging)
      local ended_at, frozen = nil, nil
      while ended_at == nil and w.tick - start < 400 do
        world.step(w)
        if w.turn.state ~= "quake" then
          ended_at, frozen = w.tick - start, { swinger.vx, swinger.vy, swinger.grounded }
        end
      end
      assert.are.same({ 300, { 0, 0, true }, "turn_start" }, { ended_at, frozen, w.turn.state })
    end
  )

  it(
    "⏱️ a blob the quake hurts to death dies once all is still, counts for no team, never plays",
    function()
      local w = forest({
        terrain = terrains.cliff(60),
        spawns = {
          { team = 1, index = 1, x = 20, y = terrains.GROUND - 61 },
          { team = 1, index = 2, x = 97, y = terrains.GROUND - 61 },
          { team = 2, index = 1, x = 40, y = terrains.GROUND - 61 },
          { team = 2, index = 2, x = 180, y = terrains.GROUND - 1 },
        },
      })
      local doomed = w.cats[2]
      doomed.hp = 10
      until_event(w, "quaked")
      local died, fell = nil, false
      while w.turn.state == "quake" do
        local acting = turn.acting_team(w)
        for _, e in ipairs(world.step(w)) do
          if e.type == "damaged" and e.cat == doomed.id then
            fell = e.cause == "fall" and e.amount >= 10
          elseif e.type == "died" and e.cat == doomed.id then
            died = { e.cause, acting, w.turn.state }
          end
        end
      end
      assert.is_true(fell)
      assert.are.same({ "hp", 0, "turn_start" }, died)
      assert.are_not.equal(doomed.id, w.turn.cat)
      for _ = 1, 3000 do
        assert.are_not.equal(doomed.id, w.turn.cat)
        step(w)
      end
    end
  )
end)

describe("⏱️ the quake in the turn table (§5.6)", function()
  it("⏱️ goes from turn_end to quake to turn_start, never from quake to aiming", function()
    local w = forest()
    until_event(w, "quaked")
    assert.are.equal("quake", w.turn.state)
    assert.has_error(function()
      turn.transition(w, "aiming")
    end)
    assert.is_false(turn.accepts(w, "move"))
    assert.is_false(turn.accepts(w, "fire"))
    assert.is_false(turn.accepts(w, "skip"))
  end)

  it("⏱️ counts the quake for no team (§6.4)", function()
    local w = forest()
    assert.are.equal(w.turn.team, turn.acting_team(w))
    until_event(w, "quaked")
    assert.are.equal(0, turn.acting_team(w))
    through_quake(w)
    assert.are.equal(w.turn.team, turn.acting_team(w))
  end)
end)

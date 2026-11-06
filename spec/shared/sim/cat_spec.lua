local cat = require("shared.sim.cat")
local fixed = require("shared.sim.fixed")
local rules = require("shared.sim.rules")
local terrain = require("shared.sim.terrain")
local terrains = require("spec.support.terrains")

local function standing(t, px)
  local py = 0
  while not terrain.solid(t, px, py + 1) do
    py = py + 1
  end
  local c = cat.new({ id = 1, team = 1, index = 1, px = px, py = py })
  local events = {}
  cat.step(c, t, terrains.LIQUID, events)
  assert.is_true(c.grounded)
  return c
end

local function run(c, t, ticks)
  local events = {}
  for _ = 1, ticks do
    cat.step(c, t, terrains.LIQUID, events)
  end
  return events
end

local function count(events, kind)
  local n = 0
  for _, e in ipairs(events) do
    if e.type == kind then
      n = n + 1
    end
  end
  return n
end

describe("🐈 cat movement", function()
  it("🐈 climbs a 3 px step and stops at a 4 px one", function()
    local low = standing(terrains.stairs(3), 90)
    cat.set_walk(low, 1)
    run(low, terrains.stairs(3), 60)
    local px, py = cat.pixel(low)
    assert.is_true(px > 105)
    assert.are.equal(terrains.GROUND - 4, py)

    local t = terrains.stairs(4)
    local high = standing(t, 90)
    cat.set_walk(high, 1)
    run(high, t, 60)
    px, py = cat.pixel(high)
    assert.are.equal(97, px)
    assert.are.equal(terrains.GROUND - 1, py)
  end)

  it("🐈 walks 1 px every 2 ticks", function()
    local t = terrains.flat()
    local c = standing(t, 50)
    cat.set_walk(c, -1)
    run(c, t, 20)
    assert.are.equal(40, (cat.pixel(c)))
  end)

  it("🐈 follows a 3 px drop without falling", function()
    local t = terrains.cliff(3)
    local c = standing(t, 90)
    local _, start_y = cat.pixel(c)
    assert.are.equal(terrains.GROUND - 4, start_y)
    cat.set_walk(c, 1)
    local events = run(c, t, 40)
    assert.are.equal(0, count(events, "landed"))
    local _, py = cat.pixel(c)
    assert.are.equal(terrains.GROUND - 1, py)
  end)

  it("🐈 falls off a higher drop, hurt only beyond about 40 px", function()
    local small = terrains.cliff(36)
    local c = standing(small, 90)
    cat.set_walk(c, 1)
    local events = run(c, small, 80)
    assert.are.equal(1, count(events, "landed"))
    assert.are.equal(0, count(events, "damaged"))
    assert.is_false(c.hurt)

    local big = terrains.cliff(60)
    local d = standing(big, 90)
    cat.set_walk(d, 1)
    events = run(d, big, 80)
    assert.are.equal(1, count(events, "damaged"))
    assert.is_true(d.hp >= 80 and d.hp <= 90, "hp " .. d.hp)
    assert.is_true(d.hurt)
  end)

  it("🐈 a jump that lands 28 px lower does not hurt", function()
    local t = terrains.cliff(28)
    local c = standing(t, 96)
    assert.is_true(cat.jump(c, 1))
    local events = run(c, t, 80)
    assert.are.equal(1, count(events, "landed"))
    assert.are.equal(0, count(events, "damaged"))
    assert.is_false(c.hurt)
    assert.are.equal(100, c.hp)
  end)

  it("🐈 fall damage begins at 1024 FP/tick, 20 HP per 256 more (§5.4)", function()
    assert.are.same(
      { safe = 1024, per = 20 },
      { safe = rules.FALL_SAFE_SPEED, per = rules.FALL_DAMAGE_PER_256 }
    )
  end)

  it("🐈 is stopped by a one-pixel wall", function()
    local t = terrains.wall(1, 10)
    local c = standing(t, 100)
    cat.set_walk(c, 1)
    run(c, t, 100)
    assert.are.equal(117, (cat.pixel(c)))
  end)

  it("🐈 jumps about 14 px high and 24 px far", function()
    local t = terrains.flat()
    local c = standing(t, 50)
    assert.is_true(cat.jump(c, 1))
    local top = terrains.GROUND - 1
    local events = {}
    for _ = 1, 60 do
      cat.step(c, t, terrains.LIQUID, events)
      local _, py = cat.pixel(c)
      top = math.min(top, py)
    end
    local px = cat.pixel(c)
    assert.is_true(terrains.GROUND - 1 - top >= 13 and terrains.GROUND - 1 - top <= 15)
    assert.is_true(px - 50 >= 22 and px - 50 <= 26, "landed at " .. px)
    assert.is_true(c.grounded)
    assert.are.equal(0, c.vx)
    assert.is_true(cat.at_rest(c))
  end)

  local function jump_path(from)
    local t = terrains.flat()
    local c = standing(t, from)
    cat.jump(c, 1)
    local path = {}
    for _ = 1, 60 do
      cat.step(c, t, terrains.LIQUID, {})
      local px, py = cat.pixel(c)
      path[px] = path[px] or {}
      path[px].py = py
    end
    return path
  end

  local function jump_onto_ledge(overlap)
    local x = 70
    local feet = jump_path(50)[x].py
    local top = feet - overlap + 1
    local t = terrains.ledge(x + 3, top)
    local c = standing(t, 50)
    cat.jump(c, 1)
    run(c, t, 90)
    local px, py = cat.pixel(c)
    return px, py, top
  end

  it("🐈 lets a jump whose feet graze a ledge's edge by up to 2 px land on the ledge", function()
    for overlap = 1, rules.AIR_NUDGE do
      local px, py, top = jump_onto_ledge(overlap)
      assert.are.equal(top - 1, py, overlap .. " px: feet at " .. py)
      assert.is_true(px >= 71, overlap .. " px: stopped at " .. px)
    end
  end)

  it("🐈 but a ledge more than 2 px above its feet still stops the jump", function()
    local px, py = jump_onto_ledge(rules.AIR_NUDGE + 1)
    assert.are.equal(terrains.GROUND - 1, py)
    assert.is_true(px <= 70, "went on to " .. px)
  end)

  local function rise_under(columns)
    local t0 = terrains.flat()
    local c0 = standing(t0, 100)
    local _, feet = cat.pixel(c0)
    local head = feet - rules.CAT_HEIGHT + 1
    local t = terrains.overhang(100 + 3 - columns, head - 5)
    local c = cat.new({ id = 1, team = 1, index = 1, px = 100, py = feet })
    cat.step(c, t, terrains.LIQUID, {})
    assert.is_true(c.grounded)
    cat.push(c, 0, rules.JUMP_VY)
    local top = head
    for _ = 1, 60 do
      cat.step(c, t, terrains.LIQUID, {})
      local _, py = cat.pixel(c)
      top = math.min(top, py - rules.CAT_HEIGHT + 1)
    end
    return top, head - 5
  end

  it("🐈 slides past a ceiling's corner that its head overlaps by up to 2 px", function()
    for columns = 1, rules.AIR_NUDGE do
      local top, ceiling = rise_under(columns)
      assert.is_true(top < ceiling - 2, columns .. " columns: head stopped at " .. top)
    end
    local top, ceiling = rise_under(rules.AIR_NUDGE + 1)
    assert.are.equal(ceiling + 1, top)
  end)

  local function without_tolerance(body)
    local nudge = rules.AIR_NUDGE
    rules.AIR_NUDGE = 0
    local ok, a, b = pcall(body)
    rules.AIR_NUDGE = nudge
    assert(ok, a)
    return a, b
  end

  local function highest(t, px, launch)
    local c = standing(t, px)
    launch(c)
    local top = select(2, cat.pixel(c))
    for _ = 1, 120 do
      cat.step(c, t, terrains.LIQUID, {})
      top = math.min(top, (select(2, cat.pixel(c))))
    end
    return top, (cat.pixel(c))
  end

  it(
    "🐈 grants the 2 px once per flight, so stairs and slopes are not climbed in the air",
    function()
      local cases = {
        {
          terrains.staircase(66, 3, 3),
          60,
          function(c)
            cat.jump(c, 1)
          end,
        },
        {
          terrains.staircase(66, 3, 2),
          60,
          function(c)
            cat.jump(c, 1)
          end,
        },
        {
          terrains.staircase(70, 1, 1),
          60,
          function(c)
            cat.push(c, 3072, -200)
          end,
        },
        {
          terrains.staircase(70, 2, 1),
          60,
          function(c)
            cat.push(c, 2048, -600)
          end,
        },
      }
      for i, case in ipairs(cases) do
        local t, px, launch = case[1], case[2], case[3]
        local before = without_tolerance(function()
          return highest(t, px, launch)
        end)
        local top = highest(t, px, launch)
        assert.is_true(
          top >= before - rules.AIR_NUDGE,
          "case " .. i .. ": " .. before .. " → " .. top
        )
      end
    end
  )

  local function glide_under(overlap)
    local path = {}
    local free = terrains.flat()
    local c = standing(free, 40)
    cat.push(c, 512, -500)
    for _ = 1, 40 do
      cat.step(c, free, terrains.LIQUID, {})
      local px, py = cat.pixel(c)
      path[px] = path[px] or py
    end
    local x = 61
    local head = path[x - 3] - rules.CAT_HEIGHT + 1
    local t = terrains.overhang(x, head - 1 + overlap)
    local d = standing(t, 40)
    cat.push(d, 512, -500)
    run(d, t, 40)
    return (cat.pixel(d)), x
  end

  it("🐈 slips under an overhang's edge that its head grazes by up to 2 px", function()
    for overlap = 1, rules.AIR_NUDGE do
      local px, x = glide_under(overlap)
      assert.is_true(px > x, overlap .. " px: stopped at " .. px)
    end
    local px, x = glide_under(rules.AIR_NUDGE + 1)
    assert.is_true(px < x, "went under to " .. px)
  end)

  local function fling(t, px, vx, vy, ticks)
    local c = standing(t, px)
    cat.push(c, vx, vy)
    local trace, events = {}, {}
    for i = 1, ticks or 200 do
      local before = { vx = c.vx, vy = c.vy, x = c.x, grounded = c.grounded }
      local from = #events
      cat.step(c, t, terrains.LIQUID, events)
      local happened = {}
      for k = from + 1, #events do
        happened[events[k].type] = true
      end
      local at_x, at_y = cat.pixel(c)
      trace[i] = {
        before = before,
        after = { vx = c.vx, vy = c.vy, x = c.x, px = at_x, py = at_y, grounded = c.grounded },
        events = happened,
      }
    end
    return c, trace, events
  end

  local function first(trace, test)
    for _, step in ipairs(trace) do
      if test(step) then
        return step
      end
    end
    return nil
  end

  it("🐈 uses §5.4's figures for a thrown blob", function()
    assert.are.same({
      thrown = 384,
      wall = 50,
      ground = 30,
      rebound_from = 700,
      keep = 70,
      skid = 50,
      friction = 128,
    }, {
      thrown = rules.THROWN_VX,
      wall = rules.WALL_BOUNCE,
      ground = rules.GROUND_BOUNCE,
      rebound_from = rules.BOUNCE_VY,
      keep = rules.BOUNCE_KEEP_VX,
      skid = rules.SLIDE_KEEP,
      friction = rules.SLIDE_FRICTION,
    })
  end)

  it(
    "🐈 thrown against a wall, bounces back at half speed, from any throw faster than a jump",
    function()
      for _, speed in ipairs({ 1536, 512 }) do
        local t = terrains.wall(3, 40)
        local c, trace = fling(t, 100, speed, -600, 120)
        local back = first(trace, function(step)
          return step.after.vx < 0
        end)
        assert.are.equal(-fixed.round_div(speed * rules.WALL_BOUNCE, 100), back.after.vx)
        assert.is_true(cat.pixel(c) < 110, speed .. ": stayed at " .. cat.pixel(c))
      end
      local t = terrains.wall(3, 40)
      local j = standing(t, 110)
      cat.jump(j, 1)
      run(j, t, 60)
      assert.are.equal(0, j.vx)
      assert.is_true(cat.pixel(j) >= 110)
    end
  )

  it(
    "🐈 rebounds with 30 % of its fall and 70 % of its run, lands at half speed, skids to rest",
    function()
      local c, trace = fling(terrains.flat(400), 60, 1536, -900, 300)
      local rebound = first(trace, function(step)
        return step.events.rebounded
      end)
      local landing = first(trace, function(step)
        return step.events.landed
      end)
      local skid = first(trace, function(step)
        return step.before.grounded
          and step.after.grounded
          and step.before.vx > rules.SLIDE_FRICTION
      end)
      local impact = rebound.before.vy + rules.GRAVITY
      assert.are.equal(-fixed.round_div(impact * rules.GROUND_BOUNCE, 100), rebound.after.vy)
      assert.are.equal(
        fixed.round_div(rebound.before.vx * rules.BOUNCE_KEEP_VX, 100),
        rebound.after.vx
      )
      assert.are.equal(fixed.round_div(landing.before.vx * rules.SLIDE_KEEP, 100), landing.after.vx)
      assert.are.equal(skid.before.vx - rules.SLIDE_FRICTION, skid.after.vx)
      assert.is_true(skid.after.x > skid.before.x)
      assert.is_true(cat.at_rest(c))
    end
  )

  it("🐈 rebounds even when a tick ends right on the ground", function()
    for _, throw in ipairs({ { 800, -1400 }, { 1536, -900 }, { 640, -1200 } }) do
      local _, trace = fling(terrains.flat(400), 60, throw[1], throw[2], 300)
      local touch = first(trace, function(step)
        return step.events.rebounded or step.events.landed
      end)
      assert.is_true(touch.events.rebounded, throw[1] .. ", " .. throw[2])
    end
  end)

  it("🐈 a throw to the left mirrors a throw to the right, tick by tick", function()
    local t = terrains.flat(400)
    local _, right = fling(t, 150, 1536, -900, 200)
    local _, left = fling(t, 250, -1536, -900, 200)
    for i = 1, 200 do
      assert.are.equal(-right[i].after.vx, left[i].after.vx, "tick " .. i)
      assert.are.equal(right[i].after.vy, left[i].after.vy, "tick " .. i)
    end
  end)

  it("🐈 a thrown blob that touches down softly lands and skids, without a rebound", function()
    local _, _, events = fling(terrains.flat(400), 60, 1536, -300, 200)
    assert.are.equal(0, count(events, "rebounded"))
    assert.are.equal(1, count(events, "landed"))
  end)

  it("🐈 a skid stops against a wall and comes to rest", function()
    local c, trace = fling(terrains.wall(3, 40), 106, 1024, -64, 200)
    assert.is_not_nil(first(trace, function(step)
      return step.before.grounded and step.after.vx > 0
    end))
    assert.is_true(cat.at_rest(c))
    assert.is_true(cat.pixel(c) <= 117)
  end)

  it("🐈 a skid climbs a 3 px step", function()
    local _, free = fling(terrains.flat(400), 60, 1024, -64, 200)
    local landing = first(free, function(step)
      return step.events.landed
    end)
    local x = landing.after.px + 4
    local c = fling(terrains.staircase(x, 3, 400), 60, 1024, -64, 200)
    local px, py = cat.pixel(c)
    assert.are.equal(terrains.GROUND - 4, py, "stayed below at " .. px)
    assert.is_true(px >= x - 2)
  end)

  it("🐈 skids off a cliff's edge keeping its speed, moving once per tick", function()
    local c, trace = fling(terrains.cliff(20), 80, 2048, -64, 300)
    local takeoff = first(trace, function(step)
      return step.before.grounded and not step.after.grounded
    end)
    assert.is_not_nil(takeoff)
    assert.is_true(takeoff.after.vx > 0)
    assert.is_true(takeoff.after.x - takeoff.before.x <= takeoff.before.vx)
    assert.are.equal(terrains.GROUND - 1, select(2, cat.pixel(c)))
  end)

  it("🐈 takes fall damage from a hard rebound, as from a landing", function()
    local _, _, events = fling(terrains.cliff(40), 90, 512, -600, 300)
    local fall = 0
    for _, e in ipairs(events) do
      if e.type == "damaged" and e.cause == "fall" then
        fall = fall + 1
      end
    end
    assert.is_true(fall >= 1)
    assert.is_true(count(events, "rebounded") >= 1)
  end)

  it("🐈 keeps walking after a jump while the direction is still held", function()
    local t = terrains.flat()
    local c = standing(t, 50)
    cat.set_walk(c, 1)
    cat.jump(c, 1)
    run(c, t, 40)
    local landed_at = cat.pixel(c)
    run(c, t, 20)
    assert.are.equal(landed_at + 10, (cat.pixel(c)))
  end)

  it("🐈 cannot jump in the air", function()
    local t = terrains.flat()
    local c = standing(t, 50)
    cat.jump(c, 1)
    cat.step(c, t, terrains.LIQUID, {})
    assert.is_false(cat.jump(c, -1))
  end)

  it("🐈 falls when the ground under it is carved away", function()
    local t = terrains.flat()
    local c = standing(t, 50)
    terrain.carve(t, 50, terrains.GROUND + 4, 6)
    local events = run(c, t, 30)
    assert.are.equal(1, count(events, "landed"))
    local _, py = cat.pixel(c)
    assert.is_true(py > terrains.GROUND - 1)
  end)

  it("🐈 drowns when it walks off the shore into the liquid", function()
    local t = terrains.shore()
    local c = standing(t, 90)
    cat.set_walk(c, 1)
    local events = run(c, t, 120)
    assert.is_false(c.alive)
    assert.are.equal(1, count(events, "died"))
    assert.are.equal("liquid", events[#events].cause)
  end)

  it("🐈 drowns the moment its centre leaves the map by a side", function()
    local t = terrains.flat()
    local c = standing(t, 4)
    cat.set_walk(c, -1)
    local events = {}
    for _ = 1, 40 do
      cat.step(c, t, terrains.LIQUID, events)
      if not c.alive then
        break
      end
    end
    assert.is_false(c.alive)
    local px, py = cat.pixel(c)
    assert.are.equal(-1, px)
    assert.are.equal(terrains.GROUND - 1, py)
  end)

  it("🐈 drowns when the centre of its box, not its feet, goes under the liquid", function()
    local function floor_at(row)
      local t = terrain.new(terrains.WIDTH, terrains.HEIGHT)
      for y = row, terrains.HEIGHT - 1 do
        for x = 0, terrains.WIDTH - 1 do
          terrain.set(t, x, y, terrain.SOIL)
        end
      end
      return t
    end
    local shallow = floor_at(terrains.LIQUID + 3)
    local alive = cat.new({ id = 1, team = 1, index = 1, px = 50, py = terrains.LIQUID + 2 })
    cat.step(alive, shallow, terrains.LIQUID, {})
    assert.is_true(alive.alive)
    local deep = floor_at(terrains.LIQUID + 4)
    local dead = cat.new({ id = 2, team = 1, index = 2, px = 50, py = terrains.LIQUID + 3 })
    cat.step(dead, deep, terrains.LIQUID, {})
    assert.is_false(dead.alive)
  end)

  it("🐈 flies when pushed and lands at rest", function()
    local t = terrains.flat()
    local c = standing(t, 50)
    cat.push(c, 512, -1024)
    local events = run(c, t, 90)
    assert.is_true(c.grounded)
    assert.are.equal(1, count(events, "landed"))
    assert.is_true(cat.pixel(c) > 60)
    assert.are.equal(0, fixed.mod(c.y, fixed.FP))
    assert.are.same({ 0, 0 }, { c.vx, c.vy })
    assert.is_true(cat.at_rest(c))
  end)

  it("🐈 clamps its speed on both axes", function()
    local t = terrains.flat()
    local c = standing(t, 100)
    cat.push(c, 20000, -20000)
    cat.step(c, t, terrains.LIQUID, {})
    assert.is_true(c.vx <= 3072 and c.vy >= -3072)
  end)

  it("🐈 is not thrown through a one-pixel wall, however fast", function()
    local t = terrains.wall(1, 40)
    local c = standing(t, 100)
    cat.push(c, 6000, -64)
    run(c, t, 30)
    assert.is_true(cat.pixel(c) <= 117, "went through to " .. cat.pixel(c))
  end)

  it("🐈 takes damage through one shared path", function()
    local c = cat.new({ id = 3, team = 1, index = 1, px = 10, py = 10 })
    local events = {}
    cat.damage(c, { amount = 12, cause = "explosion" }, events)
    cat.damage(c, { amount = 0, cause = "explosion" }, events)
    assert.are.equal(88, c.hp)
    assert.is_true(c.hurt)
    assert.are.same({ { type = "damaged", cat = 3, amount = 12, cause = "explosion" } }, events)
  end)
end)

describe("🐈 the movement gauge (§5.4)", function()
  local world = require("shared.sim.world")

  local function field(t, at)
    t = t or terrains.flat(400)
    at = at or { x = 100, y = terrains.GROUND - 1 }
    local w = world.from_terrain({
      terrain = t,
      liquid = terrains.LIQUID,
      settings = { teams = 2, cats_per_team = 1, wind_max = 0 },
      spawns = {
        { team = 1, index = 1, x = at.x, y = at.y },
        { team = 2, index = 1, x = t.width - 20, y = terrains.GROUND - 1 },
      },
    })
    while w.turn.state ~= "aiming" do
      world.step(w)
    end
    return w, w.cats[w.turn.cat]
  end

  local function walk_down_to(w, c, left)
    world.step(w, { { team = w.turn.team, kind = "move", direction = 1 } })
    for _ = 1, 400 do
      if c.gauge <= left then
        break
      end
      world.step(w)
    end
    world.step(w, { { team = w.turn.team, kind = "move", direction = 0 } })
    assert.are.equal(left, c.gauge)
  end

  local function walk_until_still(w, c, direction)
    world.step(w, { { team = w.turn.team, kind = "move", direction = direction } })
    local last, still = c.x, 0
    while still < 20 do
      world.step(w)
      still = c.x == last and still + 1 or 0
      last = c.x
    end
  end

  it("🐈 uses §5.4's figures for the gauge", function()
    assert.are.same(
      { full = 3000, walk = 20, jump = 200 },
      { full = rules.GAUGE, walk = rules.GAUGE_WALK, jump = rules.GAUGE_JUMP }
    )
  end)

  it(
    "🐈 an empty gauge stops the walk to the pixel and refuses the jump, and the cat still fires",
    function()
      local w, c = field()
      assert.are.equal(3000, c.gauge)
      local from = cat.pixel(c)
      walk_until_still(w, c, 1)
      assert.are.equal(from + 150, (cat.pixel(c)))
      assert.are.equal(0, c.gauge)
      assert.are.equal("aiming", w.turn.state)
      local _, feet = cat.pixel(c)
      world.step(w, { { team = w.turn.team, kind = "jump", direction = 1 } })
      world.step(w)
      assert.is_true(c.grounded)
      assert.are.equal(feet, select(2, cat.pixel(c)))
      local events = world.step(w, {
        { team = w.turn.team, kind = "fire", weapon = "bazooka", angle = 200, power = 40 },
      })
      assert.are.equal("fired", events[1].type)
      assert.are.equal("flight", w.turn.state)
    end
  )

  it("🐈 a jump costs 200, and a jump the gauge just covers still happens", function()
    local w, c = field()
    world.step(w, { { team = w.turn.team, kind = "jump", direction = -1 } })
    assert.is_false(c.grounded)
    assert.are.equal(2800, c.gauge)

    w, c = field()
    walk_down_to(w, c, 200)
    world.step(w, { { team = w.turn.team, kind = "jump", direction = 1 } })
    assert.is_false(c.grounded)
    assert.are.equal(0, c.gauge)
  end)

  it("🐈 a jump the gauge does not cover is refused, not paid for", function()
    local w, c = field()
    walk_down_to(w, c, 180)
    local _, feet = cat.pixel(c)
    world.step(w, { { team = w.turn.team, kind = "jump", direction = 1 } })
    world.step(w)
    assert.is_true(c.grounded)
    assert.are.equal(feet, select(2, cat.pixel(c)))
    assert.are.equal(180, c.gauge)
  end)

  it("🐈 pressing jump in the air costs nothing", function()
    local w, c = field()
    world.step(w, { { team = w.turn.team, kind = "jump", direction = 1 } })
    assert.are.equal(2800, c.gauge)
    world.step(w, { { team = w.turn.team, kind = "jump", direction = 1 } })
    assert.is_false(c.grounded)
    assert.are.equal(2800, c.gauge)
  end)

  it("🐈 the step that walks off a ledge costs 20 like any other", function()
    local w, c = field(terrains.cliff(20), { x = 90, y = terrains.GROUND - 21 })
    local from = cat.pixel(c)
    world.step(w, { { team = w.turn.team, kind = "move", direction = 1 } })
    for _ = 1, 400 do
      if not c.grounded then
        break
      end
      world.step(w)
    end
    assert.is_false(c.grounded)
    assert.are.equal(103, (cat.pixel(c)))
    assert.are.equal(3000 - 20 * (103 - from), c.gauge)
  end)

  it("🐈 a step the terrain blocks costs nothing", function()
    local t = terrains.wall(3, 40)
    local w, c = field(t)
    local from = cat.pixel(c)
    walk_until_still(w, c, 1)
    local walked = cat.pixel(c) - from
    assert.is_true(walked > 0 and walked < 20, "walked " .. walked)
    assert.are.equal(3000 - 20 * walked, c.gauge)
  end)

  it("🐈 the gauge is full again from the start of the cat's next turn", function()
    local w, c = field()
    local id = c.id
    walk_until_still(w, c, 1)
    assert.are.equal(0, c.gauge)
    world.step(w, { { team = w.turn.team, kind = "skip" } })
    local starts = 0
    for _ = 1, 2000 do
      local events
      if w.turn.state == "aiming" then
        events = world.step(w, { { team = w.turn.team, kind = "skip" } })
      else
        events = world.step(w)
      end
      for _, e in ipairs(events) do
        if e.type == "turn_started" and e.cat == id then
          starts = starts + 1
        end
      end
      if starts > 0 then
        break
      end
    end
    assert.are.equal(1, starts)
    assert.are.equal("turn_start", w.turn.state)
    assert.are.equal(3000, w.cats[id].gauge)
  end)
end)

describe("🐙 the tentacle (§5.4, §8.2)", function()
  local world = require("shared.sim.world")

  local WIDTH = 400
  local CEILING = 40

  local function hall(fields)
    fields = fields or {}
    local x = fields.x or 150
    local t = fields.terrain or terrains.ceiling(CEILING, WIDTH)
    local w = world.from_terrain({
      terrain = t,
      liquid = terrains.LIQUID,
      settings = { teams = 2, cats_per_team = 1, wind_max = 0 },
      spawns = {
        { team = 1, index = 1, x = x, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = t.width - x, y = terrains.GROUND - 1 },
      },
    })
    while w.turn.state ~= "aiming" do
      world.step(w)
    end
    return w, w.cats[w.turn.cat]
  end

  local function send(w, input)
    input.team = w.turn.team
    return world.step(w, { input })
  end

  local function throw(w, angle)
    return send(w, { kind = "fire", weapon = "tentacle", angle = angle, power = 50 })
  end

  local function find(events, kind)
    for _, e in ipairs(events) do
      if e.type == kind then
        return e
      end
    end
    return nil
  end

  local function drop(c)
    return c.y - c.anchor_y * 256
  end

  it("🐙 uses §5.4's figures for the tentacle", function()
    assert.are.same({
      range = 120,
      throw = 300,
      throw_in_the_air = 100,
      hang = 3,
      rope_min = 4,
      rope_max = 120,
      climb = 256,
      push = 64,
      bounce = 90,
    }, {
      range = rules.TENTACLE_RANGE,
      throw = rules.GAUGE_TENTACLE,
      throw_in_the_air = rules.GAUGE_TENTACLE_AIR,
      hang = rules.GAUGE_HANG,
      rope_min = rules.ROPE_MIN,
      rope_max = rules.ROPE_MAX,
      climb = rules.ROPE_STEP,
      push = rules.SWING_PUSH,
      bounce = rules.ROPE_BOUNCE,
    })
  end)

  it(
    "🐙 hung from a ceiling, a swing let go at the end of its course leaves with the expected speed",
    function()
      local w, c = hall()
      local hooked = find(throw(w, 170), "tentacle_hooked")
      assert.is_not_nil(hooked)
      assert.are.equal(CEILING, hooked.y)
      assert.is_true(c.hanging)
      assert.are.equal("aiming", w.turn.state)
      send(w, { kind = "climb", direction = -1 })
      for _ = 1, 30 do
        world.step(w)
      end
      send(w, { kind = "climb", direction = 0 })
      assert.is_false(c.grounded)
      local function course()
        local sign = fixed.sign(c.vx)
        local fastest, lowest = 0, drop(c)
        for _ = 1, 120 do
          world.step(w)
          fastest = math.max(fastest, c.vx * c.vx + c.vy * c.vy)
          lowest = math.max(lowest, drop(c))
          if fixed.sign(c.vx) == -sign then
            return fastest, lowest
          end
        end
        error("the swing never turned back")
      end
      course()
      local top = drop(c)
      local fastest, lowest = course()
      local ideal = 2 * rules.GRAVITY * (lowest - top)
      assert.is_true(ideal > 0)
      assert.is_true(fastest <= ideal, "gained energy: " .. fastest .. " > " .. ideal)
      assert.is_true(fastest * 100 >= ideal * 72, "lost too much: " .. fastest .. " for " .. ideal)
      assert.is_true(drop(c) >= top, "rose above its start")
      local vx, vy, gauge = c.vx, c.vy, c.gauge
      local x, y = c.x, c.y
      local released = find(send(w, { kind = "jump", direction = 1 }), "tentacle_released")
      assert.is_not_nil(released)
      assert.is_false(c.hanging)
      assert.are.equal(gauge - 200, c.gauge)
      local lift = { vx + 256, vy - 614 + rules.GRAVITY }
      assert.are.same(lift, { c.vx, c.vy })
      assert.are.same({ x + lift[1], y + lift[2] }, { c.x, c.y })
      local landed = false
      for _ = 1, 120 do
        landed = landed or find(world.step(w), "landed") ~= nil
      end
      assert.is_true(landed)
      assert.is_true(c.grounded)
    end
  )

  local function swing_trace(x, angle, direction)
    local w, c = hall({ x = x })
    local plan = {
      [1] = { kind = "fire", weapon = "tentacle", angle = angle, power = 50 },
      [2] = { kind = "climb", direction = -1 },
      [25] = { kind = "climb", direction = 0 },
      [26] = { kind = "move", direction = direction },
      [70] = { kind = "move", direction = 0 },
      [80] = { kind = "climb", direction = 1 },
      [95] = { kind = "climb", direction = -1 },
      [110] = { kind = "climb", direction = 0 },
      [131] = { kind = "jump", direction = direction },
    }
    local trace = {}
    for i = 1, 240 do
      local input = plan[i]
      if input then
        send(w, input)
      else
        world.step(w)
      end
      trace[i] = {
        x = c.x,
        y = c.y,
        vx = c.vx,
        vy = c.vy,
        hanging = c.hanging,
        anchor_x = c.anchor_x,
        anchor_y = c.anchor_y,
        rope = c.rope,
        gauge = c.gauge,
      }
    end
    return trace
  end

  it("🐙 the same swing on the left mirrors the one on the right, tick by tick", function()
    local right = swing_trace(150, 170, 1)
    local left = swing_trace(WIDTH - 150, 512 - 170, -1)
    assert.is_true(right[130].hanging and not right[131].hanging)
    for i = 1, #right do
      local r, l = right[i], left[i]
      local where = "tick " .. i
      assert.are.equal(-r.vx, l.vx, where)
      assert.are.equal(r.vy, l.vy, where)
      assert.are.equal(WIDTH * 256 + 256 - r.x, l.x, where)
      assert.are.equal(r.y, l.y, where)
      assert.are.equal(r.hanging, l.hanging, where)
      assert.are.equal(r.rope, l.rope, where)
      assert.are.equal(r.gauge, l.gauge, where)
      assert.are.equal(WIDTH - 1 - r.anchor_x, l.anchor_x, where)
      assert.are.equal(r.anchor_y, l.anchor_y, where)
    end
  end)

  it(
    "🐙 a throw costs 300, hooked or missed, and one the gauge cannot cover does not happen",
    function()
      local w, c = hall({ terrain = terrains.flat(WIDTH) })
      local px, py = cat.pixel(c)
      local missed = find(throw(w, 256), "tentacle_missed")
      assert.is_not_nil(missed)
      assert.are.same({ px, py - 123 }, { missed.x, missed.y })
      assert.are.equal(2700, c.gauge)
      assert.is_false(c.hanging)
      w, c = hall()
      assert.is_not_nil(find(throw(w, 256), "tentacle_hooked"))
      assert.are.equal(2700 - 3, c.gauge)
      w, c = hall({ terrain = terrains.flat(WIDTH) })
      send(w, { kind = "move", direction = 1 })
      while c.gauge > 280 do
        world.step(w)
      end
      send(w, { kind = "move", direction = 0 })
      local events = throw(w, 256)
      assert.is_nil(find(events, "tentacle_missed"))
      assert.is_nil(find(events, "tentacle_hooked"))
      assert.are.equal(280, c.gauge)
    end
  )

  it("🐙 hanging costs 3 a tick, and an empty gauge lets go", function()
    local w, c = hall()
    send(w, { kind = "move", direction = 1 })
    while c.gauge > 340 do
      world.step(w)
    end
    send(w, { kind = "move", direction = 0 })
    assert.is_not_nil(find(throw(w, 256), "tentacle_hooked"))
    assert.are.equal(37, c.gauge)
    for left = 34, 1, -3 do
      assert.is_nil(find(world.step(w), "tentacle_released"))
      assert.is_true(c.hanging)
      assert.are.equal(left, c.gauge)
    end
    assert.is_not_nil(find(world.step(w), "tentacle_released"))
    assert.is_false(c.hanging)
    assert.are.equal(0, c.gauge)
  end)

  it(
    "🐙 does not end the turn, never fires while hanging, and throws again in the air",
    function()
      local w, c = hall()
      throw(w, 200)
      send(w, { kind = "climb", direction = -1 })
      for _ = 1, 20 do
        world.step(w)
      end
      assert.are.equal("aiming", w.turn.state)
      local events = send(w, { kind = "fire", weapon = "bazooka", angle = 64, power = 50 })
      assert.is_nil(find(events, "fired"))
      assert.are.equal(0, #w.projectiles)
      local gauge = c.gauge
      events = throw(w, 64)
      assert.is_nil(find(events, "tentacle_hooked"))
      assert.are.equal(gauge - 3, c.gauge)
      send(w, { kind = "jump", direction = 1 })
      assert.is_false(c.grounded)
      assert.is_not_nil(find(throw(w, 256), "tentacle_hooked"))
      assert.is_true(c.hanging)
      assert.are.equal("aiming", w.turn.state)
    end
  )

  it("🐙 climb shortens or lengthens the rope by 1 px a tick, between 4 and 120 px", function()
    local w, c = hall()
    throw(w, 256)
    local rope = c.rope
    assert.is_true(rope > 40 * 256 and rope < 60 * 256)
    send(w, { kind = "climb", direction = -1 })
    assert.are.equal(rope - 256, c.rope)
    for _ = 1, 80 do
      world.step(w)
    end
    assert.are.equal(4 * 256, c.rope)
    send(w, { kind = "climb", direction = 1 })
    for _ = 1, 200 do
      world.step(w)
    end
    assert.are.equal(120 * 256, c.rope)
    send(w, { kind = "climb", direction = 0 })
    world.step(w)
    assert.are.equal(120 * 256, c.rope)
    send(w, { kind = "jump", direction = 1 })
    assert.are.equal(0, c.climb)
    send(w, { kind = "climb", direction = -1 })
    assert.are.equal(0, c.climb)
  end)

  it(
    "🐙 the rope is the distance from the box's centre to the pixel hooked, kept within 4 px",
    function()
      local w, c = hall()
      local hooked = find(throw(w, 256), "tentacle_hooked")
      local cx = c.x - 128
      local cy = c.y - 640
      local dx, dy = cx - (hooked.x * 256 + 128), cy - (hooked.y * 256 + 128)
      assert.are.equal(fixed.isqrt(dx * dx + dy * dy), c.rope)
      w, c = hall({ terrain = terrains.wall(3, 40), x = 117 })
      hooked = find(throw(w, 0), "tentacle_hooked")
      assert.are.equal(120, hooked.x)
      assert.are.equal(4 * 256, c.rope)
    end
  )

  it("🐙 lets go when aiming ends, and is never at rest while hanging", function()
    local w, c = hall()
    throw(w, 200)
    assert.is_false(cat.at_rest(c))
    local released = false
    while w.turn.state == "aiming" do
      released = find(world.step(w), "tentacle_released") ~= nil or released
    end
    assert.are.equal("settling", w.turn.state)
    assert.is_true(released)
    assert.is_false(c.hanging)
  end)

  local function reach(c)
    local dx = c.x - 128 - (c.anchor_x * 256 + 128)
    local dy = c.y - 640 - (c.anchor_y * 256 + 128)
    return fixed.isqrt(dx * dx + dy * dy)
  end

  it(
    "🐙 on steps and slopes, a hanging blob never enters the terrain nor strays past its rope",
    function()
      for _, t in ipairs({
        terrains.staircase(160, 3, 3),
        terrains.staircase(160, 1, 1),
        terrains.staircase(160, 2, 1),
        terrains.staircase(160, 4, 6),
      }) do
        for x = 0, t.width - 1 do
          for y = CEILING - 4, CEILING do
            terrain.set(t, x, y, terrain.SOIL)
          end
        end
        local w, c = hall({ terrain = t, x = 140 })
        throw(w, 160)
        send(w, { kind = "climb", direction = -1 })
        for _ = 1, 25 do
          world.step(w)
        end
        send(w, { kind = "climb", direction = 0 })
        send(w, { kind = "move", direction = 1 })
        local touched = 0
        for i = 1, 200 do
          world.step(w)
          assert.is_true(c.hanging)
          local px, py = cat.pixel(c)
          assert.is_true(cat.box_free(t, px, py), "inside the terrain at tick " .. i)
          local d = reach(c)
          assert.is_true(d <= c.rope + 256, "drifted away at tick " .. i)
          if not cat.box_free(t, px + 1, py) or not cat.box_free(t, px, py + 1) then
            touched = touched + 1
          end
        end
        assert.is_true(touched > 0, "never touched the terrain")
      end
    end
  )
end)

describe("🐙 the tentacle, its edges (§5.4)", function()
  local world = require("shared.sim.world")

  local WIDTH = 400

  local function hall(fields)
    fields = fields or {}
    local x = fields.x or 150
    local t = fields.terrain or terrains.ceiling(40, WIDTH)
    local w = world.from_terrain({
      terrain = t,
      liquid = terrains.LIQUID,
      settings = { teams = 2, cats_per_team = 1, wind_max = 0 },
      spawns = {
        { team = 1, index = 1, x = x, y = fields.y or terrains.GROUND - 1 },
        { team = 2, index = 1, x = t.width - 20, y = terrains.GROUND - 1 },
      },
    })
    while w.turn.state ~= "aiming" do
      world.step(w)
    end
    return w, w.cats[w.turn.cat]
  end

  local function send(w, input)
    input.team = w.turn.team
    return world.step(w, { input })
  end

  local function throw(w, angle)
    return send(w, { kind = "fire", weapon = "tentacle", angle = angle, power = 50 })
  end

  local function find(events, kind)
    for _, e in ipairs(events) do
      if e.type == kind then
        return e
      end
    end
    return nil
  end

  local function soil(t, x0, y0, x1, y1)
    for y = y0, y1 do
      for x = x0, x1 do
        terrain.set(t, x, y, terrain.SOIL)
      end
    end
  end

  local function face(w, direction)
    send(w, { kind = "move", direction = direction })
    send(w, { kind = "move", direction = 0 })
  end

  local function walk_down_to(w, c, left)
    send(w, { kind = "move", direction = 1 })
    for _ = 1, 400 do
      if c.gauge <= left then
        break
      end
      world.step(w)
    end
    send(w, { kind = "move", direction = 0 })
    assert.are.equal(left, c.gauge)
  end

  it("🐙 lets go when the time runs out, with gauge to spare", function()
    local w, c = hall()
    while w.turn.timer > 20 do
      world.step(w)
    end
    throw(w, 200)
    assert.is_true(c.hanging)
    local released
    while w.turn.state == "aiming" do
      released = find(world.step(w), "tentacle_released")
    end
    assert.is_not_nil(released)
    assert.are.equal("settling", w.turn.state)
    assert.is_true(c.gauge > 2000)
  end)

  it("🐙 lets go when the turn is skipped", function()
    local w, c = hall()
    throw(w, 200)
    assert.is_true(c.hanging)
    assert.is_not_nil(find(send(w, { kind = "skip" }), "tentacle_released"))
    assert.is_false(c.hanging)
  end)

  it(
    "🐙 pulled toward a wall, it hits it, bounces off it and climbs, instead of sticking",
    function()
      local t = terrains.wall(5, 70)
      local w, c = hall({ terrain = t, x = 100 })
      local hooked = find(throw(w, 128), "tentacle_hooked")
      assert.are.equal(120, hooked.x)
      local _, start = cat.pixel(c)
      send(w, { kind = "climb", direction = -1 })
      local bounced, slid = false, 0
      for _ = 1, 30 do
        local x, y = c.x, c.y
        world.step(w)
        local px, py = cat.pixel(c)
        if not cat.box_free(t, px + 1, py) and c.vx < 0 then
          bounced = true
        end
        if not cat.box_free(t, px + 1, py) and c.x == x and c.y ~= y then
          slid = slid + 1
        end
      end
      local _, feet = cat.pixel(c)
      assert.is_true(bounced, "never bounced off the wall")
      assert.is_true(slid > 0, "never slid along it")
      assert.is_true(start - feet >= 5, "rose " .. start - feet .. " px")
    end
  )

  local function leap_and_hook(w, direction)
    send(w, { kind = "jump", direction = direction })
    world.step(w)
    assert.is_not_nil(find(throw(w, 256), "tentacle_hooked"))
    send(w, { kind = "climb", direction = 1 })
  end

  it(
    "🐙 on a slack rope it bounces off a wall at 90 %, the left one mirroring the right",
    function()
      for _, side in ipairs({ 1, -1 }) do
        local t = terrains.ceiling(40, WIDTH)
        local x = side > 0 and 150 or WIDTH - 150
        local near = side > 0 and 165 or WIDTH - 1 - 175
        for y = 41, terrains.GROUND - 1 do
          for dx = 0, 10 do
            terrain.set(t, near + dx, y, terrain.SOIL)
          end
        end
        local w, c = hall({ terrain = t, x = x })
        leap_and_hook(w, side)
        assert.are.equal(3000 - 200 - 100 - 3 * 2, c.gauge)
        local after
        for _ = 1, 40 do
          world.step(w)
          if c.vx ~= side * 256 then
            after = c.vx
            break
          end
        end
        assert.are.equal(-side * 230, after)
        assert.is_true(c.hanging)
      end
    end
  )

  it("🐙 on a slack rope it bounces off the ground at 90 % of its fall", function()
    local w, c = hall()
    leap_and_hook(w, 1)
    local bounced
    for _ = 1, 80 do
      local before = c.vy
      world.step(w)
      if before > 0 and c.vy < 0 then
        bounced = { before + rules.GRAVITY, c.vy }
        break
      end
    end
    assert.is_not_nil(bounced, "never touched the ground")
    assert.are.equal(-fixed.round_div(bounced[1] * 90, 100), bounced[2])
    assert.is_true(c.hanging)
  end)

  it(
    "🐙 letting the rope out slows the turn around the anchor by the ratio of the lengths",
    function()
      local w, c = hall()
      throw(w, 170)
      send(w, { kind = "climb", direction = -1 })
      for _ = 1, 20 do
        world.step(w)
      end
      send(w, { kind = "climb", direction = 0 })
      local side = fixed.sign(c.x - c.anchor_x * 256 - 256)
      for _ = 1, 120 do
        world.step(w)
        if fixed.sign(c.x - c.anchor_x * 256 - 256) ~= side then
          break
        end
      end
      local rope = c.rope
      local copy = assert(world.restore(world.snapshot(w)))
      world.step(copy)
      send(w, { kind = "climb", direction = 1 })
      local held, out = copy.cats[c.id].vx, c.vx
      local expected = held * rope / (rope + 256)
      assert.is_true(
        math.abs(out - expected) <= math.abs(held) * 15 / 1000,
        out .. " for " .. expected
      )
    end
  )

  it("🐙 it never swings faster than the speed limit, however long it is pumped", function()
    local t = terrain.new(400, 300)
    for x = 0, 399 do
      for y = 280, 299 do
        terrain.set(t, x, y, terrain.SOIL)
      end
    end
    for x = 198, 201 do
      for y = 170, 173 do
        terrain.set(t, x, y, terrain.SOIL)
      end
    end
    local w = world.from_terrain({
      terrain = t,
      liquid = 296,
      settings = { teams = 2, cats_per_team = 1, wind_max = 0 },
      spawns = {
        { team = 1, index = 1, x = 170, y = 279 },
        { team = 2, index = 1, x = 380, y = 279 },
      },
    })
    while w.turn.state ~= "aiming" do
      world.step(w)
    end
    local c = w.cats[w.turn.cat]
    assert.is_not_nil(find(throw(w, 211), "tentacle_hooked"))
    send(w, { kind = "climb", direction = -1 })
    for _ = 1, 15 do
      world.step(w)
    end
    send(w, { kind = "climb", direction = 0 })
    local held, fastest = 0, 0
    for _ = 1, 900 do
      local want = c.vx >= 0 and 1 or -1
      if want ~= held then
        send(w, { kind = "move", direction = want })
        held = want
      else
        world.step(w)
      end
      if not c.hanging then
        break
      end
      fastest = math.max(fastest, math.abs(c.vx), math.abs(c.vy))
    end
    assert.is_true(fastest > 2000, "never got going: " .. fastest)
    assert.is_true(fastest <= rules.MAX_AXIS_SPEED, "reached " .. fastest)
  end)

  it("🐙 held where it cannot move, it stores no speed it does not take", function()
    local function box(t, x0, y0, x1, y1)
      for y = y0, y1 do
        for x = x0, x1 do
          terrain.set(t, x, y, terrain.SOIL)
        end
      end
    end
    local function corner()
      local t = terrain.new(300, 250)
      box(t, 0, 150, 299, 249)
      box(t, 0, 36, 299, 40)
      box(t, 107, 41, 110, 90)
      box(t, 107, 106, 110, 149)
      box(t, 60, 100, 106, 149)
      return t,
        { x = 150, y = 149 },
        256,
        {
          [1] = { kind = "climb", direction = -1 },
          [37] = { kind = "climb", direction = 0 },
          [38] = { kind = "move", direction = -1 },
          [150] = { kind = "move", direction = 0 },
          [151] = { kind = "climb", direction = -1 },
        }
    end
    local function pillar()
      local t = terrain.new(400, 250)
      box(t, 0, 240, 399, 249)
      box(t, 0, 0, 70, 239)
      box(t, 166, 120, 171, 239)
      box(t, 180, 120, 399, 239)
      box(t, 172, 140, 179, 239)
      return t,
        { x = 185, y = 119 },
        512,
        {
          [1] = { kind = "climb", direction = -1 },
          [90] = { kind = "climb", direction = 0 },
        }
    end
    local function lowered()
      return terrains.ceiling(40, WIDTH),
        { x = 150, y = terrains.GROUND - 1 },
        256,
        {
          [1] = { kind = "climb", direction = -1 },
          [41] = { kind = "climb", direction = 0 },
          [71] = { kind = "climb", direction = 1 },
        }
    end
    for _, build in ipairs({ corner, pillar, lowered }) do
      local t, at, angle, plan = build()
      local w = world.from_terrain({
        terrain = t,
        liquid = t.height - 4,
        settings = { teams = 2, cats_per_team = 1, wind_max = 0 },
        spawns = {
          { team = 1, index = 1, x = at.x, y = at.y },
          { team = 2, index = 1, x = t.width - 20, y = at.y },
        },
      })
      while w.turn.state ~= "aiming" do
        world.step(w)
      end
      local c = w.cats[w.turn.cat]
      assert.is_not_nil(find(throw(w, angle), "tentacle_hooked"))
      local still = 0
      for i = 1, 300 do
        local x, y = c.x, c.y
        if plan[i] then
          send(w, plan[i])
        else
          world.step(w)
        end
        if not c.hanging then
          break
        end
        still = (c.x == x and c.y == y) and still + 1 or 0
        if still >= 10 then
          assert.is_true(
            math.abs(c.vx) <= 256 and math.abs(c.vy) <= 256,
            "still for " .. still .. " ticks with v " .. c.vx .. ", " .. c.vy .. " at tick " .. i
          )
        end
        if build == lowered and i > 72 then
          assert.is_true(math.abs(c.vy) <= 512, "stored " .. c.vy .. " while lowered, tick " .. i)
        end
      end
    end
  end)

  it("🐙 reeling in while it swings speeds the swing up, as on a swing", function()
    local function speed_after(reel)
      local w, c = hall()
      throw(w, 170)
      send(w, { kind = "climb", direction = -1 })
      for _ = 1, 20 do
        world.step(w)
      end
      send(w, { kind = "climb", direction = 0 })
      for _ = 1, 25 do
        world.step(w)
      end
      send(w, { kind = "climb", direction = reel })
      for _ = 1, 8 do
        world.step(w)
      end
      return c.vx * c.vx + c.vy * c.vy
    end
    local reeled, held = speed_after(-1), speed_after(0)
    assert.is_true(reeled * 100 >= held * 110, "reeled " .. reeled .. ", held " .. held)
  end)

  it("🐙 a swing keeps its height: five swings later it still rises nearly as high", function()
    local w, c = hall()
    throw(w, 170)
    send(w, { kind = "climb", direction = -1 })
    for _ = 1, 30 do
      world.step(w)
    end
    send(w, { kind = "climb", direction = 0 })
    local tops, sign = {}, 0
    for _ = 1, 400 do
      world.step(w)
      local s = fixed.sign(c.vx)
      if s ~= 0 and s ~= sign then
        if sign ~= 0 then
          tops[#tops + 1] = c.y - c.anchor_y * 256
        end
        sign = s
      end
    end
    assert.is_true(#tops >= 6, #tops .. " swings")
    local bottom = c.rope + 768
    local first, fifth = bottom - tops[1], bottom - tops[6]
    assert.is_true(fifth * 100 >= first * 50, "rose " .. first .. " then " .. fifth)
    for i = 2, #tops do
      assert.is_true(tops[i] >= tops[i - 1], "rose higher at swing " .. i)
    end
  end)

  it(
    "🐙 at the foot of a cliff it climbs it: hook, reel in, jump, throw again in the air",
    function()
      local TOP = 40
      local t = terrains.flat(WIDTH)
      for y = TOP, terrains.GROUND - 1 do
        for x = 200, WIDTH - 1 do
          terrain.set(t, x, y, terrain.SOIL)
        end
      end
      local w, c = hall({ terrain = t, x = 190 })
      local function reel()
        send(w, { kind = "climb", direction = -1 })
        local last, still = c.x + c.y, 0
        for _ = 1, 150 do
          world.step(w)
          still = math.abs(c.x + c.y - last) < 16 and still + 1 or 0
          last = c.x + c.y
          if still >= 6 then
            break
          end
        end
        send(w, { kind = "climb", direction = 0 })
      end
      local function leap()
        send(w, { kind = "jump", direction = 1 })
        for _ = 1, 60 do
          world.step(w)
          if c.vy >= 0 then
            break
          end
        end
      end
      local anchors = {}
      for _, angle in ipairs({ 200, 200, 0 }) do
        throw(w, angle)
        assert.is_true(c.hanging, "missed at angle " .. angle)
        anchors[#anchors + 1] = c.anchor_y
        reel()
        leap()
      end
      assert.is_true(anchors[1] > anchors[2] and anchors[2] > anchors[3], "did not climb")
      assert.is_true(select(2, cat.pixel(c)) < TOP, "the last leap stayed below the top")
      assert.is_not_nil(find(throw(w, 960), "tentacle_hooked"))
      assert.is_true(c.anchor_x >= 200 and c.anchor_y == TOP)
      reel()
      send(w, { kind = "jump", direction = 1 })
      for _ = 1, 90 do
        if c.grounded then
          break
        end
        world.step(w)
      end
      local px, py = cat.pixel(c)
      assert.is_true(c.grounded and px > 200 and py == TOP - 1, "stands at " .. px .. ", " .. py)
      assert.is_true(c.alive and c.hp == 100)
      assert.are.equal("aiming", w.turn.state)
      assert.is_true(c.gauge > 1000, "gauge " .. c.gauge)
    end
  )

  it("🐙 a throw to the left mirrors the same throw to the right, angle by angle", function()
    for angle = 132, 380, 8 do
      local wr, cr = hall({ x = 150 })
      local wl, cl = hall({ x = WIDTH - 150 })
      face(wl, -1)
      throw(wr, angle)
      throw(wl, 512 - angle)
      local where = "angle " .. angle
      assert.is_true(cr.hanging and cl.hanging, where)
      assert.are.equal(WIDTH - 1 - cr.anchor_x, cl.anchor_x, where)
      assert.are.equal(cr.anchor_y, cl.anchor_y, where)
      assert.are.equal(cr.rope, cl.rope, where)
    end
  end)

  it("🐙 straight up, the ray between two columns counts in the column the cat faces", function()
    for _, direction in ipairs({ -1, 1 }) do
      local t = terrains.flat(WIDTH)
      if direction < 0 then
        soil(t, 0, 36, 149, 40)
      else
        soil(t, 150, 36, WIDTH - 1, 40)
      end
      local w, c = hall({ terrain = t, x = 150 })
      face(w, direction)
      assert.are.equal(direction, c.facing)
      local hooked = find(throw(w, 256), "tentacle_hooked")
      assert.is_not_nil(hooked, "facing " .. direction)
      assert.are.equal(direction < 0 and 149 or 150, hooked.x)
    end
  end)

  it("🐙 a jump lets go even on a nearly empty gauge, and refills the 2 px reserve", function()
    local w, c = hall()
    walk_down_to(w, c, 360)
    throw(w, 200)
    assert.are.equal(57, c.gauge)
    assert.are.equal(0, c.nudge)
    assert.is_not_nil(find(send(w, { kind = "jump", direction = 1 }), "tentacle_released"))
    assert.are.equal(rules.AIR_NUDGE, c.nudge)
    assert.are.equal(57, c.gauge)
    assert.is_true(c.vy >= 0 and math.abs(c.vx) < 256, "lifted to " .. c.vx .. ", " .. c.vy)
  end)

  it("🐙 a jump the gauge just covers still gets its lift", function()
    local w, c = hall()
    throw(w, 200)
    c.gauge = 203
    world.step(w)
    local vx, vy = c.vx, c.vy
    send(w, { kind = "jump", direction = 1 })
    assert.are.equal(0, c.gauge)
    assert.are.same({ vx + 256, vy - 614 + rules.GRAVITY }, { c.vx, c.vy })
  end)

  it("🐙 in the air, a throw costs 100, so 150 points left still throw", function()
    local w, c = hall()
    walk_down_to(w, c, 360)
    send(w, { kind = "jump", direction = 1 })
    world.step(w)
    assert.is_false(c.grounded)
    assert.are.equal(160, c.gauge)
    assert.is_not_nil(find(throw(w, 256), "tentacle_hooked"))
    assert.are.equal(160 - 100 - 3, c.gauge)
  end)

  it("🐙 a throw the gauge just covers happens, and the empty gauge lets go at once", function()
    local w, c = hall()
    walk_down_to(w, c, 300)
    local events = throw(w, 200)
    assert.is_not_nil(find(events, "tentacle_hooked"))
    assert.is_not_nil(find(events, "tentacle_released"))
    assert.are.equal(0, c.gauge)
  end)

  it("🐙 ignores a climb out of −1..1", function()
    local w, c = hall()
    throw(w, 256)
    for _, direction in ipairs({ 2, -2, 0.5, "1" }) do
      send(w, { kind = "climb", direction = direction })
      assert.are.equal(0, c.climb)
    end
  end)

  it("🐙 a blob let down into the liquid on its rope drowns", function()
    local t = terrains.shore()
    soil(t, 0, 36, t.width - 1, 40)
    local w, c = hall({ terrain = t, x = 90 })
    assert.is_not_nil(find(throw(w, 200), "tentacle_hooked"))
    send(w, { kind = "climb", direction = 1 })
    send(w, { kind = "move", direction = 1 })
    local died, released
    for _ = 1, 60 do
      local events = world.step(w)
      died, released = find(events, "died"), find(events, "tentacle_released")
      if not c.alive then
        break
      end
    end
    assert.is_not_nil(died)
    assert.are.equal("liquid", died.cause)
    assert.is_not_nil(released)
    assert.is_false(c.hanging)
    assert.is_true(c.gauge > 2000)
  end)
end)

describe("🐈 blobs knocking each other (§5.4)", function()
  local world = require("shared.sim.world")

  local WIDTH = 400

  local function pair(first, second)
    local t = terrains.flat(WIDTH)
    local w = world.from_terrain({
      terrain = t,
      liquid = terrains.LIQUID,
      settings = { teams = 2, cats_per_team = 1, wind_max = 0 },
      spawns = {
        { team = 1, index = 1, x = first, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = second, y = terrains.GROUND - 1 },
      },
    })
    while w.turn.state ~= "aiming" do
      world.step(w)
    end
    return w, w.cats[1], w.cats[2]
  end

  it("🐈 uses §5.4's figures for a knock", function()
    assert.are.same(
      { share = 60, lift = 256, thrown = 384 },
      { share = rules.BUMP_SHARE, lift = rules.BUMP_LIFT, thrown = rules.THROWN_VX }
    )
  end)

  it("🐈 a thrown blob that hits another passes it 60 % of their difference of speed", function()
    local w, a, b = pair(100, 140)
    cat.push(a, 1536, -300)
    local hit
    for _ = 1, 60 do
      local avx, avy = a.vx, a.vy + rules.GRAVITY
      world.step(w)
      if b.vx ~= 0 then
        hit = { avx = avx, avy = avy }
        break
      end
    end
    assert.is_not_nil(hit, "never met")
    local share = fixed.round_div(hit.avx * 60, 100)
    assert.are.equal(share, b.vx)
    assert.are.equal(hit.avx - share, a.vx)
    assert.is_true(b.vy <= -256 + rules.GRAVITY, "b left the ground at " .. b.vy)
    assert.is_false(b.grounded)
    assert.are.equal(100, b.hp)
    local from = b.x
    for _ = 1, 120 do
      world.step(w)
    end
    assert.is_true(b.x - from > 10 * 256, "b only moved " .. (b.x - from))
  end)

  it("🐈 the same knock to the left mirrors the one to the right, tick by tick", function()
    local wr, ar, br = pair(100, 140)
    local wl, al, bl = pair(WIDTH - 100, WIDTH - 140)
    cat.push(ar, 1536, -300)
    cat.push(al, -1536, -300)
    for i = 1, 150 do
      world.step(wr)
      world.step(wl)
      local where = "tick " .. i
      assert.are.same({ -ar.vx, ar.vy, -br.vx, br.vy }, { al.vx, al.vy, bl.vx, bl.vy }, where)
      assert.are.equal(WIDTH * 256 + 256 - ar.x, al.x, where)
      assert.are.equal(WIDTH * 256 + 256 - br.x, bl.x, where)
    end
  end)

  it("🐈 blobs that walk or jump still pass through each other", function()
    local w, a, b = pair(100, 120)
    world.step(w, { { team = w.turn.team, kind = "move", direction = 1 } })
    for _ = 1, 80 do
      world.step(w)
    end
    assert.is_true(cat.pixel(a) > 130, "stopped at " .. cat.pixel(a))
    assert.are.same({ 0, 0, 120 }, { b.vx, b.vy, (cat.pixel(b)) })
    w, a, b = pair(100, 115)
    world.step(w, { { team = w.turn.team, kind = "jump", direction = 1 } })
    for _ = 1, 60 do
      world.step(w)
    end
    assert.is_true(cat.pixel(a) > 115, "the jump stopped at " .. cat.pixel(a))
    assert.are.same({ 0, 0, 115 }, { b.vx, b.vy, (cat.pixel(b)) })
  end)

  it("🐈 the knock happens when the boxes first overlap, not a pixel sooner or later", function()
    local w, a, b = pair(100, 140)
    cat.push(a, 1536, -300)
    for _ = 1, 60 do
      world.step(w)
      if b.vx ~= 0 then
        break
      end
    end
    local hit_at = cat.pixel(a)
    assert.is_true(hit_at < 140 and 140 - hit_at <= rules.CAT_WIDTH - 1, "met at " .. hit_at)
    assert.is_true(140 - hit_at >= rules.CAT_WIDTH - 2, "met at " .. hit_at)
  end)

  it("🐈 a thrown blob that catches up with another trades 60 % of their difference", function()
    local w, a, b = pair(100, 125)
    cat.push(a, 2048, -300)
    cat.push(b, 512, -300)
    local before
    for _ = 1, 60 do
      before = { a.vx, a.vy + rules.GRAVITY, b.vx, b.vy }
      world.step(w)
      if a.vx < before[1] - 64 then
        break
      end
    end
    local sx = fixed.round_div((before[1] - before[3]) * 60, 100)
    local sy = fixed.round_div((before[2] - before[4]) * 60, 100)
    assert.are.equal(before[1] - sx, a.vx)
    assert.are.equal(before[3] + sx, b.vx)
    assert.are.equal(before[2] - sy, a.vy)
    assert.are.equal(math.min(before[4] + sy, -256) + rules.GRAVITY, b.vy)
  end)

  it(
    "🐈 only a thrown blob knocks: a jump through another, or 384 FP/tick exactly, does not",
    function()
      local w, a, b = pair(100, 104)
      world.step(w, { { team = w.turn.team, kind = "jump", direction = 1 } })
      for _ = 1, 40 do
        world.step(w)
      end
      assert.is_true(cat.pixel(a) > 104)
      assert.are.same({ 0, 0, 104 }, { b.vx, b.vy, (cat.pixel(b)) })
      w, a, b = pair(100, 110)
      cat.push(a, rules.THROWN_VX, -300)
      for _ = 1, 60 do
        world.step(w)
      end
      assert.is_true(cat.pixel(a) >= 105, "stopped at " .. cat.pixel(a))
      assert.are.same({ 0, 0, 110 }, { b.vx, b.vy, (cat.pixel(b)) })
    end
  )

  it("🐈 a thrown blob lets go of a hanging one it hits, and skips the dead", function()
    local t = terrains.ceiling(40, WIDTH)
    local w = world.from_terrain({
      terrain = t,
      liquid = terrains.LIQUID,
      settings = { teams = 2, cats_per_team = 2, wind_max = 0 },
      spawns = {
        { team = 1, index = 1, x = 150, y = terrains.GROUND - 1 },
        { team = 1, index = 2, x = 60, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 300, y = terrains.GROUND - 1 },
        { team = 2, index = 2, x = 350, y = terrains.GROUND - 1 },
      },
    })
    while w.turn.state ~= "aiming" do
      world.step(w)
    end
    local hanging = w.cats[w.turn.cat]
    world.step(w, {
      { team = w.turn.team, kind = "fire", weapon = "tentacle", angle = 256, power = 1 },
    })
    assert.is_true(hanging.hanging)
    local thrower = w.cats[2]
    local px = cat.pixel(hanging)
    thrower.x, thrower.y = (px - 14) * 256 + 128, hanging.y
    cat.push(thrower, 2048, 0)
    local released = false
    for _ = 1, 30 do
      for _, e in ipairs(world.step(w)) do
        if e.type == "tentacle_released" and e.cat == hanging.id then
          released = true
        end
      end
    end
    assert.is_true(released)
    assert.is_false(hanging.hanging)
    local w2, a, b = pair(100, 140)
    b.alive = false
    cat.push(a, 1536, -300)
    for _ = 1, 40 do
      world.step(w2)
    end
    assert.are.same({ 0, 0 }, { b.vx, b.vy })
  end)

  it("🐈 two blobs on the same spot, thrown alike, fly together without knocking", function()
    local w, a, b = pair(100, 101)
    b.x = a.x
    cat.push(a, 1536, -600)
    cat.push(b, 1536, -600)
    for _ = 1, 20 do
      world.step(w)
      assert.are.same({ a.x, a.y, a.vx, a.vy }, { b.x, b.y, b.vx, b.vy })
    end
  end)

  it("🐈 a blob that knocks another while skidding does not hold the turn up", function()
    local w, a, b = pair(100, 120)
    cat.push(a, 1536, -60)
    cat.push(b, 0, -600)
    world.step(w, { { team = w.turn.team, kind = "skip" } })
    for _ = 1, 200 do
      if w.turn.state ~= "settling" then
        break
      end
      world.step(w)
    end
    assert.are_not.equal("settling", w.turn.state)
  end)

  it(
    "🐈 a bazooka shot at a blob's feet sends it into its neighbour, who flies off too",
    function()
      local w, a, b = pair(100, 150)
      local c = w.cats[w.turn.cat]
      assert.are.equal(a, c)
      world.step(w, {
        { team = w.turn.team, kind = "fire", weapon = "bazooka", angle = 400, power = 12 },
      })
      local from = b.x
      for _ = 1, 200 do
        world.step(w)
      end
      assert.is_true(b.x - from > 4 * 256, "the neighbour only moved " .. (b.x - from))
    end
  )
end)

describe("🦷 the Chomp (§8.2)", function()
  local trig = require("shared.sim.trig")
  local weapons = require("shared.sim.weapons.registry")
  local world = require("shared.sim.world")

  local FEET = terrains.GROUND - 1
  local W = terrains.WIDTH

  local function burrow(t, first, second)
    local w = world.from_terrain({
      terrain = t,
      liquid = terrains.LIQUID,
      settings = { teams = 2, cats_per_team = 1, wind_max = 0 },
      spawns = {
        { team = 1, index = 1, x = first[1], y = first[2] },
        { team = 2, index = 1, x = second[1], y = second[2] },
      },
    })
    while w.turn.state ~= "aiming" do
      world.step(w)
    end
    return w, w.cats[1], w.cats[2]
  end

  local function send(w, input)
    input.team = w.turn.team
    return world.step(w, { input })
  end

  local function chomp(w, angle)
    return send(w, { kind = "fire", weapon = "chomp", angle = angle, power = 1 })
  end

  it("🦷 uses §8.2's figures", function()
    local c = weapons.get("chomp")
    assert.are.same({ "digger", 3, "angle" }, { c.kind, rules.AMMO.chomp, c.aim })
    assert.are.same({ ticks = 60, radius = 5, pixels = 2, every = 3 }, {
      ticks = rules.DIG_TICKS,
      radius = rules.DIG_RADIUS,
      pixels = rules.DIG_PIXELS,
      every = rules.DIG_EVERY,
    })
  end)

  it("🦷 eats a tunnel its size into a wall, 2/3 px a tick, no gravity, ends the turn", function()
    local w, a, b = burrow(terrains.wall(60, 40), { 110, FEET }, { 20, FEET })
    local x0, y0 = a.x, a.y
    local events = chomp(w, 0)
    assert.are.same({ "fired", a.id, "chomp" }, { events[1].type, events[1].cat, events[1].weapon })
    local bite = events[2]
    assert.are.same(
      { "chomped", a.id, 5, 110, 96 },
      { bite.type, bite.cat, bite.radius, bite.x, bite.y }
    )
    local bites = count(events, "chomped")
    for i = 2, rules.DIG_TICKS do
      assert.are.equal("flight", w.turn.state, "tick " .. i)
      local step = world.step(w)
      bites = bites + count(step, "chomped")
      for _, e in ipairs(step) do
        if e.type == "chomped" then
          for dy = -5, 5 do
            for dx = -3, 3 do
              if dx * dx + dy * dy <= 25 then
                assert.is_false(terrain.solid(w.terrain, e.x + dx, e.y + dy), "tick " .. i)
              end
            end
          end
        end
      end
      local px, py = cat.pixel(a)
      assert.are.equal(y0, a.y, "tick " .. i)
      assert.is_true(cat.box_free(w.terrain, px, py), "tick " .. i)
    end
    assert.are.equal(60, bites)
    assert.are.same({ x0 + 40 * 256, 0, "retreat" }, { a.x, a.dig, w.turn.state })
    for x = 110, 150 do
      assert.is_true(cat.box_free(w.terrain, x, FEET), "x " .. x)
    end
    assert.is_false(terrain.solid(w.terrain, 130, FEET - 8))
    assert.is_true(terrain.solid(w.terrain, 130, FEET - 9))
    assert.is_true(terrain.solid(w.terrain, 156, FEET - 3))
    assert.are.same({ 100, 100 }, { a.hp, b.hp })
    for _ = 1, 30 do
      world.step(w)
    end
    assert.is_true(a.grounded)
    assert.are.equal(100, a.hp)
  end)

  it("🦷 digs in every direction, 40 px along the aim, through a tunnel its size", function()
    for angle = 0, trig.ANGLES - 1, 64 do
      local where = "angle " .. angle
      local w, a = burrow(terrains.pockets({ { 100, 60 }, { 190, 12 } }), { 100, 60 }, { 190, 12 })
      local x0, y0 = a.x, a.y
      chomp(w, angle)
      for _ = 2, rules.DIG_TICKS do
        world.step(w)
        local px, py = cat.pixel(a)
        assert.is_true(cat.box_free(w.terrain, px, py), where)
      end
      local dx, dy = (a.x - x0) / 256, (a.y - y0) / 256
      local cos, sin = trig.cos(angle) / trig.SCALE, trig.sin(angle) / trig.SCALE
      assert.is_true(math.abs(math.sqrt(dx * dx + dy * dy) - 40) < 0.5, where)
      assert.is_true(math.abs(dx * sin + dy * cos) < 0.5 and dx * cos - dy * sin > 39, where)
      assert.are.same({ 0, "retreat" }, { a.dig, w.turn.state }, where)
    end
  end)

  it("🦷 stops where its next move would leave the map", function()
    local function meal(w, a, angle)
      chomp(w, angle)
      local ticks = 1
      while a.dig > 0 do
        world.step(w)
        ticks = ticks + 1
      end
      return ticks
    end
    local w, a = burrow(terrains.pockets({ { 10, 60 }, { 150, 60 } }), { 10, 60 }, { 150, 60 })
    local ticks = meal(w, a, 512)
    local px, py = cat.pixel(a)
    assert.are.same({ 12, 3, 60, "retreat" }, { ticks, px, py, w.turn.state })
    w, a = burrow(terrains.pockets({ { 100, 10 }, { 150, 60 } }), { 100, 10 }, { 150, 60 })
    ticks = meal(w, a, 256)
    px, py = cat.pixel(a)
    assert.are.same({ 7, 100, 6, "retreat" }, { ticks, px, py, w.turn.state })
    w, a = burrow(terrains.pockets({ { 190, 60 }, { 50, 60 } }), { 190, 60 }, { 50, 60 })
    ticks = meal(w, a, 0)
    px = cat.pixel(a)
    assert.are.same({ 12, W - 3, "retreat" }, { ticks, px, w.turn.state })
  end)

  it("🦷 eating its way into the liquid drowns it, and the turn goes on", function()
    local w, a = burrow(terrains.pockets({ { 100, 100 }, { 150, 60 } }), { 100, 100 }, { 150, 60 })
    chomp(w, 768)
    local died, above = false, nil
    for _ = 1, 40 do
      if not died then
        local _, cy = cat.center(a)
        above = cy
      end
      for _, e in ipairs(world.step(w)) do
        died = died or (e.type == "died" and e.cat == a.id)
      end
    end
    assert.is_true(died)
    assert.are.equal(terrains.LIQUID - 1, above)
    assert.are.same({ false, 0 }, { a.alive, a.dig })
    assert.are_not.equal("flight", w.turn.state)
  end)

  it("🦷 the same Chomp downward mirrors the one upward, tick by tick", function()
    for _, angle in ipairs({ 100, 256, 200 }) do
      local wu, au = burrow(terrains.pockets({ { 100, 60 }, { 20, 60 } }), { 100, 60 }, { 20, 60 })
      local wd, ad = burrow(terrains.pockets({ { 100, 60 }, { 20, 60 } }), { 100, 60 }, { 20, 60 })
      local y0 = au.y
      chomp(wu, angle)
      chomp(wd, trig.ANGLES - angle)
      for i = 1, rules.DIG_TICKS - 1 do
        local where = "angle " .. angle .. " tick " .. i
        assert.are.same({ au.x, y0 - au.y }, { ad.x, ad.y - y0 }, where)
        world.step(wu)
        world.step(wd)
      end
    end
  end)

  it("🦷 turns to where it eats", function()
    local w, a = burrow(terrains.pockets({ { 100, 60 }, { 20, 60 } }), { 100, 60 }, { 20, 60 })
    chomp(w, 600)
    assert.are.equal(-1, a.facing)
    w, a = burrow(terrains.pockets({ { 100, 60 }, { 20, 60 } }), { 100, 60 }, { 20, 60 })
    send(w, { kind = "move", direction = -1 })
    send(w, { kind = "move", direction = 0 })
    chomp(w, 1000)
    assert.are.equal(1, a.facing)
    w, a = burrow(terrains.pockets({ { 100, 60 }, { 20, 60 } }), { 100, 60 }, { 20, 60 })
    send(w, { kind = "move", direction = -1 })
    send(w, { kind = "move", direction = 0 })
    chomp(w, 256)
    assert.are.equal(-1, a.facing)
  end)

  it("🦷 a thrown blob passes through one that eats, which keeps eating", function()
    local w, a, b = burrow(terrains.flat(), { 110, FEET }, { 60, FEET })
    chomp(w, 256)
    b.x, b.y = a.x - 12 * 256, a.y
    cat.push(b, 2048, 0)
    for i = 1, 6 do
      world.step(w)
      assert.are.same({ 0, 0 }, { a.vx, a.vy }, "tick " .. i)
    end
    assert.are.equal(rules.DIG_TICKS - 7, a.dig)
    assert.is_true(b.x > a.x + 6 * 256, "the thrown blob went through")
  end)

  it("🦷 the same Chomp to the left mirrors the one to the right, tick by tick", function()
    for _, angle in ipairs({ 100, 0, 256, 900 }) do
      local wr, ar = burrow(terrains.pockets({ { 100, 60 }, { 20, 60 } }), { 100, 60 }, { 20, 60 })
      local wl, al = burrow(
        terrains.pockets({ { 100, 60 }, { 180, 60 } }),
        { 100, 60 },
        { 180, 60 }
      )
      send(wl, { kind = "move", direction = -1 })
      send(wl, { kind = "move", direction = 0 })
      send(wr, { kind = "move", direction = 1 })
      send(wr, { kind = "move", direction = 0 })
      local x0, y0, moved = al.x, al.y, false
      chomp(wr, angle)
      chomp(wl, fixed.mod(trig.ANGLES / 2 - angle, trig.ANGLES))
      assert.are.equal(rules.DIG_TICKS - 1, al.dig)
      for i = 1, 90 do
        local where = "angle " .. angle .. " tick " .. i
        assert.are.same({ W * 256 + 256 - ar.x, ar.y }, { al.x, al.y }, where)
        moved = moved or al.x ~= x0 or al.y ~= y0
        world.step(wr)
        world.step(wl)
      end
      assert.is_true(moved)
      for y = 0, terrains.HEIGHT - 1 do
        for x = 0, W - 1 do
          assert.are.equal(
            terrain.get(wr.terrain, x, y),
            terrain.get(wl.terrain, W - 1 - x, y),
            "angle " .. angle .. " cell " .. x .. "," .. y
          )
        end
      end
    end
  end)

  it("🦷 a snapshot taken mid-meal carries the meal on", function()
    local w = burrow(terrains.wall(60, 40), { 110, FEET }, { 20, FEET })
    chomp(w, 0)
    for _ = 1, 20 do
      world.step(w)
    end
    local copy = world.restore(world.snapshot(w))
    assert.are.same({ world.checksum(w) }, { world.checksum(copy) })
    assert.is_true(copy.cats[1].dig > 0)
    for _ = 1, 60 do
      world.step(w)
      world.step(copy)
    end
    assert.are.same({ world.checksum(w) }, { world.checksum(copy) })
    assert.are.same(w.cats[1].x, copy.cats[1].x)
  end)
end)

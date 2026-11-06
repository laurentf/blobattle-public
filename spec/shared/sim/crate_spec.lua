local cat = require("shared.sim.cat")
local crate = require("shared.sim.crate")
local rng = require("shared.sim.rng")
local rules = require("shared.sim.rules")
local terrain = require("shared.sim.terrain")
local terrains = require("spec.support.terrains")
local weapons = require("shared.sim.weapons.registry")
local world = require("shared.sim.world")

local function field(t, spawns, wind_max)
  return world.from_terrain({
    terrain = t or terrains.flat(),
    liquid = terrains.LIQUID,
    settings = { teams = 2, cats_per_team = 1, wind_max = wind_max or 0 },
    spawns = spawns or {
      { team = 1, index = 1, x = 40, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 160, y = terrains.GROUND - 1 },
    },
  })
end

local function find(events, kind)
  for _, e in ipairs(events) do
    if e.type == kind then
      return e
    end
  end
  return nil
end

local function skip_to_turn(w, number)
  local seen = {}
  while true do
    local played = w.teams[1].turns + w.teams[2].turns
    if played + 1 == number and w.turn.state == "turn_start" and w.turn.ticks == 0 then
      return seen
    end
    local inputs = nil
    if w.turn.state == "aiming" then
      inputs = { { team = w.turn.team, kind = "skip" } }
    end
    for _, e in ipairs(world.step(w, inputs)) do
      seen[#seen + 1] = e
    end
    assert.is_true(w.tick < 20000)
  end
end

local function until_aiming(w)
  local events = {}
  while w.turn.state ~= "aiming" do
    for _, e in ipairs(world.step(w)) do
      events[#events + 1] = e
    end
  end
  return events
end

local function pixel(k)
  return math.floor(k.x / 256), math.floor(k.y / 256)
end

local function placed_crate(w, x, y, weapon)
  local k = crate.new({
    id = w.next_crate,
    weapon = weapon or "cluster",
    x = x * 256 + 128,
    y = y * 256,
    chute = false,
  })
  w.next_crate = w.next_crate + 1
  w.crates[#w.crates + 1] = k
  return k
end

describe("📦 the crates (§5.10)", function()
  it("📦 uses §5.10's figures", function()
    assert.are.same({ 3, 3, 24, 8, 6, 384, 8, 300 }, {
      rules.CRATE_EVERY,
      rules.CRATE_MAX,
      rules.CRATE_EDGE,
      rules.CRATE_TRIES,
      rules.CRATE_SIZE,
      rules.CRATE_FALL,
      rules.CRATE_DRIFT,
      rules.CRATE_WAIT_TICKS,
    })
    assert.are.same({ "waddler", "jetpack", "cluster", "airstrike" }, rules.CRATE_WEAPONS)
    assert.are.same({ carve = 10, radius = 20, damage = 30, push = 1280 }, rules.CRATE_BLAST)
  end)

  it("📦 on the 3rd turn a crate comes down under its parachute, from above the map", function()
    local w = field()
    local before = skip_to_turn(w, 3)
    local dropped = find(before, "crate_dropped")
    assert.are.same({ "turn_start", 1, true }, { w.turn.state, #w.crates, w.crates[1].chute })
    local k = w.crates[1]
    assert.are.same(
      { dropped.crate, dropped.x, -1, rules.CRATE_FALL },
      { k.id, math.floor(k.x / 256), math.floor(k.y / 256), k.vy }
    )
  end)

  it("📦 drops one at the start of turns 3, 6 and 9, no sooner, with its column", function()
    local w = field()
    local events = skip_to_turn(w, 10)
    local drops, turns = {}, 1
    for _, e in ipairs(events) do
      if e.type == "turn_started" then
        turns = turns + 1
      elseif e.type == "crate_dropped" then
        drops[#drops + 1] = turns
        assert.is_true(e.x >= rules.CRATE_EDGE and e.x < w.terrain.width - rules.CRATE_EDGE)
        assert.is_nil(e.weapon)
      end
    end
    assert.are.same({ 3, 6, 9 }, drops)
    assert.are.equal(3, #w.crates)
    for _, k in ipairs(w.crates) do
      local found = false
      for _, id in ipairs(rules.CRATE_WEAPONS) do
        found = found or k.weapon == id
      end
      assert.is_true(found, k.weapon)
    end
  end)

  it(
    "📦 falls at 1.5 px a tick, lands, folds its chute, and only then the turn starts",
    function()
      local w = field()
      local dropped = find(skip_to_turn(w, 3), "crate_dropped")
      local landed = find(until_aiming(w), "crate_landed")
      local k = w.crates[1]
      assert.are.same({ type = "crate_landed", crate = k.id }, landed)
      assert.are.same({ false, 0, 0 }, { k.chute, k.vx, k.vy })
      assert.are.same({ dropped.x, terrains.GROUND - 1 }, { pixel(k) })
    end
  )

  it("📦 the waiting is counted: more than 60 ticks, as long as the fall", function()
    local w = field()
    skip_to_turn(w, 3)
    local start, landed_at = w.tick, nil
    while w.turn.state == "turn_start" do
      if find(world.step(w), "crate_landed") then
        landed_at = w.tick
      end
    end
    local fall = math.floor((terrains.GROUND + 1) * 256 / rules.CRATE_FALL)
    assert.is_true(landed_at - start >= fall - 1 and landed_at - start <= fall + 2)
    assert.is_true(w.tick - start > rules.TURN_START_TICKS)
    assert.is_true(w.tick - landed_at <= 1)
  end)

  it("📦 drifts with the wind while it hangs from its chute", function()
    local w = field(nil, nil, 10)
    skip_to_turn(w, 3)
    world.step(w)
    local k = w.crates[1]
    assert.are.equal(w.wind * rules.CRATE_DRIFT, k.vx)
    local x0 = k.x
    for _ = 1, 20 do
      world.step(w)
    end
    assert.are.equal(x0 + 20 * w.wind * rules.CRATE_DRIFT, k.x)
  end)

  it("📦 the active blob that walks onto it gives its team one of its weapon", function()
    local w = field()
    skip_to_turn(w, 3)
    local k = w.crates[1]
    local slot = weapons.index_of(k.weapon)
    local c = w.cats[w.turn.cat]
    local picked = find(until_aiming(w), "crate_picked")
    local side = pixel(k) > math.floor(c.x / 256) and 1 or -1
    world.step(w, { { team = w.turn.team, kind = "move", direction = side } })
    for _ = 1, 400 do
      picked = picked or find(world.step(w), "crate_picked")
      if picked then
        break
      end
    end
    assert.are.same({ type = "crate_picked", crate = k.id, cat = c.id, weapon = k.weapon }, picked)
    assert.are.same({ 1, 0, false }, { w.teams[c.team].ammo[slot], #w.crates, k.alive })
  end)

  it("📦 the other blobs pass through it; the blob whose turn it is picks it up", function()
    local w = field()
    until_aiming(w)
    local other = w.cats[2]
    local k = placed_crate(w, math.floor(other.x / 256), terrains.GROUND - 1, "jetpack")
    for _ = 1, 3 do
      world.step(w)
    end
    assert.is_true(k.alive)
    world.step(w, { { team = w.turn.team, kind = "skip" } })
    skip_to_turn(w, 2)
    world.step(w)
    assert.are.equal(2, w.turn.team)
    assert.is_false(k.alive)
    assert.are.equal(1, w.teams[2].ammo[weapons.index_of("jetpack")])
  end)

  it("📦 an explosion that reaches it sets it off on the next tick", function()
    local w = field()
    until_aiming(w)
    local k = placed_crate(w, 100, terrains.GROUND - 1)
    w.teams[1].ammo[weapons.index_of("airstrike")] = 1
    world.step(w, {
      { team = 1, kind = "fire", weapon = "airstrike", angle = 0, power = 1, target = 112 },
    })
    local destroyed_at, blast_at = nil, nil
    for _ = 1, 200 do
      for _, e in ipairs(world.step(w)) do
        if e.type == "crate_destroyed" then
          destroyed_at = destroyed_at or w.tick
        elseif e.type == "exploded" then
          if e.radius == rules.CRATE_BLAST.carve then
            blast_at = w.tick
          end
        end
      end
    end
    assert.is_false(k.alive)
    assert.are.equal(destroyed_at, blast_at)
    assert.is_true(destroyed_at ~= nil)
  end)

  it("📦 fallen into the water, it is lost", function()
    local w = field(terrains.shore(), {
      { team = 1, index = 1, x = 40, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 60, y = terrains.GROUND - 1 },
    })
    until_aiming(w)
    local k = placed_crate(w, 150, 0)
    local lost = nil
    for _ = 1, 200 do
      lost = lost or find(world.step(w), "crate_lost")
    end
    assert.are.same({ type = "crate_lost", crate = k.id }, lost)
    assert.are.same({ false, 0 }, { k.alive, #w.crates })
  end)

  it(
    "📦 one the lava rises over is lost at once, and frees its place for the next drop",
    function()
      local w = world.from_terrain({
        terrain = terrains.ledge(100, 80),
        liquid = terrains.GROUND - 2,
        liquid_kind = "lava",
        settings = { teams = 2, cats_per_team = 1, wind_max = 0 },
        spawns = {
          { team = 1, index = 1, x = 140, y = 79 },
          { team = 2, index = 1, x = 170, y = 79 },
        },
      })
      until_aiming(w)
      local low = placed_crate(w, 40, terrains.GROUND - 1)
      placed_crate(w, 120, 79)
      placed_crate(w, 150, 79)
      local events = skip_to_turn(w, 3)
      local lost = find(events, "crate_lost")
      assert.are.same({ "crate_lost", low.id }, { lost and lost.type, lost and lost.crate })
      assert.is_table(find(events, "crate_dropped"))
      assert.are.equal(terrains.GROUND - 4, w.liquid.level)
    end
  )

  it("📦 never more than 3 on the map: the 4th drop does not come", function()
    local w = field()
    local events = skip_to_turn(w, 13)
    local drops = 0
    for _, e in ipairs(events) do
      drops = drops + (e.type == "crate_dropped" and 1 or 0)
    end
    world.step(w)
    assert.are.same({ 3, 3 }, { drops, #w.crates })
  end)

  it("📦 the ground dug from under it, it falls again, without its chute, and rests", function()
    local w = field()
    until_aiming(w)
    local k = placed_crate(w, 100, terrains.GROUND - 1)
    terrain.carve(w.terrain, 100, terrains.GROUND + 3, 8)
    world.step(w)
    assert.is_true(k.vy > 0)
    local landed = nil
    for _ = 1, 60 do
      landed = landed or find(world.step(w), "crate_landed")
    end
    assert.is_nil(landed)
    local _, y = pixel(k)
    assert.are.same({ false, 0, true }, { k.chute, k.vy, y > terrains.GROUND - 1 })
  end)

  it("📦 settling waits for a crate that falls", function()
    local w = field()
    until_aiming(w)
    local k = placed_crate(w, 100, 10)
    world.step(w, { { team = 1, kind = "skip" } })
    local ticks, early = 0, false
    while w.turn.state == "settling" do
      world.step(w)
      ticks = ticks + 1
      early = early or (w.turn.state ~= "settling" and k.vy ~= 0)
    end
    assert.are.same({ false, 0, true }, { early, k.vy, ticks > 10 })
  end)

  it("📦 a bot given a crate weapon never plays it", function()
    local driver = require("shared.bots.driver")
    local w = field()
    until_aiming(w)
    for _, id in ipairs(rules.CRATE_WEAPONS) do
      w.teams[1].ammo[weapons.index_of(id)] = 1
    end
    w.teams[1].ammo[weapons.index_of("bazooka")] = 0
    w.teams[1].ammo[weapons.index_of("grenade")] = 0
    local d = driver.new({ seed = 3, teams = { 1, 2 }, level = "hard" })
    local fired = {}
    for _ = 1, 20000 do
      if w.teams[1].turns >= 1 or w.turn.state == "ended" then
        break
      end
      for _, e in ipairs(world.step(w, driver.inputs(d, w))) do
        if e.type == "fired" and w.cats[e.cat].team == 1 then
          fired[#fired + 1] = e.weapon
        end
      end
    end
    assert.are.same({ {}, 1 }, { fired, w.teams[1].turns })
  end)
end)

local GROUND = terrains.GROUND

local function arena(opts)
  opts = opts or {}
  return world.from_terrain({
    terrain = opts.terrain or terrains.flat(),
    liquid = opts.liquid or terrains.LIQUID,
    settings = { teams = 2, cats_per_team = 1, wind_max = opts.wind_max or 0 },
    spawns = opts.spawns or {
      { team = 1, index = 1, x = 40, y = GROUND - 1 },
      { team = 2, index = 1, x = 160, y = GROUND - 1 },
    },
  })
end

local function seek(events, kind)
  for i, e in ipairs(events) do
    if e.type == kind then
      return e, i
    end
  end
  return nil
end

local function copy(events)
  local out = {}
  for i, e in ipairs(events) do
    out[i] = e
  end
  return out
end

local function to_aiming(w)
  while w.turn.state ~= "aiming" do
    world.step(w)
  end
end

local function to_turn(w, number)
  local seen = {}
  while true do
    local played = w.teams[1].turns + w.teams[2].turns
    if played + 1 == number and w.turn.state == "turn_start" and w.turn.ticks == 0 then
      return seen
    end
    local inputs = nil
    if w.turn.state == "aiming" then
      inputs = { { team = w.turn.team, kind = "skip" } }
    end
    for _, e in ipairs(world.step(w, inputs)) do
      seen[#seen + 1] = e
    end
    assert.is_true(w.tick < 20000)
  end
end

local function spot(k)
  return math.floor(k.x / 256), math.floor(k.y / 256)
end

local function put(w, x, y, extra)
  extra = extra or {}
  local k = crate.new({
    id = w.next_crate,
    weapon = extra.weapon or "cluster",
    x = x * 256 + 128,
    y = y * 256,
    vx = extra.vx,
    vy = extra.vy,
    chute = extra.chute or false,
  })
  if extra.doomed then
    k.fuse = 1
  end
  w.next_crate = w.next_crate + 1
  w.crates[#w.crates + 1] = k
  return k
end

local function hung(w, x, y, vx)
  return put(w, x, y, { chute = true, vx = vx or 0, vy = rules.CRATE_FALL })
end

describe("📦 the crates, at the edges (§5.10)", function()
  it("📦 a side wall stops the drift for good, and the crate slides down along it", function()
    local w = arena({ terrain = terrains.wall(4, 60) })
    to_aiming(w)
    local k = hung(w, 110, 20, 80)
    for _ = 1, 200 do
      world.step(w)
      if spot(k) == 117 then
        break
      end
    end
    for _ = 1, 4 do
      world.step(w)
    end
    assert.are.same({ 117, 0, true }, { spot(k), k.vx, k.chute })
    for _ = 1, 100 do
      world.step(w)
    end
    local x, y = spot(k)
    assert.are.same({ 117, GROUND - 1, false }, { x, y, k.chute })
  end)

  it("📦 falling without its chute, it comes to rest on the next row crossing", function()
    local w = arena()
    to_aiming(w)
    local k = put(w, 100, GROUND - 2)
    for _ = 1, 20 do
      world.step(w)
    end
    assert.are.same({ 0, (GROUND - 1) * 256 }, { k.vy, k.y })
  end)

  it("📦 falling without its chute, it gathers speed past the chute's", function()
    local w = arena()
    to_aiming(w)
    local k = put(w, 100, 10)
    for _ = 1, 12 do
      world.step(w)
    end
    assert.are.equal(12 * rules.GRAVITY, k.vy)
  end)

  it("📦 lost as soon as the centre of its box is under the liquid, not before", function()
    local spawns = {
      { team = 1, index = 1, x = 160, y = 79 },
      { team = 2, index = 1, x = 180, y = 79 },
    }
    local deep = arena({ terrain = terrains.ledge(150, 80), liquid = GROUND - 4, spawns = spawns })
    to_aiming(deep)
    local k = put(deep, 50, GROUND - 1)
    assert.are.same({ type = "crate_lost", crate = k.id }, seek(world.step(deep), "crate_lost"))
    local shallow =
      arena({ terrain = terrains.ledge(150, 80), liquid = GROUND - 3, spawns = spawns })
    to_aiming(shallow)
    local j = put(shallow, 50, GROUND - 1)
    for _ = 1, 3 do
      world.step(shallow)
    end
    assert.is_true(j.alive)
  end)

  it("📦 lost beyond 64 px from an edge, not before", function()
    local w = arena()
    to_aiming(w)
    local near_left = put(w, -64, 40)
    local far_left = put(w, -65, 40)
    local near_right = put(w, w.terrain.width + 63, 40)
    local far_right = put(w, w.terrain.width + 64, 40)
    world.step(w)
    assert.are.same(
      { true, false, true, false },
      { near_left.alive, far_left.alive, near_right.alive, far_right.alive }
    )
  end)

  it("📦 a doomed crate says crate_destroyed, then explodes 2 px above its feet", function()
    local w = arena()
    to_aiming(w)
    put(w, 100, GROUND - 1, { doomed = true })
    local events = copy(world.step(w))
    local _, destroyed = seek(events, "crate_destroyed")
    local exploded, at = seek(events, "exploded")
    assert.is_true(destroyed ~= nil and at ~= nil and destroyed < at)
    assert.are.same(
      { 100, GROUND - 3, rules.CRATE_BLAST.carve },
      { exploded.x, exploded.y, exploded.radius }
    )
  end)

  it("📦 a crate an explosion just doomed cannot be picked up", function()
    local w = arena()
    to_aiming(w)
    local c = w.cats[w.turn.cat]
    local cx = math.floor(c.x / 256)
    put(w, cx + 10, GROUND - 1, { doomed = true })
    local b = put(w, cx, GROUND - 1)
    assert.is_nil(seek(world.step(w), "crate_picked"))
    assert.are.same({ true, 1 }, { b.alive, b.fuse })
  end)

  it("📦 picked the very tick its box first meets the active blob's", function()
    local w = arena()
    to_aiming(w)
    local c = w.cats[w.turn.cat]
    local cx, cy = math.floor(c.x / 256), math.floor(c.y / 256)
    local k = hung(w, cx, 50)
    local picked = nil
    for _ = 1, 100 do
      picked = seek(world.step(w), "crate_picked")
      local _, ky = spot(k)
      if picked then
        assert.is_true(ky >= cy - rules.CAT_HEIGHT + 1, "picked at row " .. ky)
        break
      end
      assert.is_true(ky < cy - rules.CAT_HEIGHT + 1, "left overlapping at row " .. ky)
    end
    assert.is_not_nil(picked)
  end)

  it("📦 side by side, the boxes must overlap: 6 px apart is not touching", function()
    local w = arena()
    to_aiming(w)
    local c = w.cats[w.turn.cat]
    local cx = math.floor(c.x / 256)
    local apart = put(w, cx + 6, GROUND - 1)
    local left = put(w, cx - 6, GROUND - 1)
    for _ = 1, 3 do
      world.step(w)
    end
    assert.are.same({ true, true }, { apart.alive, left.alive })
    local inside = put(w, cx + 5, GROUND - 1)
    world.step(w)
    assert.is_false(inside.alive)
  end)

  it("📦 once the turn is over, the blob that played picks nothing up", function()
    local w = arena()
    to_aiming(w)
    world.step(w, { { team = w.turn.team, kind = "skip" } })
    while w.turn.state ~= "turn_end" do
      world.step(w)
    end
    local c = w.cats[w.turn.cat]
    local k = put(w, math.floor(c.x / 256), math.floor(c.y / 256))
    assert.is_nil(seek(world.step(w), "crate_picked"))
    assert.is_true(k.alive)
  end)

  it("📦 an explosion's reach is measured to the centre of the crate's box", function()
    local w = arena()
    to_aiming(w)
    put(w, 100, 79, { doomed = true })
    local below = put(w, 100, GROUND - 1)
    world.step(w)
    assert.are.same({ true, 1 }, { below.alive, below.fuse })
  end)

  it("📦 a crate blast dooms another 15 px away, not one 21 px away", function()
    local w = arena()
    to_aiming(w)
    put(w, 100, GROUND - 1, { doomed = true })
    local near = put(w, 115, GROUND - 1)
    local far = put(w, 121, GROUND - 1)
    world.step(w)
    assert.are.same({ 1, -1 }, { near.fuse, far.fuse })
  end)

  it("📦 settling waits for a doomed crate to go off", function()
    local w = arena()
    to_aiming(w)
    put(w, 100, 79, { doomed = true })
    local below = put(w, 100, GROUND - 1)
    world.step(w, { { team = w.turn.team, kind = "skip" } })
    assert.are.same({ "settling", 1 }, { w.turn.state, below.fuse })
    local state = w.turn.state
    local events = copy(world.step(w))
    assert.is_not_nil(seek(events, "crate_destroyed"))
    assert.are.equal("settling", state)
  end)

  it("📦 a crate goes off before the blobs move: they fly in that same tick", function()
    local w = arena()
    to_aiming(w)
    local c = w.cats[w.turn.cat]
    local x0 = c.x
    put(w, math.floor(c.x / 256) + 8, GROUND - 1, { doomed = true })
    world.step(w)
    assert.is_true(c.x ~= x0)
  end)

  it("📦 its box is 6 px wide, from 3 px left of its column to 2 px right", function()
    local w = arena({
      terrain = terrains.cliff(10),
      spawns = {
        { team = 1, index = 1, x = 40, y = GROUND - 11 },
        { team = 2, index = 1, x = 160, y = GROUND - 1 },
      },
    })
    to_aiming(w)
    local held = put(w, 102, GROUND - 11)
    local off = put(w, 103, GROUND - 11)
    for _ = 1, 3 do
      world.step(w)
    end
    local _, held_y = spot(held)
    local _, off_y = spot(off)
    assert.are.same({ GROUND - 11, true }, { held_y, off_y > GROUND - 11 })
  end)

  it("📦 never dropped over water: no land above the liquid in reach, no crate", function()
    local t = terrain.new(terrains.WIDTH, terrains.HEIGHT)
    for y = 0, terrains.HEIGHT - 1 do
      for x = 0, terrains.WIDTH - 1 do
        local land = (x <= 20 or x >= terrains.WIDTH - 20) and y >= GROUND
        if land or y >= terrains.HEIGHT - 4 then
          terrain.set(t, x, y, terrain.SOIL)
        end
      end
    end
    local w = arena({
      terrain = t,
      spawns = {
        { team = 1, index = 1, x = 10, y = GROUND - 1 },
        { team = 2, index = 1, x = terrains.WIDTH - 10, y = GROUND - 1 },
      },
    })
    local events = to_turn(w, 10)
    assert.is_nil(seek(events, "crate_dropped"))
  end)

  it("📦 after the wind, up to 8 columns, then the weapon, all on the sim stream", function()
    local width = terrains.WIDTH
    local t = terrain.new(width, terrains.HEIGHT)
    for y = GROUND, terrains.HEIGHT - 1 do
      for x = 0, 50 do
        terrain.set(t, x, y, terrain.SOIL)
      end
    end
    local w = arena({
      terrain = t,
      wind_max = 3,
      spawns = {
        { team = 1, index = 1, x = 10, y = GROUND - 1 },
        { team = 2, index = 1, x = 40, y = GROUND - 1 },
      },
    })
    local function first_solid_above_liquid(x)
      for y = 0, t.height - 1 do
        if terrain.solid(t, x, y) then
          return y < w.liquid.level
        end
      end
      return false
    end
    local drops, retried = 0, false
    for _ = 1, 40000 do
      if w.teams[1].turns + w.teams[2].turns >= 20 then
        break
      end
      local inputs = nil
      if w.turn.state == "aiming" then
        inputs = { { team = w.turn.team, kind = "skip" } }
      end
      local s = { state = w.rng.sim.state, multiplier = w.rng.sim.multiplier }
      local alive = 0
      for _, k in ipairs(w.crates) do
        alive = alive + (k.alive and 1 or 0)
      end
      local number = w.teams[1].turns + w.teams[2].turns + 2
      local events = copy(world.step(w, inputs))
      local started = seek(events, "turn_started")
      if started then
        assert.are.equal(rng.range(s, -3, 3), started.wind)
        local column, tries = nil, 0
        if number % 3 == 0 and alive < 3 then
          for _ = 1, 8 do
            tries = tries + 1
            local x = rng.range(s, 24, width - 25)
            if first_solid_above_liquid(x) then
              column = x
              break
            end
          end
        end
        local dropped = seek(events, "crate_dropped")
        if column then
          local weapon = rules.CRATE_WEAPONS[rng.range(s, 1, 4)]
          drops = drops + 1
          retried = retried or tries > 1
          assert.are.same({ column, weapon }, { dropped.x, w.crates[#w.crates].weapon })
        else
          assert.is_nil(dropped)
        end
        assert.are.equal(s.state, w.rng.sim.state)
      end
    end
    assert.is_true(drops >= 2 and retried, drops .. " drops")
  end)

  it(
    "📦 dropped at its column's centre, lands 68 ticks later, snapped to the row, drifted 68 times",
    function()
      local w = arena({ wind_max = 10 })
      local dropped = seek(to_turn(w, 3), "crate_dropped")
      local k = w.crates[1]
      assert.are.equal(dropped.x * 256 + 128, k.x)
      local x0, vx = k.x, k.vx
      assert.is_true(vx ~= 0)
      local n = 0
      repeat
        n = n + 1
        local landed = seek(world.step(w), "crate_landed")
      until landed or n > 400
      assert.are.same({ 68, (GROUND - 1) * 256, x0 + 68 * vx }, { n, k.y, k.x })
    end
  )

  it("📦 every crate gets its own id", function()
    local w = arena()
    local ids = {}
    for _, e in ipairs(to_turn(w, 7)) do
      if e.type == "crate_dropped" then
        ids[#ids + 1] = e.crate
      end
    end
    assert.are.same({ { 1, 2 }, 3 }, { ids, w.next_crate })
  end)

  it("📦 turn_start gives up waiting after 300 ticks on a very tall map", function()
    local t = terrain.new(terrains.WIDTH, 600)
    for y = 580, 599 do
      for x = 0, terrains.WIDTH - 1 do
        terrain.set(t, x, y, terrain.SOIL)
      end
    end
    local w = arena({
      terrain = t,
      liquid = 592,
      spawns = {
        { team = 1, index = 1, x = 40, y = 579 },
        { team = 2, index = 1, x = 160, y = 579 },
      },
    })
    to_turn(w, 3)
    local ticks = 0
    while w.turn.state == "turn_start" do
      world.step(w)
      ticks = ticks + 1
    end
    assert.are.same({ 300, true }, { ticks, w.crates[1].chute })
  end)
  it(
    "📦 a quake's 300 ticks up, a crate still falling is set down and its chute folded",
    function()
      local w = world.from_terrain({
        terrain = terrains.ceiling(60, 400),
        liquid = terrains.LIQUID,
        seed = 1,
        settings = { teams = 2, cats_per_team = 2, wind_max = 0 },
        spawns = {
          { team = 1, index = 1, x = 20, y = GROUND - 1 },
          { team = 1, index = 2, x = 40, y = GROUND - 1 },
          { team = 2, index = 1, x = 360, y = GROUND - 1 },
          { team = 2, index = 2, x = 380, y = GROUND - 1 },
        },
      })
      for _ = 1, 40000 do
        if w.turn.state == "quake" then
          break
        end
        local inputs = nil
        if w.turn.state == "aiming" then
          inputs = { { team = w.turn.team, kind = "skip" } }
        end
        world.step(w, inputs)
      end
      assert.are.equal("quake", w.turn.state)
      local swinger = w.cats[1]
      assert.is_true(cat.grapple(swinger, { terrain = w.terrain, angle = 256, events = w.events }))
      local falling, hanging = nil, nil
      while w.turn.state == "quake" do
        if w.turn.ticks == 295 then
          falling = put(w, 200, 62)
          hanging = hung(w, 250, 62)
        end
        world.step(w)
      end
      assert.are.same(
        { 0, 0, false, false },
        { falling.vy, hanging.vy, hanging.chute, falling.chute }
      )
    end
  )
  it("📦 doomed by a shell in one tick, it goes off at the start of the next", function()
    local w = arena()
    to_aiming(w)
    local k = put(w, 100, GROUND - 1)
    w.teams[1].ammo[require("shared.sim.weapons.registry").index_of("airstrike")] = 1
    world.step(w, {
      { team = 1, kind = "fire", weapon = "airstrike", angle = 0, power = 1, target = 100 },
    })
    local doomed_at, destroyed_at = nil, nil
    for _ = 1, 200 do
      local events = world.step(w)
      if doomed_at == nil and k.fuse > 0 then
        doomed_at = w.tick
      end
      if seek(events, "crate_destroyed") then
        destroyed_at = w.tick
        break
      end
    end
    assert.is_not_nil(doomed_at)
    assert.are.equal(doomed_at + 1, destroyed_at)
  end)
end)

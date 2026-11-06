local cat = require("shared.sim.cat")
local fixed = require("shared.sim.fixed")
local rules = require("shared.sim.rules")
local terrains = require("spec.support.terrains")
local turn = require("shared.sim.turn")
local weapons = require("shared.sim.weapons.registry")
local world = require("shared.sim.world")

local function duel(fields)
  fields = fields or {}
  return world.from_terrain({
    terrain = fields.terrain or terrains.flat(),
    liquid = terrains.LIQUID,
    settings = fields.settings or { teams = 2, cats_per_team = 1, wind_max = 0 },
    spawns = fields.spawns or {
      { team = 1, index = 1, x = 40, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 160, y = terrains.GROUND - 1 },
    },
  })
end

local function run(w, ticks, inputs_at)
  local events = {}
  for i = 1, ticks do
    local inputs = inputs_at and inputs_at[i] or nil
    for _, e in ipairs(world.step(w, inputs)) do
      events[#events + 1] = e
    end
  end
  return events
end

local function until_state(w, state, limit)
  for _ = 1, limit or 2000 do
    if w.turn.state == state then
      return true
    end
    world.step(w)
  end
  return w.turn.state == state
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

local FIRE = { team = 1, kind = "fire", weapon = "bazooka", angle = 64, power = 60 }

describe("⏱️ the turn", function()
  it("⏱️ ignores a fire input outside aiming", function()
    local w = duel()
    assert.are.equal("turn_start", w.turn.state)
    world.step(w, { FIRE })
    assert.are.equal(0, #w.projectiles)
    assert.are.equal("turn_start", w.turn.state)
  end)

  it("⏱️ ignores out-of-bounds inputs without raising", function()
    local w = duel()
    until_state(w, "aiming")
    local bad = {
      { team = 1, kind = "fire", weapon = "banana", angle = 64, power = 60 },
      { team = 1, kind = "fire", weapon = "bazooka", angle = 2000, power = 60 },
      { team = 1, kind = "fire", weapon = "bazooka", angle = 64, power = 0 },
      { team = 1, kind = "fire", weapon = "bazooka", angle = 64.5, power = 60 },
      { team = 1, kind = "fire", weapon = "grenade", angle = 64, power = 60, fuse = 9 },
      { team = 1, kind = "move", direction = 5 },
      { team = 1, kind = "jump", direction = 0 },
      { team = 1, kind = "dance" },
      { team = 1 },
    }
    for _, input in ipairs(bad) do
      assert.has_no.errors(function()
        world.step(w, { input })
      end)
    end
    assert.are.equal("aiming", w.turn.state)
    assert.are.equal(0, #w.projectiles)
    assert.are.equal(0, w.cats[1].walk)
  end)

  it("⏱️ raises on a transition outside the table", function()
    local w = duel()
    assert.has_error(function()
      turn.transition(w, "flight")
    end)
  end)

  it("⏱️ runs start, aiming, flight, retreat, settling, end, then hands over", function()
    local w = duel()
    local seen = { w.turn.state }
    for _ = 1, 3000 do
      if w.turn.state == "aiming" and w.turn.team == 1 and #w.projectiles == 0 then
        world.step(w, { FIRE })
      else
        world.step(w)
      end
      if seen[#seen] ~= w.turn.state then
        seen[#seen + 1] = w.turn.state
      end
      if w.turn.team == 2 then
        break
      end
    end
    assert.are.same(
      { "turn_start", "aiming", "flight", "retreat", "settling", "turn_end", "turn_start" },
      seen
    )
  end)

  it("⏱️ waits exactly 60 ticks (2 s) before aiming", function()
    assert.are.equal(60, rules.TURN_START_TICKS)
    local w = duel()
    run(w, rules.TURN_START_TICKS - 1)
    assert.are.equal("turn_start", w.turn.state)
    run(w, 1)
    assert.are.equal("aiming", w.turn.state)
  end)

  it("⏱️ ends a turn without a shot when the timer runs out", function()
    local w = duel({ settings = { teams = 2, cats_per_team = 1, wind_max = 0, turn_seconds = 30 } })
    until_state(w, "aiming")
    run(w, 899)
    assert.are.equal("aiming", w.turn.state)
    run(w, 1)
    assert.are.equal("settling", w.turn.state)
    assert.is_true(until_state(w, "turn_start"))
    assert.are.equal(2, w.turn.team)
  end)

  it("⏱️ ignores the inactive team", function()
    local w = duel()
    until_state(w, "aiming")
    world.step(w, { { team = 2, kind = "fire", weapon = "bazooka", angle = 64, power = 60 } })
    assert.are.equal("aiming", w.turn.state)
    world.step(w, { { team = 2, kind = "move", direction = 1 } })
    assert.are.equal(0, w.cats[2].walk)
  end)

  it("⏱️ walks the active cat while aiming and stops it when it fires", function()
    local w = duel()
    until_state(w, "aiming")
    run(w, 20, { [1] = { { team = 1, kind = "move", direction = 1 } } })
    assert.is_true(w.cats[1].x > 40 * 256 + 128)
    world.step(w, { FIRE })
    assert.are.equal("flight", w.turn.state)
    assert.are.equal(0, w.cats[1].walk)
  end)

  it("⏱️ passes the turn on skip", function()
    local w = duel()
    until_state(w, "aiming")
    local events = run(w, 3, { [1] = { { team = 1, kind = "skip" } } })
    assert.are_not.equal("aiming", w.turn.state)
    assert.are.equal(1, count(events, "turn_ended"))
    assert.is_true(until_state(w, "aiming"))
    assert.are.equal(2, w.turn.team)
  end)

  it("⏱️ ends the turn when the active cat hurts itself falling", function()
    local w = duel({
      terrain = terrains.cliff(60),
      spawns = {
        { team = 1, index = 1, x = 95, y = terrains.GROUND - 61 },
        { team = 2, index = 1, x = 170, y = terrains.GROUND - 1 },
      },
    })
    until_state(w, "aiming")
    local events = run(w, 120, { [1] = { { team = 1, kind = "move", direction = 1 } } })
    assert.is_true(w.cats[1].hp < 100)
    assert.are.equal(1, count(events, "turn_ended"))
    assert.are.equal(2, w.turn.team)
  end)

  it("⏱️ rotates the cats of a team and skips a dead team", function()
    local w = duel({
      settings = { teams = 3, cats_per_team = 2, wind_max = 0 },
      spawns = {
        { team = 1, index = 1, x = 20, y = terrains.GROUND - 1 },
        { team = 1, index = 2, x = 50, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 80, y = terrains.GROUND - 1 },
        { team = 2, index = 2, x = 110, y = terrains.GROUND - 1 },
        { team = 3, index = 1, x = 140, y = terrains.GROUND - 1 },
        { team = 3, index = 2, x = 170, y = terrains.GROUND - 1 },
      },
    })
    w.cats[3].hp, w.cats[4].hp = 0, 0
    local order = {}
    for _ = 1, 4 do
      until_state(w, "aiming")
      order[#order + 1] = w.turn.cat
      world.step(w, { { team = w.turn.team, kind = "skip" } })
      until_state(w, "turn_start")
    end
    assert.are.same({ 1, 5, 2, 6 }, order)
    assert.is_false(w.cats[3].alive)
  end)

  it("⏱️ declares the last team standing the winner", function()
    local w = duel({
      terrain = terrains.shore(),
      spawns = {
        { team = 1, index = 1, x = 90, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 40, y = terrains.GROUND - 1 },
      },
    })
    until_state(w, "aiming")
    local events = run(w, 400, { [1] = { { team = 1, kind = "move", direction = 1 } } })
    assert.is_false(w.cats[1].alive)
    assert.are.equal("ended", w.turn.state)
    assert.are.same({ winner = 2 }, w.result)
    assert.are.equal(1, count(events, "game_ended"))
    assert.are.same({}, world.step(w, { FIRE }))
  end)

  it("⏱️ ends the turn of a cat that drowns, and plays on", function()
    local w = duel({
      terrain = terrains.shore(),
      settings = { teams = 2, cats_per_team = 2, wind_max = 0 },
      spawns = {
        { team = 1, index = 1, x = 90, y = terrains.GROUND - 1 },
        { team = 1, index = 2, x = 20, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 40, y = terrains.GROUND - 1 },
        { team = 2, index = 2, x = 60, y = terrains.GROUND - 1 },
      },
    })
    until_state(w, "aiming")
    run(w, 200, { [1] = { { team = 1, kind = "move", direction = 1 } } })
    assert.is_false(w.cats[1].alive)
    assert.are.equal(2, w.turn.team)
    assert.are_not.equal("ended", w.turn.state)
  end)

  it("⏱️ resets the hurt flags at every turn start", function()
    local w = duel({
      terrain = terrains.flat(300),
      spawns = {
        { team = 1, index = 1, x = 140, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 160, y = terrains.GROUND - 1 },
      },
    })
    until_state(w, "aiming")
    world.step(w, { { team = 1, kind = "skip" } })
    until_state(w, "aiming")
    assert.are.equal(2, w.turn.team)
    world.step(w, { { team = 2, kind = "fire", weapon = "bazooka", angle = 540, power = 60 } })
    until_state(w, "aiming")
    assert.is_true(w.cats[1].hp < 100)
    assert.are.equal(1, w.turn.team)
    run(w, 10)
    assert.are.equal("aiming", w.turn.state)
  end)

  it("⏱️ keeps the retreat exactly 90 ticks", function()
    local w = duel()
    until_state(w, "aiming")
    world.step(w, { FIRE })
    until_state(w, "retreat")
    local ticks = 0
    while w.turn.state == "retreat" do
      world.step(w)
      ticks = ticks + 1
    end
    assert.are.equal(90, ticks)
  end)

  it("⏱️ cuts the retreat short when the active cat gets hurt", function()
    local w = duel({
      terrain = terrains.cliff(60),
      spawns = {
        { team = 1, index = 1, x = 95, y = terrains.GROUND - 61 },
        { team = 2, index = 1, x = 170, y = terrains.GROUND - 1 },
      },
    })
    until_state(w, "aiming")
    world.step(w, { { team = 1, kind = "fire", weapon = "bazooka", angle = 320, power = 50 } })
    until_state(w, "retreat")
    local ticks = 0
    world.step(w, { { team = 1, kind = "move", direction = 1 } })
    while w.turn.state == "retreat" do
      world.step(w)
      ticks = ticks + 1
    end
    assert.is_true(w.cats[1].hp < 100)
    assert.is_true(ticks < 89, "retreat lasted " .. ticks)
  end)

  it("⏱️ releases the held direction whenever the cat may no longer walk", function()
    local w = duel({ settings = { teams = 2, cats_per_team = 1, wind_max = 0, turn_seconds = 30 } })
    until_state(w, "aiming")
    run(w, 900, { [1] = { { team = 1, kind = "move", direction = 1 } } })
    assert.are.equal(0, w.cats[1].walk)
    local x = w.cats[1].x
    run(w, 20)
    assert.are.equal(x, w.cats[1].x)

    local v = duel()
    until_state(v, "aiming")
    world.step(v, { { team = 1, kind = "move", direction = 1 } })
    world.step(v, { { team = 1, kind = "skip" } })
    assert.are.equal(0, v.cats[1].walk)

    local r = duel()
    until_state(r, "aiming")
    world.step(r, { FIRE })
    until_state(r, "retreat")
    world.step(r, { { team = 1, kind = "move", direction = -1 } })
    until_state(r, "settling")
    assert.are.equal(0, r.cats[1].walk)
  end)

  it(
    "⏱️ lets the cat move only while aiming or retreating, and skip only while aiming",
    function()
      local w = duel()
      world.step(w, { { team = 1, kind = "move", direction = 1 } })
      assert.are.equal(0, w.cats[1].walk)
      until_state(w, "aiming")
      world.step(w, { FIRE })
      assert.are.equal("flight", w.turn.state)
      world.step(w, { { team = 1, kind = "move", direction = 1 } })
      assert.are.equal(0, w.cats[1].walk)
      until_state(w, "retreat")
      world.step(w, { { team = 1, kind = "skip" } })
      assert.are.equal("retreat", w.turn.state)
    end
  )

  it("⏱️ times the turn from its setting", function()
    local w = duel({ settings = { teams = 2, cats_per_team = 1, wind_max = 0, turn_seconds = 60 } })
    until_state(w, "aiming")
    run(w, 1799)
    assert.are.equal("aiming", w.turn.state)
    run(w, 1)
    assert.are_not.equal("aiming", w.turn.state)
  end)

  it("⏱️ reports the shot and arms the grenade with the fuse asked, 3 s by default", function()
    local function fuse_ticks(fuse)
      local w = duel()
      until_state(w, "aiming")
      local fired_at, exploded_at
      local input =
        { team = 1, kind = "fire", weapon = "grenade", angle = 128, power = 20, fuse = fuse }
      for tick = 1, 400 do
        for _, e in ipairs(world.step(w, tick == 1 and { input } or nil)) do
          if e.type == "fired" then
            fired_at = tick
            assert.are.same({ type = "fired", cat = 1, weapon = "grenade" }, e)
          elseif e.type == "exploded" and exploded_at == nil then
            exploded_at = tick
          end
        end
      end
      return exploded_at - fired_at
    end
    assert.are.equal(90 - 1, fuse_ticks(nil))
    assert.are.equal(30 - 1, fuse_ticks(1))
    assert.are.equal(150 - 1, fuse_ticks(5))
  end)

  it("⏱️ spends finite ammunition and refuses an empty weapon", function()
    local w = duel()
    local slot = weapons.index_of("grenade")
    w.teams[1].ammo[slot] = 1
    until_state(w, "aiming")
    local grenade = { team = 1, kind = "fire", weapon = "grenade", angle = 64, power = 40 }
    world.step(w, { grenade })
    assert.are.equal(0, w.teams[1].ammo[slot])
    for _ = 1, 3 do
      until_state(w, "aiming")
      if w.turn.team == 2 then
        world.step(w, { { team = 2, kind = "skip" } })
      end
    end
    until_state(w, "aiming")
    assert.are.equal(1, w.turn.team)
    world.step(w, { grenade })
    assert.are.equal("aiming", w.turn.state)
    assert.are.equal(0, #w.projectiles)
  end)

  it("⏱️ starts with the team it is told to", function()
    local w = world.from_terrain({
      terrain = terrains.flat(),
      liquid = terrains.LIQUID,
      settings = { teams = 2, cats_per_team = 1 },
      first_team = 2,
      spawns = {
        { team = 1, index = 1, x = 40, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 160, y = terrains.GROUND - 1 },
      },
    })
    assert.are.equal(2, w.turn.team)
  end)

  it("⏱️ fires from the exact centre of the box, so mirrored shots land mirrored", function()
    local function landing(x, angle)
      local w = duel({
        terrain = terrains.flat(300),
        spawns = {
          { team = 1, index = 1, x = x, y = terrains.GROUND - 1 },
          { team = 2, index = 1, x = 150, y = 20 },
        },
      })
      until_state(w, "aiming")
      world.step(w, { { team = 1, kind = "fire", weapon = "bazooka", angle = angle, power = 40 } })
      for _ = 1, 300 do
        for _, e in ipairs(world.step(w)) do
          if e.type == "exploded" then
            return e.x
          end
        end
      end
    end
    for _, angle in ipairs({ 40, 100, 200 }) do
      assert.are.equal(300 - 1 - landing(60, angle), landing(240, 512 - angle), "angle " .. angle)
    end
  end)

  it("⏱️ ignores inputs that are not even tables", function()
    local w = duel()
    until_state(w, "aiming")
    assert.has_no.errors(function()
      world.step(w, { 42, "fire", true })
    end)
    assert.are.equal("aiming", w.turn.state)
  end)

  it("⏱️ calls the weapon's on_fire hook with the new projectile", function()
    local bazooka = weapons.get("bazooka")
    local seen
    bazooka.on_fire = function(api, p)
      seen = { api = api, p = p, x = p.x, y = p.y, age = p.age }
    end
    local w = duel()
    until_state(w, "aiming")
    local ok, err = pcall(world.step, w, { FIRE })
    bazooka.on_fire = nil
    assert.is_true(ok, err)
    assert.is_not_nil(seen)
    assert.are.equal(w.projectiles[1], seen.p)
    assert.are.equal(0, seen.age)
    local px, py = cat.pixel(w.cats[1])
    assert.are.same({ px * fixed.FP, (2 * py - 5) * 128 }, { seen.x, seen.y })
    assert.is_function(seen.api.explode)
  end)

  it("⏱️ calls a draw when no team is left", function()
    local w = duel()
    w.cats[1].hp, w.cats[2].hp = 0, 0
    until_state(w, "aiming")
    world.step(w, { { team = 1, kind = "skip" } })
    run(w, 400)
    assert.are.equal("ended", w.turn.state)
    assert.is_nil(w.result.winner)
  end)

  local function sheltered()
    return duel({
      terrain = terrains.pockets({ { 10, 100 }, { 190, 100 } }),
      spawns = {
        { team = 1, index = 1, x = 10, y = 100 },
        { team = 2, index = 1, x = 190, y = 100 },
      },
    })
  end

  it("⏱️ calls a draw when the round limit ends on equal hit points", function()
    local w = sheltered()
    for _ = 1, 400 do
      if w.turn.state == "ended" then
        break
      end
      until_state(w, "aiming")
      world.step(w, { { team = w.turn.team, kind = "skip" } })
      until_state(w, "turn_start")
    end
    assert.are.equal("ended", w.turn.state)
    assert.is_nil(w.result.winner)
  end)

  it("⏱️ stops after the round limit and ranks by hit points", function()
    local w = sheltered()
    w.cats[1].hp = 40
    for _ = 1, 400 do
      if w.turn.state == "ended" then
        break
      end
      until_state(w, "aiming")
      world.step(w, { { team = w.turn.team, kind = "skip" } })
      until_state(w, "turn_start")
    end
    assert.are.equal("ended", w.turn.state)
    assert.are.equal(30, w.teams[1].turns)
    assert.are.same({ winner = 2 }, w.result)
  end)

  it("⏱️ draws the wind at every turn start within its bound", function()
    local w = duel({ settings = { teams = 2, cats_per_team = 1, wind_max = 10 } })
    local winds = {}
    for _ = 1, 12 do
      until_state(w, "aiming")
      winds[#winds + 1] = w.wind
      assert.is_true(w.wind >= -10 and w.wind <= 10)
      world.step(w, { { team = w.turn.team, kind = "skip" } })
      until_state(w, "turn_start")
    end
    local distinct = {}
    for _, v in ipairs(winds) do
      distinct[v] = true
    end
    local n = 0
    for _ in pairs(distinct) do
      n = n + 1
    end
    assert.is_true(n > 3)
  end)
end)

describe("🌋 the rising lava (§5.3)", function()
  local function field(kind, spawns, per_team)
    return world.from_terrain({
      terrain = spawns.terrain or terrains.flat(),
      liquid = terrains.LIQUID,
      liquid_kind = kind,
      settings = { teams = 2, cats_per_team = per_team or 1, wind_max = 0 },
      spawns = spawns,
    })
  end

  local function round_of(w)
    local rose, ended = {}, 0
    for _ = 1, 20000 do
      local inputs = nil
      if w.turn.state == "aiming" then
        inputs = { { team = w.turn.team, kind = "skip" } }
      end
      for _, e in ipairs(world.step(w, inputs)) do
        if e.type == "liquid_rose" then
          rose[#rose + 1] = e.level
        elseif e.type == "turn_ended" then
          ended = ended + 1
        end
      end
      if ended == 2 and w.turn.state ~= "turn_end" then
        return rose
      end
    end
    error("the round never ended")
  end

  local SPAWNS = {
    { team = 1, index = 1, x = 40, y = terrains.GROUND - 1 },
    { team = 2, index = 1, x = 160, y = terrains.GROUND - 1 },
  }

  it("🌋 uses §5.3's figures", function()
    assert.are.same({ 2, 1 }, { rules.LAVA_RISE, rules.LAVA_RISE_FROM })
  end)

  it("🌋 rises 2 px at the end of every round, from the first, and says so", function()
    local w = field("lava", SPAWNS)
    local start = w.liquid.level
    assert.are.equal(0, w.rounds)
    for round = 1, 7 do
      local rose = round_of(w)
      local level = start - rules.LAVA_RISE * round
      assert.are.same({ round, level }, { w.rounds, w.liquid.level }, "round " .. round)
      assert.are.same({ level }, rose, "round " .. round)
    end
  end)

  it("🌲 the forest's water never rises", function()
    local w = field("water", SPAWNS)
    local start = w.liquid.level
    for round = 1, 7 do
      assert.are.same({}, round_of(w))
      assert.are.same({ round, start }, { w.rounds, w.liquid.level })
    end
  end)

  local function pit()
    local terrain = require("shared.sim.terrain")
    local t = terrains.flat()
    for x = 55, 64 do
      for y = terrains.GROUND, terrains.LIQUID + 1 do
        terrain.set(t, x, y, terrain.AIR)
      end
    end
    return t
  end

  local function skip_until(w, fn)
    for _ = 1, 20000 do
      local inputs = w.turn.state == "aiming" and { { team = w.turn.team, kind = "skip" } } or nil
      local events = world.step(w, inputs)
      if fn(events) then
        return events
      end
    end
    error("never happened")
  end

  local function find(events, kind, id)
    for _, e in ipairs(events) do
      if e.type == kind and (id == nil or e.cat == id) then
        return e
      end
    end
    return nil
  end

  it("🌋 drowns the blob it reaches at once, before the next turn starts", function()
    local w = field("lava", {
      terrain = pit(),
      { team = 1, index = 1, x = 40, y = terrains.GROUND - 1 },
      { team = 1, index = 2, x = 60, y = terrains.LIQUID + 1 },
      { team = 2, index = 1, x = 140, y = terrains.GROUND - 1 },
      { team = 2, index = 2, x = 170, y = terrains.GROUND - 1 },
    }, 2)
    local low = w.cats[2]
    local events = skip_until(w, function(e)
      return find(e, "liquid_rose") ~= nil
    end)
    local died = find(events, "died", low.id)
    assert.are.same({ "liquid", false }, { died and died.cause, low.alive })
    local started = find(events, "turn_started")
    assert.is_true(started == nil or started.cat ~= low.id)
    assert.are_not.equal(low.id, w.turn.cat)
  end)

  it("🌋 ends the game at once when it drowns a team's last blob", function()
    local w = field("lava", {
      terrain = pit(),
      { team = 1, index = 1, x = 40, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 60, y = terrains.LIQUID + 1 },
    })
    local events = skip_until(w, function(e)
      return find(e, "liquid_rose") ~= nil
    end)
    local ended = find(events, "game_ended")
    assert.are.same({ "ended", 1 }, { w.turn.state, ended and ended.winner })
  end)

  local function trio(kind)
    return world.from_terrain({
      terrain = pit(),
      liquid = terrains.LIQUID,
      liquid_kind = kind,
      settings = { teams = 3, cats_per_team = 1, wind_max = 0 },
      spawns = {
        { team = 1, index = 1, x = 30, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 60, y = terrains.LIQUID + 1 },
        { team = 3, index = 1, x = 150, y = terrains.GROUND - 1 },
      },
    })
  end

  local function turn_over(w)
    local rose = 0
    skip_until(w, function(e)
      rose = rose + (find(e, "liquid_rose") and 1 or 0)
      return find(e, "turn_ended") ~= nil
    end)
    return rose
  end

  it("🌋 a round ends when every living team has played once more, not before", function()
    local w = trio("water")
    local seen = {}
    for _ = 1, 3 * 3 do
      turn_over(w)
      seen[#seen + 1] = w.rounds
    end
    assert.are.same({ 0, 0, 1, 1, 1, 2, 2, 2, 3 }, seen)
    w = trio("lava")
    local rose = 0
    for _ = 1, 3 do
      rose = rose + turn_over(w)
    end
    assert.are.same({ 1, 1, false }, { w.rounds, rose, w.cats[2].alive })
    for _ = 1, 2 do
      rose = rose + turn_over(w)
    end
    assert.are.same({ 2, 2 }, { w.rounds, rose })
  end)
end)

describe("🎒 ammunition counted per game (§8.2)", function()
  local function field()
    return world.from_terrain({
      terrain = terrains.cliff(60),
      liquid = terrains.LIQUID,
      liquid_kind = "lava",
      settings = { teams = 2, cats_per_team = 1, wind_max = 0 },
      spawns = {
        { team = 1, index = 1, x = 90, y = terrains.GROUND - 61 },
        { team = 2, index = 1, x = 10, y = terrains.GROUND - 61 },
      },
    })
  end

  local function my_turn(w, team)
    for _ = 1, 3000 do
      if w.turn.state == "aiming" and w.turn.team == team then
        return true
      end
      local inputs = nil
      if w.turn.state == "aiming" then
        inputs = { { team = w.turn.team, kind = "skip" } }
      end
      world.step(w, inputs)
    end
    return false
  end

  local function fire(w, weapon, angle)
    local fired = false
    local events = world.step(w, {
      { team = 1, kind = "fire", weapon = weapon, angle = angle or 64, power = 100, fuse = 1 },
    })
    for _, e in ipairs(events) do
      fired = fired
        or e.type == "fired"
        or e.type == "tentacle_missed"
        or e.type == "tentacle_hooked"
    end
    return fired
  end

  it(
    "🎒 a team that fired its 10 bazookas cannot fire an 11th, and still throws grenades",
    function()
      local w = field()
      local slot = weapons.index_of("bazooka")
      for shot = 1, 10 do
        assert.is_true(my_turn(w, 1), "turn " .. shot)
        assert.is_true(fire(w, "bazooka"), "shot " .. shot)
        assert.are.equal(10 - shot, w.teams[1].ammo[slot])
      end
      assert.is_true(my_turn(w, 1))
      assert.is_false(fire(w, "bazooka"))
      assert.are.same({ "aiming", 0, 0 }, { w.turn.state, #w.projectiles, w.teams[1].ammo[slot] })
      assert.is_true(fire(w, "grenade"))
      assert.are.equal(9, w.teams[1].ammo[weapons.index_of("grenade")])
    end
  )

  it("🎒 the tentacle and the uppercut never run out", function()
    local w = field()
    for round = 1, 12 do
      assert.is_true(my_turn(w, 1), "turn " .. round)
      assert.is_true(fire(w, "tentacle", 256), "tentacle " .. round)
      assert.is_true(fire(w, "uppercut"), "uppercut " .. round)
    end
    for _, id in ipairs({ "tentacle", "uppercut" }) do
      assert.are.equal(-1, w.teams[1].ammo[weapons.index_of(id)], id)
    end
  end)

  it("🎒 a team eats three times with the Chomp, never a fourth", function()
    local w = world.from_terrain({
      terrain = terrains.flat(),
      liquid = terrains.LIQUID,
      settings = { teams = 2, cats_per_team = 1, wind_max = 0 },
      spawns = {
        { team = 1, index = 1, x = 170, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 20, y = terrains.GROUND - 1 },
      },
    })
    local slot = weapons.index_of("chomp")
    for meal = 1, 3 do
      assert.is_true(my_turn(w, 1), "turn " .. meal)
      assert.is_true(fire(w, "chomp", 512), "meal " .. meal)
      assert.are.equal(3 - meal, w.teams[1].ammo[slot])
    end
    assert.is_true(my_turn(w, 1))
    assert.is_false(fire(w, "chomp", 512))
    assert.are.same({ "aiming", 0 }, { w.turn.state, w.teams[1].ammo[slot] })
  end)
end)

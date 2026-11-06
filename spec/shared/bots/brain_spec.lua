local brain = require("shared.bots.brain")
local cat = require("shared.sim.cat")
local driver = require("shared.bots.driver")
local explosion = require("shared.sim.explosion")
local rules = require("shared.sim.rules")
local terrain = require("shared.sim.terrain")
local terrains = require("spec.support.terrains")
local weapons = require("shared.sim.weapons.registry")
local world = require("shared.sim.world")

local function open_field(level)
  local w = world.from_terrain({
    terrain = terrains.flat(400),
    liquid = terrains.LIQUID,
    settings = { teams = 2, cats_per_team = 1, bot_level = level },
    spawns = {
      { team = 1, index = 1, x = 100, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 260, y = terrains.GROUND - 1 },
    },
  })
  return w, driver.new({ seed = 99, teams = { 1 }, level = level })
end

local function play(w, d, until_fires)
  local fires, enemy_hurt_at = 0, nil
  for _ = 1, 20000 do
    local inputs = driver.inputs(d, w)
    if inputs == nil and w.turn.state == "aiming" and w.turn.team == 2 then
      inputs = { { team = 2, kind = "skip" } }
    end
    if inputs and inputs[1].kind == "fire" then
      fires = fires + 1
    end
    for _, e in ipairs(world.step(w, inputs)) do
      if e.type == "damaged" and e.cat == 2 and enemy_hurt_at == nil then
        enemy_hurt_at = fires
      end
    end
    if w.turn.state == "ended" or (fires >= until_fires and w.turn.team == 2) then
      break
    end
  end
  return fires, enemy_hurt_at
end

describe("🤖 bots (D-06)", function()
  it("🤖 a hard bot hurts an enemy in the open within 3 turns", function()
    local w, d = open_field("hard")
    local fires, hurt_at = play(w, d, 3)
    assert.is_true(fires >= 1)
    assert.is_not_nil(hurt_at, "the enemy was never hurt")
    assert.is_true(hurt_at <= 3)
  end)

  it("🤖 never changes the world while it thinks", function()
    local w = open_field("hard")
    for _ = 1, rules.TURN_START_TICKS + 10 do
      world.step(w)
    end
    assert.are.equal("aiming", w.turn.state)
    local before = { world.checksum(w) }
    local cells = { terrain.cells_hash(w.terrain) }
    local bot = brain.new({ team = 1, level = "hard", seed = 5 })
    for _ = 1, 60 do
      brain.think(bot, w, 16)
    end
    assert.are.same(before, { world.checksum(w) })
    assert.are.same(cells, { terrain.cells_hash(w.terrain) })
  end)

  it("🤖 stops a call once it has spent its budget of work, then refines once", function()
    local w = open_field("hard")
    for _ = 1, rules.TURN_START_TICKS + 10 do
      world.step(w)
    end
    local bot = brain.new({ team = 1, level = "hard", seed = 5 })
    brain.think(bot, w, 7)
    assert.are.equal(2 * rules.BOT_WORK.flight, bot.work)
    assert.are.equal(1, bot.cursor)
    for _ = 1, 20000 do
      brain.think(bot, w, 7)
      assert.is_true(bot.work >= 7 or bot.job == nil)
      assert.is_true(bot.work < 7 + rules.BOT_WORK.knockback)
    end
    local level = rules.BOT_LEVELS.hard
    assert.are.equal(level.candidates + level.refine, #bot.candidates)
    assert.are.equal(#bot.candidates + 1, bot.cursor)
  end)

  it("🤖 weighs a projectile tick, a knockback tick and each cat it examines", function()
    local w = open_field("hard")
    for _ = 1, rules.TURN_START_TICKS + 10 do
      world.step(w)
    end
    local bot = brain.new({ team = 1, level = "hard", seed = 5 })
    local seen = { flight = false, cat = false, knockback = false }
    for _ = 1, 50000 do
      local job = bot.job
      local stage = job and job.stage
      local index = job and job.index
      local ghost = job and job.ghost
      local ticks = job and (ghost and job.ghost_ticks or job.ticks)
      brain.think(bot, w, 1)
      if job and bot.job == job then
        if stage == "flight" and job.stage == "flight" then
          assert.are.equal(rules.BOT_WORK.flight, bot.work)
          assert.are.equal(ticks + 1, job.ticks)
          seen.flight = true
        elseif stage == "cats" and ghost == nil then
          assert.are.equal(rules.BOT_WORK.cat, bot.work)
          assert.are.equal(index + 1, job.index)
          seen.cat = true
        elseif stage == "cats" and ghost == job.ghost then
          assert.are.equal(rules.BOT_WORK.knockback, bot.work)
          assert.are.equal(ticks + 1, job.ghost_ticks)
          seen.knockback = true
        end
      end
      if bot.cursor > #bot.candidates and bot.refined then
        break
      end
    end
    assert.are.same({ flight = true, cat = true, knockback = true }, seen)
  end)

  it("🤖 starts searching during the turn start, but only fires while aiming", function()
    local w = open_field("hard")
    assert.are.equal("turn_start", w.turn.state)
    local bot = brain.new({ team = 1, level = "easy", seed = 5 })
    assert.is_nil(brain.think(bot, w, 50))
    assert.are.equal(50, bot.work)
  end)

  it("🤖 decides after 3 s of aiming even on a starved budget", function()
    local w = open_field("hard")
    local d = driver.new({ seed = 99, teams = { 1 }, level = "hard", budget = 1 })
    local fired_at
    for _ = 1, 400 do
      local inputs = driver.inputs(d, w)
      if inputs and inputs[1].kind == "fire" then
        fired_at = w.turn.ticks
        break
      end
      world.step(w)
    end
    assert.are.equal(rules.BOT_DECIDE_TICKS, fired_at)
  end)

  it("🤖 never fires a candidate it already knows to be a dud", function()
    local w = open_field("hard")
    local d = driver.new({ seed = 99, teams = { 1 }, level = "hard", budget = 1 })
    local bot = d.bots[1]
    while w.turn.state ~= "aiming" do
      world.step(w)
    end
    local input, cursor
    for _ = 1, 400 do
      local inputs = driver.inputs(d, w)
      if inputs then
        input, cursor = inputs[1], bot.cursor
        break
      end
      world.step(w)
    end
    assert.is_true(cursor > 1, "the first candidate was not evaluated yet")
    local current = bot.candidates[cursor]
    assert.are.equal(current.weapon, input.weapon)
    assert.is_true(math.abs(input.power - current.power) <= rules.BOT_LEVELS.hard.power_noise)
  end)

  it("🤖 stops searching once it has decided", function()
    local w = open_field("hard")
    local d = driver.new({ seed = 99, teams = { 1 }, level = "hard", budget = 1 })
    local bot = d.bots[1]
    for _ = 1, 400 do
      if driver.inputs(d, w) then
        break
      end
      world.step(w)
    end
    local state, cursor = bot.stream.state, bot.cursor
    for _ = 1, 500 do
      brain.think(bot, w, 150)
    end
    assert.are.equal(state, bot.stream.state)
    assert.are.equal(cursor, bot.cursor)
  end)

  it("🤖 keeps its decision for the whole turn without drawing again", function()
    local w, d = open_field("medium")
    local first
    for _ = 1, 2000 do
      local inputs = driver.inputs(d, w)
      if inputs then
        first = inputs[1]
        break
      end
      world.step(w)
    end
    local bot = d.bots[1]
    local state = bot.stream.state
    for _ = 1, 5 do
      assert.are.same(first, driver.inputs(d, w)[1])
    end
    assert.are.equal(state, bot.stream.state)
  end)

  it("🤖 searches anew when it takes a team over in the middle of a later turn", function()
    local w = open_field("easy")
    local bot = brain.new({ team = 1, level = "easy", seed = 5 })
    local first
    for _ = 1, 2000 do
      first = brain.think(bot, w, 1500)
      if first then
        break
      end
      world.step(w)
    end
    world.step(w, { first })
    for _ = 1, 3000 do
      if w.turn.state == "aiming" and w.turn.team == 2 then
        world.step(w, { { team = 2, kind = "skip" } })
      elseif w.turn.state == "aiming" and w.turn.team == 1 and w.turn.ticks >= 10 then
        break
      else
        world.step(w)
      end
    end
    assert.are.equal(1, w.turn.team)
    brain.think(bot, w, 1500)
    assert.are.equal(2, bot.searches)
  end)

  it("🤖 searches anew on each of its turns", function()
    local w = world.from_terrain({
      terrain = terrains.flat(400),
      liquid = terrains.LIQUID,
      settings = { teams = 2, cats_per_team = 2, bot_level = "easy" },
      spawns = {
        { team = 1, index = 1, x = 60, y = terrains.GROUND - 1 },
        { team = 1, index = 2, x = 140, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 260, y = terrains.GROUND - 1 },
        { team = 2, index = 2, x = 340, y = terrains.GROUND - 1 },
      },
    })
    local d = driver.new({ seed = 3, teams = { 1 }, level = "easy" })
    local shooters = {}
    for _ = 1, 20000 do
      local inputs = driver.inputs(d, w)
      if inputs == nil and w.turn.state == "aiming" and w.turn.team == 2 then
        inputs = { { team = 2, kind = "skip" } }
      end
      if inputs and inputs[1].kind == "fire" then
        shooters[#shooters + 1] = w.turn.cat
      end
      world.step(w, inputs)
      if #shooters == 2 then
        break
      end
    end
    assert.are.same({ 1, 2 }, shooters)
    assert.are.equal(2, d.bots[1].searches)
  end)

  it("🤖 counts a push into the liquid as a kill", function()
    local w = world.from_terrain({
      terrain = terrains.shore(),
      liquid = terrains.LIQUID,
      settings = { teams = 2, cats_per_team = 1 },
      spawns = {
        { team = 1, index = 1, x = 20, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 96, y = terrains.GROUND - 1 },
      },
    })
    local spec = weapons.get("bazooka").explosion
    local result = brain.score(w, w.cats[1], { x = 90, y = terrains.GROUND - 4, spec = spec })
    assert.is_true(result.value >= rules.BOT_KILL_BONUS, "score " .. result.value)
  end)

  it(
    "🤖 follows a pushed blob until it rests, so a skid into the liquid counts as a kill",
    function()
      local skids, spec = 0, weapons.get("bazooka").explosion
      for x = 60, 98 do
        local w = world.from_terrain({
          terrain = terrains.shore(),
          liquid = terrains.LIQUID,
          settings = { teams = 2, cats_per_team = 1 },
          spawns = {
            { team = 1, index = 1, x = 20, y = terrains.GROUND - 1 },
            { team = 2, index = 1, x = x, y = terrains.GROUND - 1 },
          },
        })
        local target = w.cats[2]
        local blast = { x = x - 6, y = terrains.GROUND - 4, spec = spec }
        local predicted = brain.score(w, w.cats[1], blast).enemy == target.hp
        local hit = explosion.effect(target, blast)
        cat.push(target, hit.vx, hit.vy)
        local touched = false
        for _ = 1, 400 do
          cat.step(target, w.terrain, w.liquid.level, {})
          touched = touched or target.grounded
          if not target.alive or cat.at_rest(target) then
            break
          end
        end
        assert.are.equal(not target.alive, predicted, "blast at " .. blast.x)
        if touched and not target.alive then
          skids = skids + 1
        end
      end
      assert.is_true(skids >= 1, "no skid into the liquid was tried")
    end
  )

  it("🤖 prefers a harmless shot to one whose score is not positive", function()
    local hurtful, harmless, digging = { angle = 1 }, { angle = 2 }, { angle = 3 }
    local bot = {
      best = { value = -10, candidate = hurtful },
      fallback = { nearest = 5, candidate = harmless },
      least_bad = { value = 0, candidate = digging },
    }
    assert.are.equal(harmless, brain.choose(bot))
    bot.best.value = 10
    assert.are.equal(hurtful, brain.choose(bot))
    bot.best, bot.fallback = nil, nil
    assert.are.equal(digging, brain.choose(bot))
    bot.least_bad = nil
    assert.is_nil(brain.choose(bot))
  end)

  it("🤖 emits a regular, valid fire input", function()
    for _, level in ipairs({ "easy", "medium", "hard" }) do
      local w, d = open_field(level)
      local input
      for _ = 1, 2000 do
        local inputs = driver.inputs(d, w)
        if inputs then
          input = inputs[1]
          break
        end
        world.step(w)
      end
      assert.are.equal("fire", input.kind)
      assert.are.equal(1, input.team)
      assert.is_not_nil(weapons.get(input.weapon))
      assert.is_true(input.angle >= 0 and input.angle <= 1023 and input.angle % 1 == 0)
      assert.is_true(input.power >= 1 and input.power <= 100 and input.power % 1 == 0)
      assert.is_true(w.turn.ticks >= rules.BOT_WAIT_MIN)
    end
  end)

  it("🤖 only considers weapons its team still has ammunition for", function()
    local w = open_field("hard")
    w.teams[1].ammo[weapons.index_of("grenade")] = 0
    for _ = 1, rules.TURN_START_TICKS + 10 do
      world.step(w)
    end
    local bot = brain.new({ team = 1, level = "hard", seed = 5 })
    for _ = 1, 100 do
      brain.think(bot, w, 16)
    end
    for _, candidate in ipairs(bot.candidates) do
      assert.are_not.equal("grenade", candidate.weapon)
    end
  end)

  it("🤖 passes its turn once it has neither bazooka nor grenade left (§9)", function()
    local w = open_field("hard")
    w.teams[1].ammo[weapons.index_of("bazooka")] = 0
    w.teams[1].ammo[weapons.index_of("grenade")] = 0
    local bot = brain.new({ team = 1, level = "hard", seed = 5 })
    local input = nil
    for _ = 1, rules.TURN_START_TICKS + rules.BOT_DECIDE_TICKS + 10 do
      input = brain.think(bot, w, rules.BOT_WORK_PER_TICK)
      if input then
        break
      end
      world.step(w)
    end
    assert.are.same({ team = 1, kind = "skip" }, input)
  end)

  it("🤖 never throws the tentacle (§9)", function()
    local w = open_field("hard")
    for _ = 1, rules.TURN_START_TICKS + 10 do
      world.step(w)
    end
    local bot = brain.new({ team = 1, level = "hard", seed = 5 })
    for _ = 1, 100 do
      brain.think(bot, w, 16)
    end
    assert.is_true(#bot.candidates > 0)
    for _, candidate in ipairs(bot.candidates) do
      assert.are.equal("projectile", weapons.get(candidate.weapon).kind)
    end
  end)

  it("🤖 accepts the largest seed for every team", function()
    for team = 1, 8 do
      assert.has_no.errors(function()
        brain.new({ team = team, level = "easy", seed = 2147483646 })
      end)
    end
  end)

  it("🤖 prefers hurting enemies over its own team", function()
    local w = world.from_terrain({
      terrain = terrains.flat(400),
      liquid = terrains.LIQUID,
      settings = { teams = 2, cats_per_team = 2 },
      spawns = {
        { team = 1, index = 1, x = 60, y = terrains.GROUND - 1 },
        { team = 1, index = 2, x = 200, y = terrains.GROUND - 1 },
        { team = 2, index = 1, x = 320, y = terrains.GROUND - 1 },
        { team = 2, index = 2, x = 380, y = terrains.GROUND - 1 },
      },
    })
    local shooter = w.cats[1]
    local spec = weapons.get("bazooka").explosion
    local on_friend = brain.score(w, shooter, { x = 200, y = terrains.GROUND - 4, spec = spec })
    local on_enemy = brain.score(w, shooter, { x = 320, y = terrains.GROUND - 4, spec = spec })
    assert.is_true(on_enemy.value > 0)
    assert.is_true(on_friend.value < 0)
  end)

  it("🤖 plays the same shots again from the same seed", function()
    local a_w, a_d = open_field("medium")
    local b_w, b_d = open_field("medium")
    play(a_w, a_d, 2)
    play(b_w, b_d, 2)
    assert.are.same({ world.checksum(a_w) }, { world.checksum(b_w) })
  end)
end)

describe("🤖 bot cost", function()
  it("🤖 measures the cost of one candidate #perf", function()
    local w = assert(world.new(31337, { teams = 8, cats_per_team = 4 }))
    for _ = 1, rules.TURN_START_TICKS + 10 do
      world.step(w)
    end
    local bot = brain.new({ team = w.turn.team, level = "easy", seed = 1 })
    local start = os.clock()
    brain.think(bot, w, 1000000000)
    local per = (os.clock() - start) * 1000 / #bot.candidates
    print(
      string.format("\n🤖 one candidate: %.3f ms under %s", per, jit and "LuaJIT" or "Lua 5.1")
    )
    assert.are.equal(#bot.candidates + 1, bot.cursor)
  end)

  local function take_over_after(aimed)
    local w = open_field("hard")
    while w.turn.state ~= "aiming" or w.turn.ticks < aimed do
      world.step(w)
    end
    local d = driver.new({ seed = 99, teams = {}, level = "hard" })
    driver.take(d, 1)
    local took_at = w.turn.ticks
    for _ = 1, 3000 do
      local inputs = driver.inputs(d, w)
      if inputs and inputs[1].kind == "fire" then
        return w, d.bots[1], w.turn.ticks - took_at, inputs[1]
      end
      world.step(w, inputs)
    end
    error("the bot never fired")
  end

  it("🤖 a bot taking over after the human aimed 100 ticks still waits and searches", function()
    local _, bot, after = take_over_after(100)
    assert.is_true(after >= bot.wait, "fired " .. after .. " ticks after taking over")
    assert.are.equal(#bot.candidates + 1, bot.cursor)
    assert.is_true(bot.refined)
  end)

  it("🤖 a bot taking over with 10 ticks left on the timer fires before the turn ends", function()
    local w = open_field("hard")
    while w.turn.state ~= "aiming" or w.turn.timer > 10 do
      world.step(w)
    end
    local d = driver.new({ seed = 99, teams = {}, level = "hard", budget = 1 })
    driver.take(d, 1)
    local fired = false
    while w.turn.state == "aiming" do
      local inputs = driver.inputs(d, w)
      if inputs and inputs[1].kind == "fire" then
        fired = true
      end
      world.step(w, inputs)
    end
    assert.is_true(fired)
    assert.are.equal("flight", w.turn.state)
  end)
end)

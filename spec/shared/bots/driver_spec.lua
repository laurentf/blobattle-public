local driver = require("shared.bots.driver")
local rules = require("shared.sim.rules")
local terrains = require("spec.support.terrains")
local world = require("shared.sim.world")

local function duel()
  return world.from_terrain({
    terrain = terrains.flat(400),
    liquid = terrains.LIQUID,
    settings = { teams = 2, cats_per_team = 1 },
    spawns = {
      { team = 1, index = 1, x = 100, y = terrains.GROUND - 1 },
      { team = 2, index = 1, x = 260, y = terrains.GROUND - 1 },
    },
  })
end

describe("🤖 the bot driver", function()
  it("🤖 plays only the teams it drives", function()
    local w = duel()
    local d = driver.new({ seed = 4, teams = { 2 }, level = "easy" })
    for _ = 1, 200 do
      assert.is_nil(driver.inputs(d, w))
      world.step(w)
    end
    assert.are.equal(1, w.turn.team)
  end)

  it("🤖 hands its bots the budget it was given, or the default", function()
    local w = duel()
    local given = driver.new({ seed = 4, teams = { 1 }, level = "easy", budget = 9 })
    driver.inputs(given, w)
    assert.are.equal(2 * rules.BOT_WORK.flight, given.bots[1].work)
    local default = driver.new({ seed = 4, teams = { 1 }, level = "easy" })
    driver.inputs(default, w)
    assert.is_true(default.bots[1].work >= rules.BOT_WORK_PER_TICK)
    assert.is_true(default.bots[1].work < rules.BOT_WORK_PER_TICK + rules.BOT_WORK.knockback)
  end)

  local function fires(budget, turns)
    local w = assert(world.new(31337, { teams = 8, cats_per_team = 4, bot_level = "hard" }))
    local all = {}
    for team = 1, 8 do
      all[team] = team
    end
    local d = driver.new({ seed = 31337, teams = all, level = "hard", budget = budget })
    local shots, decided_at = {}, {}
    while #shots < turns do
      local inputs = driver.inputs(d, w)
      local bot = d.bots[w.turn.team]
      if inputs and inputs[1].kind == "fire" then
        local i = inputs[1]
        shots[#shots + 1] = { i.team, i.weapon, i.angle, i.power, i.fuse or 0 }
        decided_at[#decided_at + 1] = {
          state = w.turn.state,
          ticks = w.turn.ticks,
          done = bot.refined and bot.job == nil and bot.cursor == #bot.candidates + 1,
        }
      end
      world.step(w, inputs)
    end
    return shots, decided_at
  end

  it("🤖 on the server budget, a hard bot has searched everything before the limit", function()
    local _, decided = fires(rules.BOT_SERVER_WORK_PER_TICK, 2)
    for _, at in ipairs(decided) do
      assert.are.equal("aiming", at.state)
      assert.is_true(at.ticks < rules.BOT_DECIDE_TICKS, "decided at aiming tick " .. at.ticks)
      assert.is_true(at.done)
    end
  end)

  it("🤖 works with the same budget offline as on the server, so a seed plays alike", function()
    assert.are.equal(rules.BOT_SERVER_WORK_PER_TICK, rules.BOT_WORK_PER_TICK)
  end)

  it("🤖 takes a team over, keeps its bot if asked again, and hands it back", function()
    local w = duel()
    local d = driver.new({ seed = 4, teams = {}, level = "easy" })
    assert.is_nil(driver.inputs(d, w))
    driver.take(d, 1)
    local bot = d.bots[1]
    driver.take(d, 1)
    assert.are.equal(bot, d.bots[1])
    local fired = false
    for _ = 1, 400 do
      local inputs = driver.inputs(d, w)
      if inputs and inputs[1].kind == "fire" then
        fired = true
        break
      end
      world.step(w, inputs)
    end
    assert.is_true(fired)
    driver.release(d, 1)
    assert.is_nil(d.bots[1])
    assert.is_nil(driver.inputs(d, w))
  end)
end)

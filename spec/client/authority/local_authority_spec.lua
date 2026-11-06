local LocalAuthority = require("authority.local_authority")
local names = require("shared.names")
local replay = require("harness.replay")
local rules = require("shared.sim.rules")
local world = require("shared.sim.world")

local TICK = 1 / rules.TICKS_PER_SECOND

local PLAYER = {
  nickname = "Tester",
  team_name = "Pawtesters",
  members = { "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot" },
}

local function record(a, into)
  for _, m in ipairs(a.poll()) do
    if m.name == "game_start" then
      into.game_start = m.data
    elseif m.name == "ticks" then
      into.ticks[#into.ticks + 1] = m.data
    elseif m.name == "checksum" then
      into.checksums[#into.checksums + 1] = m.data
    elseif m.name == "game_end" then
      into.game_end = m.data
    elseif m.name == "refused" then
      into.refused[#into.refused + 1] = m.data.code
    elseif m.name == "snapshot" then
      into.snapshots[#into.snapshots + 1] = m.data
    end
  end
end

local function new_recording()
  return { ticks = {}, checksums = {}, snapshots = {}, refused = {} }
end

local function open(settings, seed)
  local a = LocalAuthority.new({ seed = seed or 1234, settings = settings, player = PLAYER })
  local rec = new_recording()
  a.start()
  record(a, rec)
  return a, rec
end

local function until_turn(a, rec, state, on_bot_aiming)
  for _ = 1, 20000 do
    local t = a.world.turn
    if t.team == 1 and t.state == state then
      return
    end
    if on_bot_aiming and t.team ~= 1 and t.state == "aiming" then
      on_bot_aiming()
    end
    a.update(TICK)
    record(a, rec)
  end
  error("the player never reached " .. state)
end

describe("🔌 the local authority (§7.1)", function()
  it("🔌 announces the game with the seed, the settings and a named roster", function()
    local _, rec = open({ teams = 3, cats_per_team = 2 })
    local start = rec.game_start
    assert.are.equal(1234, start.seed)
    assert.are.same(world.resolve_settings({ teams = 3, cats_per_team = 2 }), start.settings)
    assert.are.equal(3, #start.roster)
    local generated = names.game(1234, 3)
    assert.are.same({
      team = 1,
      kind = "human",
      name = "Tester",
      team_name = "Pawtesters",
      members = PLAYER.members,
    }, start.roster[1])
    for team = 2, 3 do
      assert.are.same({
        team = team,
        kind = "bot",
        team_name = generated[team].name,
        members = generated[team].members,
      }, start.roster[team])
    end
  end)

  it("🔌 tells which team the player plays, and drives the bots at the offline budget", function()
    local a = open({ teams = 3, cats_per_team = 1 })
    assert.are.equal(1, a.team())
    assert.are.equal(rules.BOT_WORK_PER_TICK, a.budget)
  end)

  it(
    "🔌 plays a whole game whose stream replays like the server's, to an odd last tick",
    function()
      local a, rec = open({ teams = 3, cats_per_team = 1, bot_level = "hard" }, 7)
      local skips = 0
      for _ = 1, 30000 do
        a.update(TICK)
        record(a, rec)
        if rec.game_end then
          break
        end
        if a.world.turn.team == 1 and a.world.turn.state == "aiming" then
          a.send("skip", {})
          skips = skips + 1
        end
      end
      assert.is_table(rec.game_end)
      assert.are.same({}, rec.refused)
      assert.is_true(skips >= 2, skips .. " skips")
      assert.are.equal(1, a.world.tick % 2)
      assert.are.equal(a.world.tick, rec.ticks[#rec.ticks].to)
      assert.are.equal(a.world.tick, rec.checksums[#rec.checksums].tick)
      local report = replay.check(rec)
      assert.are.same({}, report.errors)
      assert.is_true(report.checksums > 10)
      for _ = 1, 10 do
        a.update(TICK)
      end
      assert.are.same({}, a.poll())
    end
  )

  it("🌍 in a forest game, what the quakes do counts for no team, like on the server", function()
    local a, rec = open({ teams = 2, cats_per_team = 2, map = "forest", bot_level = "easy" }, 11)
    local quaked = false
    for _ = 1, 30000 do
      a.update(TICK)
      record(a, rec)
      quaked = quaked or a.world.turn.state == "quake"
      if rec.game_end then
        break
      end
      if a.world.turn.team == 1 and a.world.turn.state == "aiming" then
        a.send("skip", {})
      end
    end
    assert.is_true(quaked)
    assert.is_table(rec.game_end)
    local report = replay.check(rec)
    assert.are.same({}, report.errors)
  end)

  it(
    "🎒 refuses a weapon the team has run out of, and a walk in the same tick goes through",
    function()
      local weapons = require("shared.sim.weapons.registry")
      local a, rec = open({ teams = 2, cats_per_team = 1 })
      until_turn(a, rec, "aiming")
      a.world.teams[1].ammo[weapons.index_of("bazooka")] = 0
      a.send("fire", { weapon = "bazooka", angle = 64, power = 50 })
      a.send("input", { kind = "move", direction = 1 })
      a.update(TICK)
      record(a, rec)
      a.update(TICK)
      record(a, rec)
      assert.are.same({ "no_ammo" }, rec.refused)
      local kinds = {}
      for _, message in ipairs(rec.ticks) do
        for _, entry in ipairs(message.inputs) do
          if entry.input.team == 1 then
            kinds[#kinds + 1] = entry.input.kind
          end
        end
      end
      assert.are.same({ "move" }, kinds)
    end
  )

  it("📡 carries an air strike's column into the game, and refuses one off the map", function()
    local weapons = require("shared.sim.weapons.registry")
    local a, rec = open({ teams = 2, cats_per_team = 1 })
    until_turn(a, rec, "aiming")
    a.world.teams[1].ammo[weapons.index_of("airstrike")] = 1
    local width = a.world.terrain.width
    a.send("fire", { weapon = "airstrike", angle = 0, power = 1, target = width })
    a.update(TICK)
    record(a, rec)
    assert.are.same({ "invalid_target" }, rec.refused)
    a.send("fire", { weapon = "airstrike", angle = 0, power = 1, target = width - 1 })
    a.update(TICK)
    record(a, rec)
    a.update(TICK)
    record(a, rec)
    local fired = nil
    for _, message in ipairs(rec.ticks) do
      for _, entry in ipairs(message.inputs) do
        if entry.input.kind == "fire" then
          fired = entry.input
        end
      end
    end
    assert.are.same({ "airstrike", width - 1 }, { fired.weapon, fired.target })
    assert.are.equal(5, #a.world.projectiles)
  end)

  it("🐑 sets the Waddler off in flight with none left, refusing nothing", function()
    local turn = require("shared.sim.turn")
    local weapons = require("shared.sim.weapons.registry")
    local a = LocalAuthority.new({
      seed = 1234,
      settings = { teams = 2, cats_per_team = 1 },
      player = PLAYER,
    })
    local refused = {}
    local function pump()
      a.update(TICK)
      for _, m in ipairs(a.poll()) do
        if m.name == "refused" then
          refused[#refused + 1] = m.data.code
        end
      end
    end
    a.start()
    for _ = 1, 20000 do
      if a.world.turn.team == 1 and a.world.turn.state == "aiming" then
        break
      end
      pump()
    end
    a.world.teams[1].ammo[weapons.index_of("waddler")] = 1
    a.send("fire", { weapon = "waddler", angle = 0, power = 1 })
    for _ = 1, 10 do
      pump()
    end
    assert.are.same({ "flight", true }, { a.world.turn.state, turn.accepts(a.world, "fire") })
    a.send("fire", { weapon = "waddler", angle = 0, power = 1 })
    for _ = 1, 4 do
      pump()
    end
    assert.are.same({}, refused)
    assert.are.equal(0, #a.world.projectiles)
  end)

  it("🔌 stamps the player's input with their team at the next tick, fuse included", function()
    local a, rec = open({ teams = 2, cats_per_team = 1 })
    until_turn(a, rec, "aiming", function()
      a.send("skip", {})
    end)
    local at = a.world.tick
    a.send("fire", { weapon = "grenade", angle = 300, power = 60, fuse = 2 })
    a.update(TICK)
    a.update(TICK)
    record(a, rec)
    assert.are.same({
      {
        at = at,
        input = { team = 1, kind = "fire", weapon = "grenade", angle = 300, power = 60, fuse = 2 },
      },
    }, rec.ticks[#rec.ticks].inputs)
  end)

  it(
    "🔌 refuses what the server would refuse, with the same reasons, in the same order",
    function()
      local a, rec = open({ teams = 2, cats_per_team = 1 })
      until_turn(a, rec, "turn_start", function()
        rec.refused = {}
        a.send("skip", {})
        a.update(TICK)
        record(a, rec)
        assert.are.same({ "not_your_turn" }, rec.refused)
      end)
      rec.refused = {}
      a.send("fire", { weapon = "bazooka", angle = 300, power = 60 })
      a.send("start", {})
      a.send("lobby_settings", { teams = 3 })
      a.send("rematch", {})
      a.send("dance", {})
      a.update(TICK)
      record(a, rec)
      assert.are.same(
        { "not_now", "wrong_phase", "wrong_phase", "wrong_phase", "unknown_op" },
        rec.refused
      )
      until_turn(a, rec, "aiming")
      rec.refused = {}
      a.send("fire", { weapon = "bazooka", angle = 300.5, power = 60 })
      a.send("fire", { weapon = "rake", angle = 300, power = 60 })
      a.send("input", { kind = "move", direction = 2 })
      a.send("fire", { weapon = "bazooka", angle = 300, power = 60 })
      a.send("skip", {})
      a.send("input", { kind = "move", direction = 1 })
      a.update(TICK)
      record(a, rec)
      assert.are.same(
        { "invalid_angle", "invalid_weapon", "invalid_direction", "not_now", "not_now" },
        rec.refused
      )
    end
  )

  it("🐙 a tentacle throw keeps the tick open: an input right after it goes through", function()
    local a, rec = open({ teams = 2, cats_per_team = 1 })
    until_turn(a, rec, "aiming")
    rec.refused, rec.ticks = {}, {}
    a.send("fire", { weapon = "tentacle", angle = 256, power = 1 })
    a.send("input", { kind = "climb", direction = -1 })
    a.send("input", { kind = "move", direction = 1 })
    a.update(TICK)
    a.update(TICK)
    record(a, rec)
    assert.are.same({}, rec.refused)
    local kinds = {}
    for _, m in ipairs(rec.ticks) do
      for _, entry in ipairs(m.inputs) do
        kinds[#kinds + 1] = entry.input.kind
      end
    end
    assert.are.same({ "fire", "climb", "move" }, kinds)
    assert.are.equal("aiming", a.world.turn.state)
  end)

  it("🔌 answers a snapshot request with the world, at most once every 5 s", function()
    local a, rec = open({ teams = 2, cats_per_team = 1 })
    for _ = 1, 40 do
      a.update(TICK)
    end
    a.send("snapshot_request", {})
    a.send("snapshot_request", {})
    record(a, rec)
    assert.are.equal(1, #rec.snapshots)
    assert.are.equal(40, rec.snapshots[1].tick)
    assert.are.same({ world.checksum(a.world) }, {
      world.checksum(assert(world.restore(rec.snapshots[1].state))),
    })
    assert.are.same({ "too_soon" }, rec.refused)
  end)

  it("🔌 refuses game inputs once the game is over", function()
    local a, rec = open({ teams = 2, cats_per_team = 1, bot_level = "hard" })
    for _ = 1, 30000 do
      a.update(TICK)
      record(a, rec)
      if rec.game_end then
        break
      end
      if a.world.turn.team == 1 and a.world.turn.state == "aiming" then
        a.send("skip", {})
      end
    end
    rec.refused = {}
    a.send("skip", {})
    record(a, rec)
    assert.are.same({ "wrong_phase" }, rec.refused)
  end)

  it("🔌 sends ticks every two ticks, a checksum every second, nothing beyond", function()
    local a, rec = open({ teams = 2, cats_per_team = 1 })
    for _ = 1, 90 do
      a.update(TICK)
    end
    record(a, rec)
    assert.are.equal(45, #rec.ticks)
    for i, m in ipairs(rec.ticks) do
      assert.are.equal(2 * i, m.to)
    end
    assert.are.same({ 30, 60, 90 }, {
      rec.checksums[1].tick,
      rec.checksums[2].tick,
      rec.checksums[3].tick,
    })
    assert.are.equal(90, a.world.tick)
  end)

  it("🔌 catches up at most a few ticks after a long pause, then goes on at 30 Hz", function()
    local a = open({ teams = 2, cats_per_team = 1 })
    a.update(10)
    assert.are.equal(LocalAuthority.MAX_CATCH_UP, a.world.tick)
    a.update(TICK)
    assert.is_true(a.world.tick <= LocalAuthority.MAX_CATCH_UP + 2, a.world.tick .. " ticks")
  end)
end)

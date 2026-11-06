local fake = require("spec.support.nakama")
local names = require("shared.names")
local protocol = require("shared.protocol")
local room_support = require("spec.support.room")
local rules = require("shared.sim.rules")
local runner = require("conformance.runner")
local stats = require("shared.sim.stats")
local turn = require("shared.sim.turn")
local weapons = require("shared.sim.weapons.registry")
local world = require("shared.sim.world")

local OPS = protocol.OPS
local last = room_support.last

local GRENADE_AT_FEET = { weapon = "grenade", angle = 256, power = 1, fuse = 1 }

describe("🎮 the game (§6.5, §6.8, D-03, D-08)", function()
  local nk, room, host, guest

  local function open(settings, seats)
    nk = fake.install()
    room = room_support.open(nk, settings)
    host = room_support.arrive(nk, room, "host", "Host")
    if seats ~= "alone" then
      guest = room_support.arrive(nk, room, "g1", "Guest")
    end
    room.loop({ fake.message(host, OPS.lobby_settings, { seed = 4 }) })
  end

  local function start()
    room.loop({ fake.message(host, OPS.start, {}) })
    return room.state().world
  end

  local function presence_of(team)
    for _, p in ipairs({ host, guest }) do
      if p and room.state().players[p.user_id].seat == team then
        return p
      end
    end
    return nil
  end

  local function until_state(name, limit)
    for _ = 1, limit or 2000 do
      if room.state().world.turn.state == name then
        return
      end
      room.loop()
    end
    error("never reached " .. name)
  end

  local function replay_stream()
    local announced = last(room, OPS.game_start)
    local w = assert(world.new(announced.seed, announced.settings))
    local s = stats.new(w)
    local by_tick, previous = {}, 0
    for _, message in ipairs(room.received(OPS.ticks)) do
      for _, entry in ipairs(message.inputs) do
        assert.is_true(entry.at >= previous and entry.at < message.to)
        by_tick[entry.at] = by_tick[entry.at] or {}
        table.insert(by_tick[entry.at], entry.input)
      end
      previous = message.to
    end
    local sums = {}
    for _, sum in ipairs(room.received(OPS.checksum)) do
      sums[sum.tick] = sum.sum
    end
    local checked = 0
    while w.tick < previous do
      local acting = turn.acting_team(w)
      stats.record(s, w, acting, world.step(w, by_tick[w.tick]))
      if sums[w.tick] then
        assert.are.same(sums[w.tick], { world.checksum(w) })
        checked = checked + 1
      end
    end
    return w, s, checked
  end

  local function ticks_inputs()
    local out = {}
    for _, t in ipairs(room.received(OPS.ticks)) do
      for _, entry in ipairs(t.inputs) do
        out[#out + 1] = entry
      end
    end
    return out
  end

  it("🚫 a fire from the inactive player is dropped and counted", function()
    open({ teams = 2, cats_per_team = 1 })
    start()
    until_state("aiming")
    local w = room.state().world
    local idle = presence_of(3 - w.turn.team)
    room.loop({ fake.message(idle, OPS.fire, { weapon = "bazooka", angle = 256, power = 40 }) })
    room.loop()
    assert.are.same({ code = "not_your_turn" }, last(room, OPS.refused, idle))
    assert.are.equal("aiming", w.turn.state)
    assert.are.same({}, ticks_inputs())
    room.leave(idle)
    local totals = nk.logged("🚫 refusals")
    assert.are.equal(1, #totals)
    assert.truthy(totals[1].message:find("not_your_turn=1", 1, true))
  end)

  it(
    "🎮 start turns every open seat without a human into a bot and announces the game",
    function()
      open({ teams = 4, cats_per_team = 1 })
      room.loop({ fake.message(host, OPS.lobby_slot, { seat = 3, kind = "bot" }) })
      room.loop({ fake.message(guest, OPS.start, {}) })
      assert.are.same({ code = "not_host" }, last(room, OPS.refused, guest))
      assert.are.equal("lobby", room.state().phase)
      local w = start()
      local announced = last(room, OPS.game_start)
      assert.are.equal(4, announced.seed)
      assert.are.equal(4, announced.settings.teams)
      local generated = names.game(4, 4)
      local function entry(fields, i)
        fields.team_name, fields.members = generated[i].name, generated[i].members
        return fields
      end
      assert.are.same({
        entry({ team = 1, kind = "human", user = "host", name = "Host" }, 1),
        entry({ team = 2, kind = "human", user = "g1", name = "Guest" }, 2),
        entry({ team = 3, kind = "bot" }, 3),
        entry({ team = 4, kind = "bot" }, 4),
      }, announced.roster)
      assert.are.same({ code = room.state().code, phase = "playing" }, nk.json_decode(room.label()))
      assert.are.equal(4, #w.teams)
      assert.are.equal(1, #nk.logged("🎮 game started"))
    end
  )

  it(
    "🎮 the roster carries each human's deposited team, generated names for the others (§6.1)",
    function()
      nk = fake.install()
      local identity = require("server.identity")
      local members = { "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot" }
      identity.team_set(
        { user_id = "g1" },
        nk.json_encode({ name = "Gel Gang", members = members })
      )
      room = room_support.open(nk, { teams = 3, cats_per_team = 2 })
      host = room_support.arrive(nk, room, "host", "Host")
      guest = room_support.arrive(nk, room, "g1", "Guest")
      room.loop({ fake.message(host, OPS.lobby_settings, { seed = 9 }) })
      start()
      local roster = last(room, OPS.game_start).roster
      local generated = names.game(9, 3)
      assert.are.equal("Gel Gang", roster[2].team_name)
      assert.are.same(members, roster[2].members)
      assert.are.equal(generated[1].name, roster[1].team_name)
      assert.are.same(generated[1].members, roster[1].members)
      assert.are.equal(generated[3].name, roster[3].team_name)
      assert.are.same(generated[3].members, roster[3].members)
    end
  )

  it("🎮 start draws the seed when the lobby left it at 0", function()
    open({ teams = 2, cats_per_team = 1 })
    room.loop({ fake.message(host, OPS.lobby_settings, { seed = 0 }) })
    nk.uuids = { "00001234-0000-4000-8000-000000000000" }
    start()
    assert.are.equal(4661, last(room, OPS.game_start).seed)
  end)

  it(
    "🧮 ticks every 2 ticks, checksums every 30, all found again by replaying the inputs",
    function()
      open({ teams = 2, cats_per_team = 2 })
      start()
      for _ = 1, 3 do
        until_state("aiming")
        local p = presence_of(room.state().world.turn.team)
        room.loop({ fake.message(p, OPS.input, { kind = "move", direction = 1 }) })
        room.loop({ fake.message(p, OPS.input, { kind = "jump", direction = 1 }) })
        for _ = 1, 20 do
          room.loop()
        end
        room.loop({ fake.message(p, OPS.fire, { weapon = "bazooka", angle = 200, power = 60 }) })
        until_state("turn_start")
      end
      local ticks = room.received(OPS.ticks)
      for i, t in ipairs(ticks) do
        assert.are.equal(2 * i, t.to)
      end
      local _, _, checked = replay_stream()
      assert.are.equal(#room.received(OPS.checksum), checked)
      local script = {}
      for _, entry in ipairs(ticks_inputs()) do
        assert.is_true(entry.at < room.state().world.tick)
        script[#script + 1] = entry
      end
      assert.is_true(#script >= 9)
      local sums = room.received(OPS.checksum)
      assert.is_true(#sums >= 10)
      local checks, expected = {}, {}
      for i, sum in ipairs(sums) do
        assert.are.equal(30 * i, sum.tick)
        checks[i] = sum.tick
        expected[i] = { tick = sum.tick, a = sum.sum[1], b = sum.sum[2] }
      end
      local announced = last(room, OPS.game_start)
      local replayed = runner.run({
        seed = announced.seed,
        settings = announced.settings,
        script = script,
        checks = checks,
      })
      assert.are.same(expected, replayed)
    end
  )

  it(
    "🚫 an input the turn does not accept is refused, and so is a weapon without ammo",
    function()
      open({ teams = 2, cats_per_team = 1 })
      start()
      local w = room.state().world
      local p = presence_of(w.turn.team)
      room.loop({ fake.message(p, OPS.fire, { weapon = "bazooka", angle = 256, power = 40 }) })
      assert.are.same({ code = "not_now" }, last(room, OPS.refused, p))
      room.loop({ fake.message(p, OPS.input, { kind = "move", direction = 1 }) })
      assert.are.same({ code = "not_now" }, last(room, OPS.refused, p))
      until_state("aiming")
      w.teams[w.turn.team].ammo[1] = 0
      room.loop({ fake.message(p, OPS.fire, { weapon = "bazooka", angle = 256, power = 40 }) })
      assert.are.same({ code = "no_ammo" }, last(room, OPS.refused, p))
      room.loop({ fake.message(p, OPS.fire, { weapon = "grenade", angle = 256, power = 400 }) })
      assert.are.same({ code = "invalid_power" }, last(room, OPS.refused, p))
      assert.are.equal("aiming", w.turn.state)
      assert.are.same({}, ticks_inputs())
    end
  )

  it("🤖 a bot plays its team through the broadcast inputs, within the server budget", function()
    open({ teams = 2, cats_per_team = 1 }, "alone")
    local w = start()
    local bot_team = 3 - room.state().players.host.seat
    for _ = 1, 3000 do
      if w.turn.team == bot_team and w.turn.state == "flight" then
        break
      end
      if w.turn.team ~= bot_team and w.turn.state == "aiming" then
        room.loop({ fake.message(host, OPS.skip, {}) })
      else
        room.loop()
      end
      local work = room.state().driver.bots[bot_team].work
      assert.is_true(work < rules.BOT_SERVER_WORK_PER_TICK + rules.BOT_WORK.knockback)
    end
    room.loop()
    room.loop()
    local fired = nil
    for _, entry in ipairs(ticks_inputs()) do
      if entry.input.team == bot_team and entry.input.kind == "fire" then
        fired = entry
      end
    end
    assert.is_not_nil(fired)
    assert.is_nil(room.state().driver.bots[room.state().players.host.seat])
  end)

  it("🎮 the game ends with its last ticks, a final checksum and game_end, then stops", function()
    open({ teams = 2, cats_per_team = 1 }, "alone")
    local w = start()
    local mine = room.state().players.host.seat
    for _ = 1, 20000 do
      if room.state().phase ~= "playing" then
        break
      end
      if w.turn.team == mine and w.turn.state == "aiming" then
        room.loop({ fake.message(host, OPS.fire, GRENADE_AT_FEET) })
      else
        room.loop()
      end
    end
    assert.are.equal("ended", room.state().phase)
    local final = w.tick
    local ticks, sums = room.received(OPS.ticks), room.received(OPS.checksum)
    assert.are.equal(final, ticks[#ticks].to)
    assert.are.equal(final, sums[#sums].tick)
    local ended = last(room, OPS.game_end)
    assert.are.equal(3 - mine, ended.winner)
    assert.are.equal(2, #ended.stats)
    local replayed, replayed_stats, checked = replay_stream()
    assert.are.equal(#sums, checked)
    assert.are.equal("ended", replayed.turn.state)
    assert.are.equal(ended.winner, replayed.result.winner)
    assert.are.same(replayed_stats, ended.stats)
    assert.are.same({ team = mine, damage = 0, kills = 0 }, ended.stats[mine])
    assert.are.equal(room.sent[#room.sent].op_code, OPS.game_end)
    assert.are.same({ code = room.state().code, phase = "ended" }, nk.json_decode(room.label()))
    local sent = #room.sent
    for _ = 1, 60 do
      room.loop()
    end
    assert.are.equal(final, w.tick)
    assert.are.equal(sent, #room.sent)
    assert.are.equal(1, #nk.logged("🎮 game ended"))
  end)

  it("🎮 a death at the end of a turn is credited to the team whose turn it was", function()
    open({ teams = 3, cats_per_team = 1 }, "alone")
    room.loop({ fake.message(host, OPS.lobby_settings, { seed = 2 }) })
    local w = start()
    local mine = room.state().players.host.seat
    local cat = w.cats[w.teams[mine].cats[1]]
    local cause = nil
    for _ = 1, 20000 do
      if not cat.alive and w.turn.state == "aiming" and w.tick % 2 == 0 then
        break
      end
      if w.turn.team == mine and w.turn.state == "aiming" then
        room.loop({ fake.message(host, OPS.fire, GRENADE_AT_FEET) })
      else
        room.loop()
      end
      for _, e in ipairs(w.events) do
        if e.type == "died" and e.cat == cat.id then
          cause = e.cause
        end
      end
    end
    assert.is_false(cat.alive)
    assert.are.equal("hp", cause)
    assert.are.equal(0, cat.hp)
    assert.are.equal("playing", room.state().phase)
    local _, replayed = replay_stream()
    assert.are.same(replayed, room.state().stats)
  end)

  it("🎮 a game stopped by the round limit with equal hit points is a draw: winner 0", function()
    open({ teams = 2, cats_per_team = 1 })
    room.loop({ fake.message(host, OPS.lobby_settings, { seed = 3 }) })
    local w = start()
    assert.are.equal("lava", w.liquid.kind)
    for _ = 1, 40000 do
      if room.state().phase ~= "playing" then
        break
      end
      if w.turn.state == "aiming" then
        room.loop({ fake.message(presence_of(w.turn.team), OPS.skip, {}) })
      else
        room.loop()
      end
    end
    assert.are.equal("ended", room.state().phase)
    assert.is_nil(w.result.winner)
    assert.are.equal(0, last(room, OPS.game_end).winner)
  end)

  it("🚫 a second fire, or an input after a skip, in the same tick is refused", function()
    open({ teams = 2, cats_per_team = 1 })
    local w = start()
    until_state("aiming")
    local p = presence_of(w.turn.team)
    room.loop({
      fake.message(p, OPS.fire, { weapon = "bazooka", angle = 300, power = 40 }),
      fake.message(p, OPS.fire, { weapon = "grenade", angle = 300, power = 40 }),
    })
    assert.are.same({ code = "not_now" }, last(room, OPS.refused, p))
    room.loop()
    local fires = 0
    for _, entry in ipairs(ticks_inputs()) do
      if entry.input.kind == "fire" then
        fires = fires + 1
      end
    end
    assert.are.equal(1, fires)
    until_state("turn_start")
    until_state("aiming")
    local q = presence_of(w.turn.team)
    room.loop({
      fake.message(q, OPS.skip, {}),
      fake.message(q, OPS.input, { kind = "move", direction = 1 }),
    })
    assert.are.same({ code = "not_now" }, last(room, OPS.refused, q))
  end)

  it("📡 an air strike carries its column into the game, and is refused once spent", function()
    open({ teams = 2, cats_per_team = 1 })
    local w = start()
    until_state("aiming")
    local p = presence_of(w.turn.team)
    local strike = { weapon = "airstrike", angle = 0, power = 1, target = 100 }
    room.loop({ fake.message(p, OPS.fire, strike) })
    assert.are.same({ code = "no_ammo" }, last(room, OPS.refused, p))
    w.teams[w.turn.team].ammo[weapons.index_of("airstrike")] = 1
    local off = { weapon = "airstrike", angle = 0, power = 1, target = w.terrain.width }
    room.loop({ fake.message(p, OPS.fire, off) })
    assert.are.same({ code = "invalid_target" }, last(room, OPS.refused, p))
    room.loop({
      fake.message(p, OPS.fire, strike),
      fake.message(p, OPS.input, { kind = "move", direction = 1 }),
    })
    assert.are.same({ code = "not_now" }, last(room, OPS.refused, p))
    room.loop()
    local fired = nil
    for _, entry in ipairs(ticks_inputs()) do
      if entry.input.kind == "fire" then
        fired = entry.input
      end
    end
    assert.are.same({ "airstrike", 100 }, { fired.weapon, fired.target })
    assert.are.equal("flight", w.turn.state)
    assert.are.equal(5, #w.projectiles)
  end)

  it(
    "🐑 Fire sets off the Waddler in flight with none left, and is refused with none walking",
    function()
      open({ teams = 2, cats_per_team = 1 })
      local w = start()
      until_state("aiming")
      local p = presence_of(w.turn.team)
      local team = w.turn.team
      local slot = weapons.index_of("waddler")
      w.teams[team].ammo[slot] = 1
      local fire = { weapon = "waddler", angle = 0, power = 1 }
      room.loop({ fake.message(p, OPS.fire, fire) })
      room.loop()
      assert.are.same({ "flight", 0 }, { w.turn.state, w.teams[team].ammo[slot] })
      for _ = 1, 40 do
        room.loop()
      end
      room.loop({
        fake.message(p, OPS.fire, { weapon = "tentacle", angle = 0, power = 1 }),
        fake.message(p, OPS.fire, fire),
      })
      assert.are.same({ code = "not_now" }, last(room, OPS.refused, p))
      room.loop()
      assert.are.same({ 0, "retreat" }, { #w.projectiles, w.turn.state })
      room.loop({ fake.message(p, OPS.fire, fire) })
      assert.are.same({ code = "not_now" }, last(room, OPS.refused, p))
    end
  )

  it("🚀 a player who leaves in the middle of a jetpack flight has its engine cut", function()
    open({ teams = 2, cats_per_team = 1 })
    local w = start()
    until_state("aiming")
    local p = presence_of(w.turn.team)
    w.teams[w.turn.team].ammo[weapons.index_of("jetpack")] = 1
    room.loop({
      fake.message(p, OPS.fire, { weapon = "jetpack", angle = 0, power = 1 }),
      fake.message(p, OPS.input, { kind = "climb", direction = -1 }),
    })
    room.loop()
    local c = turn.active_cat(w)
    assert.is_true(c.jet > 0)
    room.leave(p)
    room.loop()
    room.loop()
    assert.are.equal(0, c.jet)
  end)

  it("🐙 a tentacle throw keeps the tick open: an input right after it goes through", function()
    open({ teams = 2, cats_per_team = 1 })
    local w = start()
    until_state("aiming")
    local p = presence_of(w.turn.team)
    room.loop({
      fake.message(p, OPS.fire, { weapon = "tentacle", angle = 256, power = 1 }),
      fake.message(p, OPS.input, { kind = "climb", direction = -1 }),
      fake.message(p, OPS.input, { kind = "move", direction = 1 }),
    })
    assert.is_nil(last(room, OPS.refused, p))
    room.loop()
    local kinds = {}
    for _, entry in ipairs(ticks_inputs()) do
      kinds[#kinds + 1] = entry.input.kind
    end
    assert.are.same({ "fire", "climb", "move" }, kinds)
    assert.are.equal("aiming", w.turn.state)
  end)

  it(
    "🏠 once ended, only the host rematches, no stranger joins, a gone human loses the seat",
    function()
      open({ teams = 2, cats_per_team = 1 })
      local w = start()
      for _ = 1, 20000 do
        if room.state().phase ~= "playing" then
          break
        end
        if w.turn.state == "aiming" then
          room.loop({ fake.message(presence_of(w.turn.team), OPS.fire, GRENADE_AT_FEET) })
        else
          room.loop()
        end
      end
      assert.are.equal("ended", room.state().phase)
      nk.add_user("stranger", "Stranger")
      local ok, reason = room.join(fake.presence("stranger"))
      assert.is_false(ok)
      assert.are.equal("game_in_progress", reason)
      room.loop({ fake.message(guest, OPS.rematch, {}) })
      assert.are.same({ code = "not_host" }, last(room, OPS.refused, guest))
      assert.are.equal("ended", room.state().phase)
      room.leave(guest)
      room.loop({ fake.message(host, OPS.rematch, {}) })
      local lobby = last(room, OPS.lobby_state)
      assert.are.equal("host", lobby.seats[room.state().players.host.seat].user)
      local freed = 0
      for _, seat in ipairs(lobby.seats) do
        if seat.user == nil then
          freed = freed + 1
        end
      end
      assert.are.equal(1, freed)
      assert.is_nil(room.state().players.g1)
    end
  )

  it(
    "🏠 game_end names the host, and is sent again to all when the host leaves the ended game",
    function()
      open({ teams = 2, cats_per_team = 1 })
      local w = start()
      for _ = 1, 20000 do
        if room.state().phase ~= "playing" then
          break
        end
        local p = presence_of(w.turn.team)
        if w.turn.state == "aiming" and p then
          room.loop({ fake.message(p, OPS.fire, GRENADE_AT_FEET) })
        else
          room.loop()
        end
      end
      assert.are.equal("ended", room.state().phase)
      assert.are.equal("host", last(room, OPS.game_end, guest).host)
      local before = #room.received(OPS.game_end, guest)
      room.leave(host)
      assert.are.equal(before + 1, #room.received(OPS.game_end, guest))
      assert.are.equal("g1", last(room, OPS.game_end, guest).host)
      room.loop({ fake.message(guest, OPS.rematch, {}) })
      assert.are.equal("lobby", room.state().phase)
    end
  )

  it("🏠 after a rematch, a seat left by a departed player shows no team any more", function()
    nk = fake.install()
    local identity = require("server.identity")
    local members = { "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot" }
    identity.team_set({ user_id = "g1" }, nk.json_encode({ name = "Gel Gang", members = members }))
    room = room_support.open(nk, { teams = 2, cats_per_team = 1 })
    host = room_support.arrive(nk, room, "host", "Host")
    guest = room_support.arrive(nk, room, "g1", "Guest")
    room.loop({ fake.message(host, OPS.lobby_settings, { seed = 4 }) })
    local w = start()
    for _ = 1, 20000 do
      if room.state().phase ~= "playing" then
        break
      end
      local p = presence_of(w.turn.team)
      if w.turn.state == "aiming" and p then
        room.loop({ fake.message(p, OPS.fire, GRENADE_AT_FEET) })
      else
        room.loop()
      end
    end
    room.leave(guest)
    room.loop({ fake.message(host, OPS.rematch, {}) })
    assert.are.same({ kind = "open" }, last(room, OPS.lobby_state, host).seats[2])
    room_support.arrive(nk, room, "g2", "Late")
    assert.are.same(
      { kind = "open", user = "g2", name = "Late" },
      last(room, OPS.lobby_state, host).seats[2]
    )
  end)

  it("🏠 the host's rematch brings everyone back to the lobby with the same seats", function()
    open({ teams = 3, cats_per_team = 1 }, "alone")
    local w = start()
    local mine = room.state().players.host.seat
    for _ = 1, 20000 do
      if room.state().phase ~= "playing" then
        break
      end
      if w.turn.team == mine and w.turn.state == "aiming" then
        room.loop({ fake.message(host, OPS.fire, GRENADE_AT_FEET) })
      else
        room.loop()
      end
    end
    assert.are.equal("ended", room.state().phase)
    room.loop({ fake.message(host, OPS.fire, GRENADE_AT_FEET) })
    assert.are.same({ code = "wrong_phase" }, last(room, OPS.refused, host))
    room.loop({ fake.message(host, OPS.rematch, {}) })
    assert.are.equal("lobby", room.state().phase)
    assert.is_nil(room.state().world)
    local lobby = last(room, OPS.lobby_state)
    assert.are.same({ kind = "open", user = "host", name = "Host" }, lobby.seats[1])
    assert.are.same({ kind = "open" }, lobby.seats[2])
    assert.are.same({ kind = "open" }, lobby.seats[3])
    assert.are.same({ code = room.state().code, phase = "lobby" }, nk.json_decode(room.label()))
    start()
    assert.are.equal("playing", room.state().phase)
  end)

  it("🏠 only a registered player can join a game in progress", function()
    open({ teams = 2, cats_per_team = 1 })
    start()
    nk.add_user("stranger", "Stranger")
    local ok, reason = room.join(fake.presence("stranger"))
    assert.is_false(ok)
    assert.are.equal("game_in_progress", reason)
    assert.is_true(room.join(fake.presence("g1", "s-g1-again")))
  end)
end)

describe("🔁 absences and snapshots (§6.6, §6.7, D-08)", function()
  local nk, room, host, guest

  local function open()
    nk = fake.install()
    room = room_support.open(nk, { teams = 2, cats_per_team = 1 })
    host = room_support.arrive(nk, room, "host", "Host")
    guest = room_support.arrive(nk, room, "g1", "Guest")
    room.loop({ fake.message(host, OPS.lobby_settings, { seed = 4 }) })
    room.loop({ fake.message(host, OPS.start, {}) })
    return room.state().world
  end

  local function presence_of(team)
    for _, p in ipairs({ host, guest }) do
      if room.state().players[p.user_id].seat == team then
        return p
      end
    end
  end

  local function run_until(check, limit)
    for _ = 1, limit or 3000 do
      if check() then
        return
      end
      room.loop()
    end
    error("condition never reached")
  end

  local function inputs_of(team, from)
    local out = {}
    for i, t in ipairs(room.received(OPS.ticks)) do
      if i > (from or 0) then
        for _, entry in ipairs(t.inputs) do
          if entry.input.team == team then
            out[#out + 1] = entry
          end
        end
      end
    end
    return out
  end

  it(
    "🔁 a player who disconnects during their turn is played by a bot, then takes back control",
    function()
      local w = open()
      run_until(function()
        return w.turn.state == "aiming"
      end)
      local team = w.turn.team
      local away = presence_of(team)
      local other = presence_of(3 - team)
      room.leave(away)
      assert.is_not_nil(room.state().driver.bots[team])
      for _ = 1, 5 do
        room.loop()
      end
      local back = fake.presence(away.user_id, "s-back")
      assert.is_true(room.join(back))
      assert.are.equal(w.tick, last(room, OPS.snapshot, back).tick)
      room.loop({ fake.message(back, OPS.input, { kind = "move", direction = 1 }) })
      assert.are.same({ code = "not_your_turn" }, last(room, OPS.refused, back))
      run_until(function()
        return w.turn.team ~= team
      end)
      local played = inputs_of(team)
      assert.are.equal(2, #played)
      assert.are.same({ team = team, kind = "move", direction = 0 }, played[1].input)
      assert.truthy(played[2].input.kind == "fire" or played[2].input.kind == "skip")
      assert.is_nil(room.state().driver.bots[team])
      run_until(function()
        return w.turn.state == "aiming"
      end)
      room.loop({ fake.message(other, OPS.skip, {}) })
      run_until(function()
        return w.turn.team == team and w.turn.state == "aiming"
      end)
      local seen = #room.received(OPS.ticks)
      room.loop({ fake.message(back, OPS.fire, { weapon = "bazooka", angle = 300, power = 50 }) })
      room.loop()
      room.loop()
      local mine = inputs_of(team, seen)
      assert.are.equal(1, #mine)
      assert.are.same(
        { team = team, kind = "fire", weapon = "bazooka", angle = 300, power = 50 },
        mine[1].input
      )
    end
  )

  it(
    "🔁 a player who leaves while walking lets go of the direction, by a regular input",
    function()
      local w = open()
      run_until(function()
        return w.turn.state == "aiming"
      end)
      local team = w.turn.team
      local away = presence_of(team)
      room.loop({ fake.message(away, OPS.input, { kind = "move", direction = 1 }) })
      local walker = w.cats[w.turn.cat]
      assert.are.equal(1, walker.walk)
      room.leave(away)
      room.loop()
      room.loop()
      assert.are.equal(0, walker.walk)
      local released = inputs_of(team)
      assert.are.same({ team = team, kind = "move", direction = 0 }, released[#released].input)
    end
  )

  it(
    "🔁 a player who leaves hanging on the tentacle lets go of it, by a regular input",
    function()
      local w = open()
      run_until(function()
        return w.turn.state == "aiming"
      end)
      local team = w.turn.team
      local away = presence_of(team)
      room.loop({ fake.message(away, OPS.fire, { weapon = "tentacle", angle = 768, power = 1 }) })
      local hanging = w.cats[w.turn.cat]
      assert.is_true(hanging.hanging)
      room.leave(away)
      room.loop()
      room.loop()
      assert.is_false(hanging.hanging)
      local played = inputs_of(team)
      assert.are.same(
        { team = team, kind = "jump", direction = hanging.facing },
        played[#played].input
      )
    end
  )

  it(
    "🤖 all are told which teams a bot plays: departure, return, hand-back (§6.4, §6.7)",
    function()
      local w = open()
      run_until(function()
        return w.turn.state == "aiming"
      end)
      local team = w.turn.team
      local away, stay = presence_of(team), presence_of(3 - team)
      local seated, with_away = {}, {}
      for i, seat in ipairs(room.state().seats) do
        if seat.user == nil then
          seated[#seated + 1] = i
        end
        if seat.user == nil or i == team then
          with_away[#with_away + 1] = i
        end
      end
      room.leave(away)
      assert.are.same({ bots = with_away }, last(room, OPS.pilots, stay))
      local back = fake.presence(away.user_id, "s-back")
      local before = #room.sent
      room.join(back)
      local order = {}
      for i = before + 1, #room.sent do
        local m = room.sent[i]
        for _, p in ipairs(m.presences or {}) do
          if p.session_id == "s-back" then
            order[#order + 1] = m.op_code
          end
        end
      end
      assert.are.same({ OPS.game_start, OPS.snapshot, OPS.pilots }, order)
      assert.are.same(room.received(OPS.game_start)[1], last(room, OPS.game_start, back))
      assert.are.same({ bots = with_away }, last(room, OPS.pilots, back))
      local told = #room.received(OPS.pilots, stay)
      run_until(function()
        return room.state().driver.bots[team] == nil
      end)
      assert.are.same({ bots = seated }, last(room, OPS.pilots, stay))
      assert.are.same({ bots = seated }, last(room, OPS.pilots, back))
      assert.are.equal(told + 1, #room.received(OPS.pilots, stay))
      local turns = w.teams[1].turns + w.teams[2].turns
      run_until(function()
        return w.teams[1].turns + w.teams[2].turns > turns
      end)
      assert.are.equal(told + 1, #room.received(OPS.pilots, stay))
    end
  )

  it("🔁 the returning human is refused until the next turn starts, retreat included", function()
    local w = open()
    run_until(function()
      return w.turn.state == "aiming"
    end)
    local team = w.turn.team
    local away = presence_of(team)
    room.leave(away)
    local back = fake.presence(away.user_id, "s-back")
    room.join(back)
    run_until(function()
      return w.turn.state == "retreat"
    end)
    room.loop({ fake.message(back, OPS.input, { kind = "move", direction = 1 }) })
    assert.are.same({ code = "not_your_turn" }, last(room, OPS.refused, back))
    assert.is_not_nil(room.state().driver.bots[team])
    run_until(function()
      return w.turn.team ~= team
    end)
    assert.is_nil(room.state().driver.bots[team])
  end)

  it("🔁 a human who leaves again before the hand-back stays replaced", function()
    local w = open()
    run_until(function()
      return w.turn.state == "aiming"
    end)
    local team = w.turn.team
    local away = presence_of(team)
    room.leave(away)
    local back = fake.presence(away.user_id, "s-back")
    room.join(back)
    room.leave(back)
    run_until(function()
      return w.turn.team ~= team
    end)
    assert.is_not_nil(room.state().driver.bots[team])
  end)

  it("🔁 a second live session keeps the team in human hands when the first one drops", function()
    local w = open()
    run_until(function()
      return w.turn.state == "aiming"
    end)
    local team = w.turn.team
    local first = presence_of(team)
    local second = fake.presence(first.user_id, "s-second")
    assert.is_true(room.join(second))
    room.leave(first)
    assert.is_nil(room.state().driver.bots[team])
    room.loop({ fake.message(second, OPS.skip, {}) })
    assert.is_nil(last(room, OPS.refused, second))
    assert.are_not.equal("aiming", w.turn.state)
  end)

  it("🔁 a bot replacing a human who aimed 100 ticks still waits before firing", function()
    local w = open()
    run_until(function()
      return w.turn.state == "aiming" and w.turn.ticks >= 100
    end)
    local team = w.turn.team
    room.leave(presence_of(team))
    local took = w.tick
    run_until(function()
      return w.turn.state ~= "aiming"
    end)
    room.loop()
    room.loop()
    local fired = nil
    for _, entry in ipairs(inputs_of(team)) do
      if entry.input.kind == "fire" then
        fired = entry
      end
    end
    assert.is_not_nil(fired)
    assert.is_true(
      fired.at - took >= rules.BOT_WAIT_MIN,
      "fired " .. (fired.at - took) .. " ticks after"
    )
  end)

  it("🔁 a player who leaves outside their turn gets a bot for their next turn", function()
    local w = open()
    run_until(function()
      return w.turn.state == "aiming"
    end)
    local team = w.turn.team
    room.leave(presence_of(3 - team))
    room.loop({ fake.message(presence_of(team), OPS.skip, {}) })
    run_until(function()
      return w.turn.team ~= team and w.turn.state == "flight"
    end)
    room.loop()
    room.loop()
    local played = inputs_of(3 - team)
    assert.are.equal(1, #played)
    assert.are.equal("fire", played[1].input.kind)
  end)

  it(
    "🔁 a returning player's snapshot restores the server world, and the stream continues it",
    function()
      local w = open()
      run_until(function()
        return w.turn.state == "aiming"
      end)
      local away = presence_of(3 - w.turn.team)
      room.leave(away)
      room.loop({
        fake.message(
          presence_of(w.turn.team),
          OPS.fire,
          { weapon = "grenade", angle = 300, power = 40 }
        ),
      })
      room.loop()
      local back = fake.presence(away.user_id, "s-back")
      room.join(back)
      local snap = last(room, OPS.snapshot, back)
      local restored = assert(world.restore(snap.state))
      assert.are.same({ world.checksum(w) }, { world.checksum(restored) })
      local seen = #room.received(OPS.ticks)
      for _ = 1, 400 do
        room.loop()
      end
      local by_tick = {}
      for i, t in ipairs(room.received(OPS.ticks)) do
        if i > seen - 1 then
          for _, entry in ipairs(t.inputs) do
            if entry.at >= snap.tick then
              by_tick[entry.at] = by_tick[entry.at] or {}
              table.insert(by_tick[entry.at], entry.input)
            end
          end
        end
      end
      local sums = room.received(OPS.checksum)
      local checked = 0
      for _, sum in ipairs(sums) do
        if sum.tick > snap.tick then
          while restored.tick < sum.tick do
            world.step(restored, by_tick[restored.tick])
          end
          assert.are.same(sum.sum, { world.checksum(restored) })
          checked = checked + 1
        end
      end
      assert.is_true(checked >= 10)
    end
  )

  it("🔁 a snapshot request is answered at most every 5 s, and a divergence is a warn", function()
    local w = open()
    local before = w.tick
    room.loop({ fake.message(host, OPS.snapshot_request, { tick = 30 }) })
    assert.are.equal(before, last(room, OPS.snapshot, host).tick)
    local warns = nk.logged("🧮 checksum divergence")
    assert.are.equal(1, #warns)
    assert.are.equal("warn", warns[1].level)
    assert.truthy(warns[1].message:find("at=30", 1, true))
    assert.truthy(warns[1].message:find("player=Host", 1, true))
    local seat = room.state().players.host.seat
    assert.truthy(warns[1].message:find("team=" .. seat, 1, true))
    assert.truthy(warns[1].message:find("room=" .. room.state().code, 1, true))
    room.loop({ fake.message(host, OPS.snapshot_request, { tick = 60 }) })
    assert.are.same({ code = "too_soon" }, last(room, OPS.refused, host))
    assert.are.equal(1, #nk.logged("🧮 checksum divergence"))
    for _ = 1, rules.SNAPSHOT_REQUEST_TICKS do
      room.loop()
    end
    local count = #room.received(OPS.snapshot, host)
    room.loop({ fake.message(host, OPS.snapshot_request, {}) })
    assert.are.equal(count + 1, #room.received(OPS.snapshot, host))
  end)

  it("🔁 a player back in an ended game receives the final snapshot and game_end", function()
    nk = fake.install()
    room = room_support.open(nk, { teams = 2, cats_per_team = 1 })
    host = room_support.arrive(nk, room, "host", "Host")
    room.loop({ fake.message(host, OPS.lobby_settings, { seed = 4 }) })
    room.loop({ fake.message(host, OPS.start, {}) })
    local w = room.state().world
    local mine = room.state().players.host.seat
    for _ = 1, 20000 do
      if room.state().phase ~= "playing" then
        break
      end
      if w.turn.team == mine and w.turn.state == "aiming" then
        room.loop({ fake.message(host, OPS.fire, GRENADE_AT_FEET) })
      else
        room.loop()
      end
    end
    assert.are.equal("ended", room.state().phase)
    room.leave(host)
    local back = fake.presence("host", "s-back")
    assert.is_true(room.join(back))
    assert.are.equal(w.tick, last(room, OPS.snapshot, back).tick)
    assert.are.equal(3 - mine, last(room, OPS.game_end, back).winner)
    local started = room.received(OPS.game_start)
    assert.are.same(started[1], last(room, OPS.game_start, back))
    local order = {}
    for _, m in ipairs(room.sent) do
      for _, p in ipairs(m.presences or {}) do
        if p.session_id == "s-back" then
          order[#order + 1] = m.op_code
        end
      end
    end
    assert.are.same({ OPS.game_start, OPS.snapshot, OPS.game_end }, order)
    assert.are.equal("host", last(room, OPS.game_end, back).host)
  end)

  it(
    "🔁 a second session of a player still present gets game_start, the snapshot and pilots",
    function()
      local w = open()
      run_until(function()
        return w.turn.state == "aiming"
      end)
      local second = fake.presence(guest.user_id, "s-second")
      local before = #room.sent
      room.join(second)
      local order = {}
      for i = before + 1, #room.sent do
        for _, p in ipairs(room.sent[i].presences or {}) do
          if p.session_id == "s-second" then
            order[#order + 1] = room.sent[i].op_code
          end
        end
      end
      assert.are.same({ OPS.game_start, OPS.snapshot, OPS.pilots }, order)
    end
  )
end)

describe("🏠 a room closed during a game", function()
  it("🏠 logs its tick timings when it closes", function()
    local nk = fake.install()
    local room = room_support.open(nk, { teams = 2, cats_per_team = 1 })
    local host = room_support.arrive(nk, room, "host", "Host")
    room.loop({ fake.message(host, OPS.start, {}) })
    local w = room.state().world
    room.leave(host)
    for _ = 1, rules.ROOM_EMPTY_SECONDS * rules.TICKS_PER_SECOND do
      room.loop()
    end
    assert.is_false(room.open())
    local closed = nk.logged("🏠 room closed")
    assert.are.equal(1, #closed)
    assert.truthy(closed[1].message:find("tick_ms_max=", 1, true))
    assert.truthy(closed[1].message:find("ticks=" .. w.tick .. " ", 1, true), closed[1].message)
  end)
end)

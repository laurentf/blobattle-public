local cat = require("shared.sim.cat")
local rules = require("shared.sim.rules")
local terrains = require("spec.support.terrains")
local weapons = require("shared.sim.weapons.registry")
local world = require("shared.sim.world")

local WIDTH = 400
local FEET = terrains.GROUND - 1

local function duel(t, first, second)
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

local function pair(first, second)
  return duel(terrains.flat(WIDTH), { first, FEET }, { second, FEET })
end

local function send(w, input)
  input.team = w.turn.team
  return world.step(w, { input })
end

local function face(w, direction)
  send(w, { kind = "move", direction = direction })
  send(w, { kind = "move", direction = 0 })
end

local function punch(w, angle, power)
  return send(w, { kind = "fire", weapon = "uppercut", angle = angle or 0, power = power or 1 })
end

local function index_of(events, kind)
  for i, e in ipairs(events) do
    if e.type == kind then
      return i
    end
  end
  return nil
end

local function find(events, kind, cat_id)
  for _, e in ipairs(events) do
    if e.type == kind and (cat_id == nil or e.cat == cat_id) then
      return e
    end
  end
  return nil
end

describe("🥊 the uppercut (§8.2)", function()
  it("🥊 uses §8.2's figures", function()
    local u = weapons.get("uppercut")
    assert.are.same(
      { kind = "melee", ammo = -1, reach = 10, damage = 30, push_x = 512, push_y = 1024 },
      {
        kind = u.kind,
        ammo = require("shared.sim.rules").AMMO.uppercut,
        reach = u.melee.reach,
        damage = u.melee.damage,
        push_x = u.melee.push_x,
        push_y = u.melee.push_y,
      }
    )
  end)

  it("🥊 sends the blob in front flying in an arc, 30 damage, and ends the turn", function()
    local w, a, b = pair(100, 110)
    local events = punch(w)
    assert.are.same({ "fired", a.id }, { events[1].type, events[1].cat })
    assert.is_true(index_of(events, "damaged") > 1)
    local hurt = find(events, "damaged", b.id)
    assert.are.same({ 30, "melee" }, { hurt.amount, hurt.cause })
    assert.are.same({ 100, 70 }, { a.hp, b.hp })
    assert.are.same({ 512, -1024 + rules.GRAVITY }, { b.vx, b.vy })
    assert.are.equal("retreat", w.turn.state)
    local from, feet = cat.pixel(b)
    local top = feet
    for _ = 1, 120 do
      world.step(w)
      local _, y = cat.pixel(b)
      top = math.min(top, y)
    end
    assert.is_true(feet - top >= 30, "rose " .. (feet - top) .. " px")
    assert.is_true(cat.pixel(b) - from >= 30, "flew " .. (cat.pixel(b) - from) .. " px")
    assert.are.same({ 0, 0 }, { a.vx, a.vy })
  end)

  it("🥊 reaches 10 px in front of the striker's box, not one more", function()
    local w, _, b = pair(100, 115)
    punch(w)
    assert.are.equal(70, b.hp)
    w, _, b = pair(100, 116)
    local events = punch(w)
    assert.is_nil(find(events, "damaged"))
    assert.are.same({ 100, 0 }, { b.hp, b.vx })
    assert.are.equal("retreat", w.turn.state)
  end)

  it("🥊 starts one pixel in front of the striker's pixel", function()
    local w, _, b = pair(100, 101)
    punch(w)
    assert.are.equal(70, b.hp)
    for _, at in ipairs({ 100, 95 }) do
      w, _, b = pair(100, at)
      assert.is_nil(find(punch(w), "damaged"), "at " .. at)
      assert.are.same({ 100, 0 }, { b.hp, b.vx }, "at " .. at)
    end
  end)

  it("🥊 hits nobody behind, nor the striker", function()
    local w, a, b = pair(100, 94)
    local events = punch(w)
    assert.is_nil(find(events, "damaged"))
    assert.are.same({ 100, 100, 0, 0 }, { a.hp, b.hp, a.vx, b.vx })
    assert.are.equal("retreat", w.turn.state)
  end)

  it("🥊 leaves a dead blob's puddle alone", function()
    local w, _, b = pair(100, 110)
    b.alive = false
    assert.is_nil(find(punch(w), "damaged"))
    assert.are.same({ 100, 0, 0 }, { b.hp, b.vx, b.vy })
  end)

  it("🥊 refuses an angle or a power out of the bounds of a shot", function()
    for _, bad in ipairs({ { 1024, 1 }, { -1, 1 }, { 0, 0 }, { 0, 101 } }) do
      local w, _, b = pair(100, 110)
      local events = punch(w, bad[1], bad[2])
      assert.is_nil(find(events, "fired"), bad[1] .. "/" .. bad[2])
      assert.are.same({ "aiming", 100 }, { w.turn.state, b.hp })
    end
  end)

  it("🥊 hits only at the striker's height", function()
    local w, _, b = duel(terrains.cliff(6), { 103, FEET }, { 96, FEET - 6 })
    face(w, -1)
    punch(w)
    assert.are.same({ 70, -512 }, { b.hp, b.vx })
    w, _, b = duel(terrains.cliff(7), { 103, FEET }, { 96, FEET - 7 })
    face(w, -1)
    punch(w)
    assert.are.same({ 100, 0 }, { b.hp, b.vx })
    w, _, b = duel(terrains.cliff(6), { 96, FEET - 6 }, { 103, FEET })
    punch(w)
    assert.are.same({ 70, 512 }, { b.hp, b.vx })
    w, _, b = duel(terrains.cliff(7), { 96, FEET - 7 }, { 103, FEET })
    punch(w)
    assert.are.same({ 100, 0 }, { b.hp, b.vx })
  end)

  it("🥊 the same punch to the left mirrors the one to the right, tick by tick", function()
    local wr, ar, br = pair(100, 110)
    local wl, al, bl = pair(WIDTH - 100, WIDTH - 110)
    face(wr, 1)
    face(wl, -1)
    punch(wr)
    punch(wl)
    assert.are.equal(70, bl.hp)
    for i = 1, 120 do
      local where = "tick " .. i
      assert.are.same({ -br.vx, br.vy, br.hp }, { bl.vx, bl.vy, bl.hp }, where)
      assert.are.equal(WIDTH * 256 + 256 - br.x, bl.x, where)
      assert.are.equal(br.y, bl.y, where)
      assert.are.equal(WIDTH * 256 + 256 - ar.x, al.x, where)
      world.step(wr)
      world.step(wl)
    end
  end)
end)

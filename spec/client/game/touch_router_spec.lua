local camera_rig = require("game.camera_rig")
local controls = require("input.controls")
local hud_model = require("game.hud_model")
local palette = require("ui.palette")
local touch_router = require("game.touch_router")

local CAT = { x = 300, y = 200, radius = 0 }
local STRIKE = { "bazooka", "airstrike" }
local ALL = {
  "bazooka",
  "grenade",
  "tentacle",
  "uppercut",
  "chomp",
  "dynamite",
  "cluster",
  "airstrike",
  "waddler",
  "jetpack",
}

local function fake_authority()
  local sent = {}
  return {
    sent = sent,
    send = function(name, body)
      sent[#sent + 1] = { name = name, body = body }
    end,
  }
end

local function info(fields)
  return {
    mine = fields.mine ~= false,
    state = fields.state or "aiming",
    cat = CAT,
    facing = 1,
    weapons = fields.weapons or STRIKE,
  }
end

local function setup(weapons)
  hud_model.reset()
  hud_model.scale = 1
  local authority = fake_authority()
  local c = controls.new({ authority = authority })
  controls.turn(c, info({ weapons = weapons }))
  local rig = camera_rig.new({
    map_width = 896,
    map_height = 256,
    screen = { width = 844, height = 390 },
  })
  camera_rig.place(rig, 400, 100)
  local r = touch_router.new({ rig = rig, controls = c })
  return r, c, authority, rig
end

local function finger(r, id, points)
  local first, last = points[1], points[#points]
  touch_router.pointer(r, { id = id, state = "pressed", x = first[1], y = first[2], now = 0 })
  for i = 2, #points do
    touch_router.pointer(
      r,
      { id = id, state = "moved", x = points[i][1], y = points[i][2], now = 0 }
    )
  end
  touch_router.pointer(r, { id = id, state = "released", x = last[1], y = last[2], now = 0 })
end

local function sources()
  local list = {}
  local pipe = io.popen('find client -name "*.script" -o -name "*.gui_script" -o -name "*.lua"')
  for line in pipe:lines() do
    list[#list + 1] = line
  end
  pipe:close()
  return list
end

describe("👆 the touch router, the air strike and the grid of ten (§7.3)", function()
  it("📡 a still tap on the map places the column under the finger", function()
    local r, c, _, rig = setup()
    controls.weapon(c, "airstrike")
    finger(r, 1, { { 500, 200 }, { 505, 196 } })
    local x = camera_rig.to_world(rig, 505, 196)
    assert.are.equal(math.floor(x), controls.target(c))
  end)

  it("📡 a drag of more than 12 points, either way, pans and places nothing", function()
    local r, c = setup()
    controls.weapon(c, "airstrike")
    finger(r, 1, { { 500, 200 }, { 540, 200 } })
    assert.is_nil(controls.target(c))
    finger(r, 2, { { 500, 200 }, { 500, 200 + 30 } })
    assert.is_nil(controls.target(c))
    finger(r, 3, { { 500, 200 }, { 520, 200 }, { 500, 200 } })
    assert.is_not_nil(controls.target(c))
  end)

  it("📡 the action button strikes only while it reads Strike", function()
    local r, c, authority = setup()
    controls.weapon(c, "airstrike")
    controls.place_target(c, 100)
    hud_model.buttons.action = { x = 460, y = 330, rx = 64, ry = 32 }
    hud_model.action = "boom"
    finger(r, 1, { { 460, 330 } })
    assert.are.same({}, authority.sent)
    hud_model.action = "strike"
    finger(r, 2, { { 460, 330 } })
    assert.are.equal(100, authority.sent[1].body.target)
  end)

  it("🔟 the tenth grid cell picks the tenth weapon", function()
    local r, c = setup(ALL)
    hud_model.weapons = ALL
    hud_model.grid = true
    hud_model.buttons.grid_10 = { x = 598, y = 34, rx = 64, ry = 28 }
    finger(r, 1, { { 598, 34 } })
    assert.are.equal("jetpack", controls.current_weapon(c))
    assert.is_false(hud_model.grid)
  end)

  it("📡 choosing the air strike again keeps the column", function()
    local _, c = setup()
    controls.weapon(c, "airstrike")
    controls.place_target(c, 77)
    controls.weapon(c, "airstrike")
    assert.are.equal(77, controls.target(c))
  end)

  it("📡 holding the fire key strikes once, even if a new column is placed", function()
    local _, c, authority = setup()
    controls.weapon(c, "airstrike")
    controls.place_target(c, 33)
    controls.charge(c, 0.1)
    controls.place_target(c, 60)
    controls.charge(c, 0.1)
    assert.are.equal(1, #authority.sent)
  end)

  it("🎨 every palette colour a client script names exists", function()
    local missing = {}
    for _, path in ipairs(sources()) do
      local file = assert(io.open(path, "rb"))
      local source = file:read("*a")
      file:close()
      for name in source:gmatch("palette%.([%u_]+)") do
        if palette[name] == nil then
          missing[#missing + 1] = path .. ": palette." .. name
        end
      end
    end
    assert.are.same({}, missing)
  end)
end)

describe("📡 the air strike at the fingers and the keyboard (§7.3)", function()
  it("📡 the air strike shows no aim line, even at the keyboard (§7.3)", function()
    local _, c = setup()
    controls.weapon(c, "airstrike")
    controls.aim_key(c, 1, 0.1)
    assert.is_nil(controls.aim(c))
    controls.charge(c, 0.1)
    assert.is_nil(controls.aim(c))
  end)

  it("📡 a tap beside the map never holds a column the server refuses", function()
    local r, c, _, rig = setup()
    rig.x = -200
    controls.weapon(c, "airstrike")
    finger(r, 1, { { 100, 200 } })
    local column = controls.target(c)
    assert.is_true(column == nil or (column >= 0 and column < rig.map_width), tostring(column))
  end)

  it("📡 the still finger of a pinch does not move the target", function()
    local r, c = setup()
    controls.weapon(c, "airstrike")
    touch_router.pointer(r, { id = 1, state = "pressed", x = 300, y = 200, now = 0 })
    touch_router.pointer(r, { id = 2, state = "pressed", x = 600, y = 200, now = 0 })
    touch_router.pointer(r, { id = 2, state = "moved", x = 700, y = 200, now = 0 })
    touch_router.pointer(r, { id = 2, state = "released", x = 700, y = 200, now = 0 })
    touch_router.pointer(r, { id = 1, state = "released", x = 300, y = 200, now = 0 })
    assert.is_nil(controls.target(c))
  end)
end)

describe("🐑 the Boom button (§7.3)", function()
  it("🐑 the action button sets the Waddler off while it reads Boom", function()
    local r, c, authority = setup({ "bazooka" })
    controls.turn(c, {
      mine = true,
      state = "flight",
      cat = CAT,
      facing = 1,
      weapons = { "bazooka" },
      triggerable = "waddler",
    })
    hud_model.action = "boom"
    hud_model.buttons.action = { x = 460, y = 60, rx = 64, ry = 32 }
    finger(r, 1, { { 460, 60 } })
    assert.are.same(
      { { name = "fire", body = { weapon = "waddler", angle = 0, power = 1 } } },
      authority.sent
    )
  end)

  it("🐑 the action button does nothing while it reads nothing, Waddler or not", function()
    local r, c, authority = setup({ "bazooka" })
    controls.turn(c, {
      mine = true,
      state = "flight",
      cat = CAT,
      facing = 1,
      weapons = { "bazooka" },
      triggerable = "waddler",
    })
    hud_model.action = nil
    hud_model.buttons.action = { x = 460, y = 60, rx = 64, ry = 32 }
    finger(r, 1, { { 460, 60 } })
    assert.are.same({}, authority.sent)
  end)
end)

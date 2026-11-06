local camera_rig = require("game.camera_rig")

local SCREEN = { width = 2532, height = 1170 }

local function rig()
  local r = camera_rig.new({ map_width = 896, screen = SCREEN })
  camera_rig.follow(r, 400, 150)
  camera_rig.update(r, 10)
  return r
end

describe("🎥 the camera (§7.3, §7.4)", function()
  it("🎥 projects the play plane and back without drift", function()
    local r = rig()
    for _, p in ipairs({ { 400, 150 }, { 380, 170 }, { 455, 120 } }) do
      local sx, sy = camera_rig.to_screen(r, p[1], p[2])
      local wx, wy = camera_rig.to_world(r, sx, sy)
      assert.is_true(math.abs(wx - p[1]) < 1e-6 and math.abs(wy - p[2]) < 1e-6)
    end
    local cx = camera_rig.to_screen(r, 400, 150)
    assert.is_true(math.abs(cx - SCREEN.width / 2) < 1)
  end)

  it("🎥 glides to the next blob in a set time, gently, and arrives", function()
    local r = rig()
    camera_rig.glide(r)
    camera_rig.follow(r, 500, 150)
    local frames = math.floor(camera_rig.GLIDE_SECONDS * 60 + 0.5)
    for _ = 1, frames / 4 do
      camera_rig.update(r, 1 / 60)
    end
    assert.is_true(r.x - 400 < 20, "a gentle start: " .. (r.x - 400))
    for _ = frames / 4 + 1, frames do
      camera_rig.update(r, 1 / 60)
    end
    assert.is_true(math.abs(r.x - 500) < 1e-6)
    assert.is_nil(r.glide)
  end)

  it("🎥 a shot or a pan ends a glide, so the next projectile is followed briskly", function()
    for _, stop in ipairs({
      function(r)
        camera_rig.shot(r)
      end,
      function(r)
        camera_rig.pan(r, { x = 100, y = 100, dx = 10, dy = 0 })
        camera_rig.recenter(r)
      end,
    }) do
      local r = rig()
      camera_rig.glide(r)
      camera_rig.follow(r, 500, 150)
      camera_rig.update(r, 1 / 60)
      stop(r)
      assert.is_nil(r.glide)
    end
  end)

  it("🎥 follows the projectile of a new shot even after a pan", function()
    local r = rig()
    camera_rig.pan(r, { x = SCREEN.width / 2, y = SCREEN.height / 2, dx = 300, dy = 0 })
    camera_rig.shot(r)
    camera_rig.follow(r, 520, 90)
    camera_rig.update(r, 10)
    assert.is_true(math.abs(r.x - 520) < 0.5)
  end)

  it("🎥 follows its target on its own, and a pan stops it until the next turn", function()
    local r = rig()
    camera_rig.pan(r, { x = SCREEN.width / 2, y = SCREEN.height / 2, dx = 300, dy = 0 })
    camera_rig.follow(r, 400, 150)
    camera_rig.update(r, 10)
    local x = r.x
    assert.is_true(x < 390, "the pan moved the view left of the target: " .. x)
    camera_rig.turn(r)
    camera_rig.follow(r, 400, 150)
    camera_rig.update(r, 10)
    assert.is_true(math.abs(r.x - 400) < 0.5)
  end)

  it("🎥 keeps what is under the finger under the finger while panning", function()
    local r = rig()
    local wx, wy = camera_rig.to_world(r, 1000, 600)
    camera_rig.pan(r, { x = 1000, y = 600, dx = 150, dy = -80 })
    local sx, sy = camera_rig.to_screen(r, wx, wy)
    assert.is_true(math.abs(sx - 1150) < 1 and math.abs(sy - 520) < 1)
  end)

  it("🎥 zooms between an overview of the map and a close-up on a blob", function()
    local r = rig()
    camera_rig.pinch(r, 100)
    assert.are.equal(camera_rig.NEAR, r.distance)
    camera_rig.pinch(r, 0.01)
    local left = camera_rig.to_world(r, 0, SCREEN.height / 2)
    local right = camera_rig.to_world(r, SCREEN.width, SCREEN.height / 2)
    assert.is_true(right - left >= 896, "the overview shows " .. (right - left) .. " of 896")
  end)

  it(
    "📦 the overview keeps the sky above the map, where planes fly and crates come down",
    function()
      for _, screen in ipairs({ { width = 1920, height = 1080 }, { width = 844, height = 390 } }) do
        for _, map in ipairs({ { 384, 256 }, { 896, 256 }, { 1024, 256 } }) do
          local r = camera_rig.new({
            map_width = map[1],
            map_height = map[2],
            screen = screen,
            overview = true,
          })
          camera_rig.place(r, 120, 150)
          camera_rig.follow(r, 120, 150)
          camera_rig.update(r, 10)
          local _, top = camera_rig.to_screen(r, map[1] / 2, map[2] + camera_rig.SKY)
          local _, bottom = camera_rig.to_screen(r, map[1] / 2, 0)
          assert.is_true(
            top <= screen.height and bottom >= 0,
            map[1] .. ": " .. top .. ", " .. bottom
          )
        end
      end
      assert.is_true(camera_rig.SKY >= 30)
    end
  )

  it("🎥 on a computer, starts far enough out to show the whole map, centred on it", function()
    local desk = { width = 1920, height = 1080 }
    local r = camera_rig.new({ map_width = 896, map_height = 256, screen = desk, overview = true })
    assert.are.equal(r.far, r.distance)
    camera_rig.place(r, 120, 150)
    camera_rig.follow(r, 120, 150)
    camera_rig.update(r, 10)
    local left, top = camera_rig.to_screen(r, 0, 256)
    local right, bottom = camera_rig.to_screen(r, 896, 0)
    assert.is_true(left >= 0 and right <= desk.width, "sides at " .. left .. ", " .. right)
    assert.is_true(
      bottom >= 0 and top <= desk.height,
      "bottom and top at " .. bottom .. ", " .. top
    )
  end)

  it("🎥 zoomed in from the overview, it follows the action again", function()
    local desk = { width = 1920, height = 1080 }
    local r = camera_rig.new({ map_width = 896, map_height = 256, screen = desk, overview = true })
    camera_rig.pinch(r, 3)
    camera_rig.follow(r, 120, 150)
    camera_rig.update(r, 10)
    assert.is_true(math.abs(r.x - 120) < 0.5)
    camera_rig.pinch(r, 0.01)
    camera_rig.update(r, 10)
    assert.is_true(math.abs(r.x - 448) < 0.5)
  end)

  it("🎥 a resized window keeps the overview an overview", function()
    local r = camera_rig.new({
      map_width = 896,
      map_height = 256,
      screen = { width = 1920, height = 1080 },
      overview = true,
    })
    camera_rig.resize(r, 1280, 1000)
    assert.are.equal(r.far, r.distance)
  end)

  it("🎥 on a phone, starts close on the blob as before", function()
    local r = camera_rig.new({ map_width = 896, map_height = 256, screen = SCREEN })
    assert.are.equal(camera_rig.START, r.distance)
  end)

  it("🎥 recenters on the active blob on a double tap", function()
    local r = rig()
    camera_rig.pan(r, { x = 1000, y = 600, dx = 800, dy = 300 })
    camera_rig.recenter(r)
    camera_rig.follow(r, 400, 150)
    camera_rig.update(r, 10)
    assert.is_true(math.abs(r.x - 400) < 0.5)
  end)
end)

local backdrop = require("render.backdrop")
local en = require("shared.i18n.en")
local faces = require("render.faces")
local shapes = require("render.shapes")
local voxel_font = require("render.voxel_font")

local LOOK = backdrop.MEADOW

describe("🏞️ the menu backdrop (§7.2)", function()
  it("🏞️ builds its layers far to near, each wide enough for the camera's pan", function()
    local layers = backdrop.layers(7, LOOK)
    assert.are.equal(3, #layers)
    for i, layer in ipairs(layers) do
      local spec = LOOK.layers[i]
      if i > 1 then
        assert.is_true(layer.depth > layers[i - 1].depth)
      end
      local distance = LOOK.view - layer.depth
      assert.is_true(#layer.heights * layer.cell >= LOOK.width * distance / LOOK.view)
      assert.are.equal(-#layer.heights * layer.cell / 2, layer.x0)
      for _, h in ipairs(layer.heights) do
        assert.is_true(h >= spec.low and h <= spec.high and h % 1 == 0)
      end
    end
  end)

  it("🏞️ never shows a layer's end, however wide the screen and wherever the pan", function()
    for _, aspect in ipairs({ 390 / 844, 844 / 390, 2.4 }) do
      local eye = backdrop.eye(LOOK, aspect)
      assert.is_true(eye.z >= LOOK.view)
      assert.is_true(
        2 * math.tan(LOOK.camera.fov / 2) * (eye.z - 0) * aspect >= LOOK.camera.min_width - 1e-9
      )
      for _, layer in ipairs(backdrop.layers(7, LOOK)) do
        local half = math.tan(LOOK.camera.fov / 2) * (eye.z - layer.depth) * aspect
        local reach = half + LOOK.camera.pan
        assert.is_true(reach <= -layer.x0, aspect .. " @ " .. layer.depth .. ": " .. reach)
      end
    end
  end)

  it("🏞️ frames the ground a fifth of the way up the screen", function()
    for _, aspect in ipairs({ 390 / 844, 844 / 390 }) do
      local eye = backdrop.eye(LOOK, aspect)
      local half = math.tan(LOOK.camera.fov / 2) * eye.z
      local at = (LOOK.camera.ground_line - (eye.y - half)) / (2 * half)
      assert.is_true(math.abs(at - LOOK.camera.ground_at) < 1e-9, at)
    end
  end)

  it("🏞️ gives the same backdrop for a seed, and another one for another seed", function()
    assert.are.same(backdrop.layers(7, LOOK), backdrop.layers(7, LOOK))
    assert.are_not.same(backdrop.layers(7, LOOK)[3].heights, backdrop.layers(8, LOOK)[3].heights)
    assert.are.same(backdrop.clouds(7, LOOK), backdrop.clouds(7, LOOK))
  end)

  it("🏞️ stands a blob on the highest column under its whole width", function()
    local ground = { x0 = 0, cell = 2, heights = { 5, 5, 8, 5, 5, 5 } }
    assert.are.equal(16, backdrop.ground(ground, 3, 3.5))
    assert.are.equal(16, backdrop.ground(ground, 8, 3.5))
    assert.are.equal(10, backdrop.ground(ground, 11, 0.5))
    assert.are.equal(16, backdrop.ground(ground, 1, 3.5))
  end)

  it("🏞️ tells where the ground is under a point, for the blobs to stand on", function()
    local ground = backdrop.layers(7, LOOK)[3]
    local i = 10
    local x = ground.x0 + (i - 0.5) * ground.cell
    assert.are.equal(ground.heights[i] * ground.cell, backdrop.ground(ground, x))
    assert.are.equal(ground.heights[1] * ground.cell, backdrop.ground(ground, ground.x0 - 50))
  end)

  it("🏞️ drifts clouds of cubes above the hills, each at its own speed", function()
    local clouds = backdrop.clouds(7, LOOK)
    assert.are.equal(LOOK.clouds.count, #clouds)
    for _, c in ipairs(clouds) do
      assert.is_true(#c.cells >= 6)
      assert.is_true(c.y >= LOOK.clouds.low and c.y <= LOOK.clouds.high)
      assert.is_true(c.speed > 0)
    end
  end)

  it(
    "🏞️ draws under 30 000 vertices with its water, clouds, blobs, shells and title",
    function()
      local total = 0
      for _, layer in ipairs(backdrop.layers(7, LOOK)) do
        local fields = { cell = layer.cell, depth = layer.thickness }
        total = total + shapes.skyline(layer.heights, fields).n
        if layer.rim then
          fields.band = 1
          total = total + shapes.skyline(layer.heights, fields).n
        end
      end
      for _, c in ipairs(backdrop.clouds(7, LOOK)) do
        total = total + shapes.extrude(c.cells, { depth = 2 }).n
      end
      for _, letter in ipairs(voxel_font.layout(en["app.title"]:upper()).letters) do
        total = total + shapes.extrude(letter.cells, { depth = 2 }).n
      end
      local ground = backdrop.layers(7, LOOK)[3]
      total = total + backdrop.water(ground, LOOK).n
      local blob = shapes.blob().n + shapes.face(faces.scared).n
      total = total + #LOOK.blobs * blob
      total = total + backdrop.CUBES * shapes.cube().n
      assert.are.equal(6, #LOOK.blobs)
      assert.is_true(total < 30000, total .. " vertices")
    end
  )
end)

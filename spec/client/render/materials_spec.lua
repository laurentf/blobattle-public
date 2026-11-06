local materials = require("render.materials")
local palette = require("ui.palette")
local terrain = require("shared.sim.terrain")
local terrains = require("spec.support.terrains")

local function class_at(out, t, x, row)
  return out[(t.height - 1 - row) * t.width + x + 1]
end

describe("🎨 the materials of the map (§7.4, D-09)", function()
  it("🎨 paints grass on every face open to the sky, a band of soil, then rock", function()
    local t = terrains.flat(40)
    local out = materials.fill(t, {})
    local g = terrains.GROUND
    assert.are.equal(materials.SURFACE, class_at(out, t, 10, g))
    assert.are.equal(materials.SURFACE, class_at(out, t, 10, g + materials.SURFACE_DEPTH - 1))
    assert.are.equal(materials.SOIL, class_at(out, t, 10, g + materials.SURFACE_DEPTH))
    assert.are.equal(materials.SOIL, class_at(out, t, 10, g + materials.SOIL_DEPTH - 1))
    assert.are.equal(materials.ROCK, class_at(out, t, 10, g + materials.SOIL_DEPTH))
    assert.are.equal(materials.ROCK, class_at(out, t, 10, t.height - 1))
    assert.are.equal(materials.AIR, class_at(out, t, 10, g - 1))
    assert.are.equal(t.width * t.height, #out)
  end)

  it("🎨 grows grass again on a cave floor, and tells wood and leaves apart", function()
    local t = terrains.flat(40)
    for y = terrains.GROUND + 12, terrains.GROUND + 14 do
      for x = 5, 15 do
        terrain.set(t, x, y, terrain.AIR)
      end
    end
    for y = terrains.GROUND - 14, terrains.GROUND - 1 do
      terrain.set(t, 30, y, terrain.WOOD)
    end
    terrain.set(t, 30, terrains.GROUND - 15, terrain.LEAVES)
    terrain.set(t, 35, 10, terrain.STEEL)
    terrain.set(t, 35, 11, terrain.SOIL)
    local out = materials.fill(t, {})
    assert.are.equal(materials.STEEL, class_at(out, t, 35, 10))
    assert.are.equal(materials.SURFACE, class_at(out, t, 35, 11))
    assert.are.equal(materials.SURFACE, class_at(out, t, 10, terrains.GROUND + 15))
    assert.are.equal(materials.WOOD, class_at(out, t, 30, terrains.GROUND - 1))
    assert.are.equal(materials.LEAVES, class_at(out, t, 30, terrains.GROUND - 15))
    assert.are.equal(materials.SURFACE, class_at(out, t, 30, terrains.GROUND))
    local below = terrains.GROUND + materials.SURFACE_DEPTH
    assert.are.equal(materials.SOIL, class_at(out, t, 30, below))
  end)

  it(
    "🎨 dresses the volcano in grey ash, black basalt and dark rock under a glowing sky",
    function()
      local forest, volcano = palette.BIOMES.forest, palette.BIOMES.volcano
      assert.is_true(forest.sky[3] > forest.sky[1], "a blue forest sky")
      assert.is_true(volcano.sky[1] > 2 * volcano.sky[3], "a red volcano sky")
      local ash = volcano.surface
      assert.is_true(
        math.abs(ash[1] - ash[2]) < 0.05 and math.abs(ash[2] - ash[3]) < 0.05,
        "grey ash"
      )
      assert.is_true(volcano.soil[1] + volcano.soil[2] + volcano.soil[3] < 0.6, "black basalt")
      local function green(c)
        return c[2] > c[1] and c[2] > c[3]
      end
      local function sum(c)
        return c[1] + c[2] + c[3]
      end
      assert.is_true(green(forest.surface) and green(forest.leaves), "green grass and leaves")
      assert.is_true(
        forest.wood[1] > forest.wood[2] and forest.wood[2] > forest.wood[3],
        "brown wood"
      )
      assert.is_true(sum(volcano.rock) < sum(forest.rock) - 0.3, "dark volcanic rock")
      assert.is_true(
        sum(forest.clouds) > 2.7 and sum(volcano.clouds) < 1,
        "white clouds, dark smoke"
      )
      local steel = volcano.steel
      assert.is_true(steel[3] > steel[1], "blue-grey steel")
      assert.is_true(
        math.abs(steel[1] - volcano.sky[1]) + math.abs(steel[3] - volcano.sky[3]) > 0.5
      )
      assert.is_true(sum(steel) - sum(volcano.soil) > 0.8, "steel reads on basalt")
      assert.is_nil(forest.fog)
      assert.is_true(volcano.fog[4] > 0)
      for _, look in ipairs({ forest, volcano }) do
        for _, key in ipairs({
          "sky",
          "surface",
          "soil",
          "rock",
          "wood",
          "leaves",
          "steel",
          "clouds",
        }) do
          assert.are.equal(3, #look[key], key)
        end
      end
    end
  )

  it("🎨 gives each class its colour, in the order the shader reads them", function()
    assert.are.same({ "surface", "soil", "rock", "wood", "leaves", "steel" }, materials.CONSTANTS)
    assert.are.same({ 1, 2, 3, 4, 5, 6 }, {
      materials.SURFACE,
      materials.SOIL,
      materials.ROCK,
      materials.WOOD,
      materials.LEAVES,
      materials.STEEL,
    })
  end)

  it("🎨 picks the look of the map from its liquid", function()
    assert.are.equal(palette.BIOMES.volcano, materials.look({ kind = "lava" }))
    assert.are.equal(palette.BIOMES.forest, materials.look({ kind = "water" }))
  end)
end)

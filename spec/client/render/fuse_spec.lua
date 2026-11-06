local fuse = require("render.fuse")
local palette = require("ui.palette")

local function lcg(seed)
  local state = seed
  return function()
    state = (state * 1103515245 + 12345) % 2147483648
    return state / 2147483648
  end
end

local function burn(f, seconds, rate)
  rate = rate or 60
  local born, oldest = {}, 0
  for _ = 1, math.floor(seconds * rate + 0.5) do
    fuse.step(f, 1 / rate)
    for _, spark in ipairs(f.list) do
      if spark.age == 0 then
        born[#born + 1] = { life = spark.life, dx = spark.dx, colour = spark.colour }
      end
      oldest = math.max(oldest, spark.age)
    end
  end
  return #born, oldest, born
end

describe("🧨 the dynamite's fuse (§7.4)", function()
  it(
    "🧨 sparks fly from the tip while it burns, and each one goes out within its life",
    function()
      local f = fuse.new(lcg(3))
      local spawned, oldest = burn(f, 2)
      local expected = 2 * fuse.RATE
      assert.is_true(spawned > expected * 0.8 and spawned < expected * 1.2, spawned .. " sparks")
      assert.is_true(oldest <= fuse.LIFE, "a spark outlived its life")
      assert.is_true(fuse.LIFE < 0.5)
    end
  )

  it("🧨 they spray both ways, rise and shrink until they go out", function()
    local f = fuse.new(lcg(11))
    local _, _, seen = burn(f, 1)
    local left, right = false, false
    for _, spark in ipairs(seen) do
      local start = fuse.shape({ age = 0, life = spark.life, dx = spark.dx, colour = spark.colour })
      local mid = fuse.shape({ age = spark.life / 2, life = spark.life, dx = spark.dx })
      local late = fuse.shape({ age = spark.life * 0.95, life = spark.life, dx = spark.dx })
      assert.are.same({ 0, 0 }, { start.x, start.y })
      assert.is_true(mid.y > 0 and late.size < start.size / 4)
      left, right = left or mid.x < -0.2, right or mid.x > 0.2
    end
    assert.is_true(left and right)
  end)

  it("🧨 they are yellow and orange", function()
    local f = fuse.new(lcg(5))
    local _, _, seen = burn(f, 1)
    local used = {}
    for _, spark in ipairs(seen) do
      local rgb = palette.SPARKS[spark.colour]
      assert.is_table(rgb)
      assert.is_true(rgb[1] > 0.9 and rgb[3] < 0.4, "yellow or orange")
      used[spark.colour] = true
    end
    assert.is_true(palette.SPARKS[1][2] > 0.8, "yellow")
    assert.is_true(palette.SPARKS[2][2] > 0.4 and palette.SPARKS[2][2] < 0.7, "orange")
    assert.is_true(used[1] and used[2])
  end)

  it(
    "🧨 sparks as many per second at 30, 60 or 120 frames a second, never fewer than 4 at once",
    function()
      for _, rate in ipairs({ 30, 60, 120 }) do
        local f = fuse.new(lcg(rate))
        burn(f, 0.5, rate)
        local fewest = math.huge
        for _ = 1, rate do
          fuse.step(f, 1 / rate)
          fewest = math.min(fewest, #f.list)
        end
        local spawned = burn(fuse.new(lcg(rate + 1)), 2, rate)
        assert.is_true(
          math.abs(spawned - 2 * fuse.RATE) <= 0.2 * 2 * fuse.RATE,
          rate .. ": " .. spawned
        )
        assert.is_true(fewest >= 4, rate .. ": " .. fewest .. " at once")
      end
    end
  )

  it("🧨 gives a spark that went out to a new one, which keeps its colour", function()
    local f = fuse.new(lcg(21))
    local tables, colours = {}, {}
    local count = 0
    for _ = 1, 5 * 60 do
      fuse.step(f, 1 / 60)
      for _, spark in ipairs(f.list) do
        if tables[spark] == nil then
          tables[spark], colours[spark] = true, spark.colour
          count = count + 1
        end
        assert.are.equal(colours[spark], spark.colour)
      end
    end
    assert.is_true(count <= 16, count .. " tables for 5 s of sparks")
  end)

  it("🧨 has a dark fuse", function()
    local rgb = palette.FUSE
    assert.is_true(math.max(rgb[1], rgb[2], rgb[3]) < 0.35)
  end)
end)

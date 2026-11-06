local bubbles = require("render.bubbles")

local function lcg(seed)
  local state = seed
  return function()
    state = (state * 1103515245 + 12345) % 2147483648
    return state / 2147483648
  end
end

local function run(b, seconds, open)
  local spawned, oldest = 0, 0
  local seen = {}
  for _ = 1, seconds * 60 do
    bubbles.step(b, 1 / 60, open)
    for _, bubble in ipairs(b.list) do
      if not seen[bubble] then
        seen[bubble] = true
        spawned = spawned + 1
      end
      oldest = math.max(oldest, bubble.age)
    end
  end
  return spawned, oldest, seen
end

describe("🫧 bubbles on the lava (§7.4)", function()
  it("🫧 lava bubbles up along its open surface, and every bubble pops", function()
    local b = bubbles.new({ width = 400, level = 30, lava = true, random = lcg(7) })
    local spawned, oldest, seen = run(b, 10, function(x)
      return x < 200
    end)
    local expected = 400 * bubbles.RATE * 10 * 0.5
    assert.is_true(spawned > expected * 0.75 and spawned < expected * 1.25, spawned .. " bubbles")
    assert.is_true(oldest <= bubbles.LIFE, "a bubble outlived its life")
    for bubble in pairs(seen) do
      assert.is_true(bubble.x >= 0 and bubble.x < 200, "bubble at " .. bubble.x)
      assert.are.equal(30, bubble.level)
    end
    local _, _, again = run(b, 0.1, function()
      return true
    end)
    for bubble in pairs(again) do
      assert.is_true(bubble.age <= bubbles.LIFE)
    end
  end)

  it("🫧 a bubble swells, rises a little over the lava, then pops", function()
    local b = bubbles.new({ width = 100, level = 50, lava = true, random = lcg(3) })
    local bubble
    while bubble == nil do
      bubbles.step(b, 1 / 60, function()
        return true
      end)
      bubble = b.list[1]
    end
    local first = bubbles.shape(bubble)
    for _ = 1, 30 do
      bubbles.step(b, 1 / 60, function()
        return false
      end)
    end
    local later = bubbles.shape(bubble)
    assert.is_true(later.size > first.size and later.size <= bubbles.SIZE)
    assert.is_true(later.rise > first.rise and later.rise <= bubbles.RISE)
    for _ = 1, 120 do
      bubbles.step(b, 1 / 60, function()
        return false
      end)
    end
    assert.are.equal(0, #b.list)
  end)

  it("🫧 water stays still, and the level follows the liquid", function()
    local b = bubbles.new({ width = 400, level = 30, lava = false, random = lcg(1) })
    assert.are.equal(0, (run(b, 5, function()
      return true
    end)))
    local lava = bubbles.new({ width = 400, level = 30, lava = true, random = lcg(1) })
    bubbles.set_level(lava, 28)
    local _, _, seen = run(lava, 2, function()
      return true
    end)
    for bubble in pairs(seen) do
      assert.are.equal(28, bubble.level)
    end
  end)
end)

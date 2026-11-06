local clouds = require("render.clouds")

local function lcg(seed)
  local state = seed
  return function()
    state = (state * 1103515245 + 12345) % 2147483648
    return state / 2147483648
  end
end

local function run(c, seconds, wind)
  for _ = 1, seconds * 30 do
    clouds.step(c, 1 / 30, wind)
  end
end

describe("☁️ clouds in the sky (§7.4)", function()
  it("☁️ spreads a few clouds of puffs high above the hills", function()
    local c = clouds.new({ width = 464, height = 256, random = lcg(5) })
    local expected = math.floor(464 / clouds.EVERY + 0.5)
    assert.are.equal(expected, #c.list)
    for _, cloud in ipairs(c.list) do
      assert.is_true(cloud.x >= 0 and cloud.x < 464)
      assert.is_true(cloud.y >= 256 * (1 - clouds.LOW) and cloud.y <= 256 * (1 - clouds.HIGH))
      assert.is_true(#cloud.puffs >= clouds.PUFFS_MIN and #cloud.puffs <= clouds.PUFFS_MAX)
      for _, puff in ipairs(cloud.puffs) do
        assert.is_true(puff.size >= clouds.PUFF_MIN and puff.size <= clouds.PUFF_MAX)
        assert.is_true(math.abs(puff.dx) <= clouds.SPREAD and math.abs(puff.dy) <= 2)
      end
    end
  end)

  it("☁️ drifts with the wind, slowly without it, and comes back round the map", function()
    local c = clouds.new({ width = 400, height = 256, random = lcg(9) })
    local before = {}
    for i, cloud in ipairs(c.list) do
      before[i] = cloud.x
    end
    clouds.step(c, 1, 6)
    for i, cloud in ipairs(c.list) do
      assert.is_true(cloud.x > before[i])
      before[i] = cloud.x
    end
    clouds.step(c, 1, -6)
    for i, cloud in ipairs(c.list) do
      assert.is_true(cloud.x < before[i])
      before[i] = cloud.x
    end
    clouds.step(c, 1, 0)
    for i, cloud in ipairs(c.list) do
      assert.is_true(cloud.x > before[i])
    end
    for _, wind in ipairs({ 10, -10 }) do
      run(c, 600, wind)
      for _, cloud in ipairs(c.list) do
        assert.is_true(cloud.x >= -clouds.MARGIN and cloud.x <= 400 + clouds.MARGIN, wind)
      end
    end
  end)
end)

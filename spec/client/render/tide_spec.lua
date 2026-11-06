local tide = require("render.tide")

describe("🌋 the drawn lava follows the rising lava (§7.4)", function()
  it("🌋 climbs to the new level in about a second, never past it", function()
    local shown, target = 232, 230
    local t, highest = 0, 232
    while shown ~= target and t < 5 do
      shown = tide.step(shown, target, 1 / 60)
      t = t + 1 / 60
      highest = math.min(highest, shown)
    end
    assert.are.equal(target, shown)
    assert.is_true(math.abs(t - 2 / tide.SPEED) < 1.5 / 60 and tide.SPEED == 2, t .. " s")
    assert.are.equal(target, highest)
  end)

  it("🌋 stays still when it is where the sim says", function()
    assert.are.equal(230, tide.step(230, 230, 1 / 60))
    assert.are.equal(228, tide.step(229, 228, 10))
  end)
end)

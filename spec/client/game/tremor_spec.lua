local quake = require("shared.sim.quake")
local rules = require("shared.sim.rules")
local tremor = require("game.tremor")

local STEP = 1 / 60

local function sway(t, seconds, from)
  local most, time = 0, from or 0
  local stop = time + seconds
  while time < stop do
    time = time + STEP
    tremor.step(t, STEP, time)
    most = math.max(most, math.abs(t.x), math.abs(t.y))
  end
  return most
end

describe("📳 the camera during a quake (§7.4, D-09)", function()
  it("📳 stays still without a shake", function()
    local t = tremor.new()
    assert.are.equal(0, sway(t, 1))
    assert.are.same({ 0, 0 }, { t.x, t.y })
  end)

  it("📳 a shake moves the camera on both axes, then settles before the next shake", function()
    local t = tremor.new()
    tremor.shake(t, quake.strength(1))
    local xs, ys, time = 0, 0, 0
    while time < tremor.SECONDS - 0.05 do
      time = time + STEP
      tremor.step(t, STEP, time)
      xs, ys = math.max(xs, math.abs(t.x)), math.max(ys, math.abs(t.y))
    end
    assert.is_true(xs > 0.3 and ys > 0.3, xs .. " " .. ys)
    sway(t, 0.1, time)
    assert.are.same({ 0, 0 }, { t.x, t.y })
    assert.is_true(tremor.SECONDS <= rules.QUAKE_SHAKE_EVERY / rules.TICKS_PER_SECOND)
  end)

  it("📳 a stronger quake shakes harder", function()
    local weak, strong = tremor.new(), tremor.new()
    tremor.shake(weak, quake.strength(1))
    tremor.shake(strong, quake.strength(8))
    assert.is_true(sway(strong, 0.4) > 2 * sway(weak, 0.4))
  end)

  it("📳 calms down within its half second", function()
    local t = tremor.new()
    tremor.shake(t, quake.strength(4))
    local early = sway(t, 0.1)
    sway(t, 0.2, 0.1)
    assert.is_true(sway(t, 0.1, 0.3) < early / 2)
  end)
end)

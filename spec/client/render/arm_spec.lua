local arm = require("render.arm")

local DT = 1 / 60

local function run(a, seconds, speed)
  for _ = 1, math.floor(seconds / DT + 0.5) do
    arm.step(a, DT, speed or 0)
  end
end

local function off_line(points, count)
  local first, last = points[1], points[count]
  local dx, dy = last.x - first.x, last.y - first.y
  local length = math.sqrt(dx * dx + dy * dy)
  local worst = 0
  for i = 1, count do
    local p = points[i]
    worst = math.max(worst, math.abs((p.x - first.x) * dy - (p.y - first.y) * dx) / length)
  end
  return worst
end

describe("🐙 the tentacle's arm (§7.4)", function()
  it("🐙 draws nothing until a tentacle is thrown", function()
    local a = arm.new()
    run(a, 1)
    assert.are.equal(0, arm.points(a, { x = 0, y = 0 }, {}))
  end)

  it("🐙 stretches from the blob to the anchor, then holds it", function()
    local a = arm.new()
    arm.hooked(a, 30, 40)
    local points = {}
    run(a, 0.05)
    local count = arm.points(a, { x = 10, y = 10 }, points)
    local tip = points[count]
    assert.is_true(math.abs(tip.x - 10) < 20 and math.abs(tip.y - 10) < 30, "reached already")
    run(a, 0.3)
    count = arm.points(a, { x = 10, y = 10 }, points)
    assert.are.equal(arm.SEGMENTS + 1, count)
    assert.are.same({ 10, 10 }, { points[1].x, points[1].y })
    assert.is_true(math.abs(points[count].x - 30) < 1e-9 and math.abs(points[count].y - 40) < 1e-9)
  end)

  it("🐙 waves with its spring when it hooks, then settles straight", function()
    local a = arm.new()
    arm.hooked(a, 60, 0)
    local points = {}
    local most = 0
    for _ = 1, 30 do
      run(a, DT)
      most = math.max(most, off_line(points, arm.points(a, { x = 0, y = 0 }, points)))
    end
    assert.is_true(most > 0.3, "waved by " .. most)
    run(a, 4)
    assert.is_true(off_line(points, arm.points(a, { x = 0, y = 0 }, points)) < 0.05)
  end)

  it("🐙 waves with the swing's speed", function()
    local a = arm.new()
    arm.hooked(a, 60, 0)
    run(a, 4)
    local points = {}
    local most = 0
    for _ = 1, 30 do
      run(a, DT, 3)
      most = math.max(most, off_line(points, arm.points(a, { x = 0, y = 0 }, points)))
    end
    assert.is_true(most > 0.3, "waved by " .. most)
  end)

  it("🐙 the wave travels along the arm while it swings", function()
    local a = arm.new()
    arm.hooked(a, 60, 0)
    run(a, 2, 3)
    local before, after = {}, {}
    local count = arm.points(a, { x = 0, y = 0 }, before)
    run(a, 0.1, 3)
    arm.points(a, { x = 0, y = 0 }, after)
    local moved = 0
    for i = 1, count do
      moved = math.max(moved, math.abs(after[i].y - before[i].y))
    end
    assert.is_true(moved > 0.2, "moved by " .. moved)
  end)

  it("🐙 each throw stretches out from the blob, even right after another", function()
    local a = arm.new()
    arm.hooked(a, 60, 0)
    run(a, 1)
    arm.released(a)
    run(a, 0.05)
    arm.hooked(a, 0, 60)
    local points = {}
    local count = arm.points(a, { x = 0, y = 0 }, points)
    assert.is_true(count == 0 or points[count].y < 5)
    run(a, 1)
    arm.missed(a, 60, 60)
    count = arm.points(a, { x = 0, y = 0 }, points)
    assert.is_true(count == 0 or points[count].x < 5)
  end)

  it("🐙 a missed throw stretches out and comes back within half a second", function()
    local a = arm.new()
    arm.missed(a, 0, 120)
    local points = {}
    run(a, 0.12)
    local count = arm.points(a, { x = 0, y = 0 }, points)
    assert.is_true(points[count].y > 100)
    run(a, 0.3)
    assert.are.equal(0, arm.points(a, { x = 0, y = 0 }, points))
  end)

  it("🐙 comes back to the blob once let go", function()
    local a = arm.new()
    arm.hooked(a, 30, 40)
    run(a, 1)
    arm.released(a)
    run(a, 0.1)
    local points = {}
    assert.is_true(arm.points(a, { x = 0, y = 0 }, points) > 0)
    run(a, 0.2)
    assert.are.equal(0, arm.points(a, { x = 0, y = 0 }, points))
  end)
end)

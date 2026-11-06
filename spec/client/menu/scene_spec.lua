local scene = require("menu.scene")

local function scripted(values)
  local i = 0
  return function(lo, hi)
    i = i + 1
    local v = values[(i - 1) % #values + 1]
    return lo + (hi - lo) * v
  end
end

local function blobs()
  return {
    { x = -60 },
    { x = -30 },
    { x = -20 },
    { x = 20 },
    { x = 45 },
    { x = 70 },
  }
end

local function run(s, seconds, step)
  local events = {}
  local t = 0
  while t < seconds - 1e-9 do
    for _, e in ipairs(scene.update(s, step)) do
      e.at = t + step
      events[#events + 1] = e
    end
    t = t + step
  end
  return events
end

local function of(events, kind)
  local out = {}
  for _, e in ipairs(events) do
    if e.type == kind then
      out[#out + 1] = e
    end
  end
  return out
end

describe("💥 the menu scene (§7.2)", function()
  it("💥 fires a shell after 2 s, then one every 4 to 6 s", function()
    local s = scene.new({ blobs = blobs(), random = scripted({ 0, 1, 0.5 }) })
    local shells = of(run(s, 20, 0.05), "shell")
    assert.is_true(#shells >= 3)
    assert.is_true(math.abs(shells[1].at - scene.FIRST_SHELL) < 0.06)
    for i = 2, #shells do
      local gap = shells[i].at - shells[i - 1].at
      assert.is_true(gap >= scene.SHELL_EVERY[1] - 0.06 and gap <= scene.SHELL_EVERY[2] + 0.06, gap)
    end
  end)

  it("💥 lands each shell near a blob but never on it, after its flight", function()
    local s = scene.new({ blobs = blobs(), random = scripted({ 0.3, 0.9, 0.1, 0.6 }) })
    local events = run(s, 30, 0.05)
    local shells, booms = of(events, "shell"), of(events, "boom")
    assert.is_true(#booms >= 4)
    for i, boom in ipairs(booms) do
      assert.is_true(math.abs(boom.at - shells[i].at - scene.FLIGHT) < 0.06)
      assert.are.equal(shells[i].to, boom.x)
      local nearest = math.huge
      for _, b in ipairs(s.blobs) do
        nearest = math.min(nearest, math.abs(b.x - boom.x))
      end
      assert.is_true(nearest >= scene.MISS[1] and nearest <= scene.MISS[2], nearest)
    end
  end)

  it(
    "😨 scares the blobs near the blast, angers another one, and calms them after 2 s",
    function()
      local s = scene.new({ blobs = blobs(), random = scripted({ 0.2, 0.7, 0.4 }) })
      local boom
      while boom == nil do
        boom = of(scene.update(s, 0.05), "boom")[1]
      end
      local scared, angry = 0, 0
      for _, b in ipairs(s.blobs) do
        local near = math.abs(b.x - boom.x) <= scene.SCARE_RADIUS
        assert.are.equal(near, b.mood == "scared")
        assert.are.equal(near, b.hop == true)
        scared = scared + (b.mood == "scared" and 1 or 0)
        angry = angry + (b.mood == "angry" and 1 or 0)
      end
      assert.is_true(scared >= 1)
      assert.are.equal(1, angry)
      run(s, scene.MOOD_SECONDS + 0.1, 0.05)
      for _, b in ipairs(s.blobs) do
        assert.are.equal("calm", b.mood)
      end
    end
  )
end)

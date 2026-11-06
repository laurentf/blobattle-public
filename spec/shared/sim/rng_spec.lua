local fixed = require("shared.sim.fixed")
local rng = require("shared.sim.rng")

describe("🎲 Park–Miller generator", function()
  it("🎲 draws the published sequence from 1", function()
    local s = rng.new(1, 48271)
    assert.are.same({ 48271, 182605794, 1291394886 }, { rng.next(s), rng.next(s), rng.next(s) })
  end)

  it("🎲 keeps an exact state in [1, 2147483646]", function()
    local s = rng.new(123456789, 69621)
    for _ = 1, 20000 do
      local v = rng.next(s)
      assert.is_true(v >= 1 and v <= 2147483646)
      assert.are.equal(0, fixed.mod(v, 1))
    end
  end)

  it("🎲 draws within bounds and covers a small range", function()
    local s = rng.stream(42, "sim")
    local seen = {}
    for _ = 1, 2000 do
      local v = rng.range(s, -10, 10)
      assert.is_true(v >= -10 and v <= 10)
      seen[v] = true
    end
    for v = -10, 10 do
      assert.is_true(seen[v], "never drew " .. v)
    end
  end)

  it("🎲 refuses an empty range", function()
    assert.has_error(function()
      rng.range(rng.stream(1, "map"), 5, 3)
    end)
  end)

  it("🎲 maps each seed to its own state", function()
    local seen = {}
    for seed = 2147483640, 2147483646 do
      local state = rng.stream(seed, "sim").state
      assert.is_nil(seen[state])
      seen[state] = true
    end
    assert.are_not.equal(rng.stream(1, "sim").state, rng.stream(2147483646, "sim").state)
  end)

  it("🎲 keeps its four streams independent", function()
    local a = rng.stream(7, "map")
    local b = rng.stream(7, "sim")
    local n = rng.stream(7, "names")
    local first = rng.next(rng.stream(7, "sim"))
    local first_name = rng.next(rng.stream(7, "names"))
    for _ = 1, 50 do
      rng.next(a)
    end
    assert.are.equal(first, rng.next(b))
    assert.are.equal(first_name, rng.next(n))
    assert.are_not.equal(rng.next(rng.stream(7, "map")), rng.next(rng.stream(7, "bots")))
    assert.are_not.equal(rng.next(rng.stream(7, "bots")), rng.next(rng.stream(7, "names")))
  end)

  it("🎲 derives the names stream from g + 3000009 with the multiplier 39373 (§5.1)", function()
    local s = rng.stream(1, "names")
    assert.are.equal(3000010, s.state)
    assert.are.equal(fixed.mod(3000010 * 39373, 2147483647), rng.next(s))
    assert.are.equal(1, rng.stream(2147483646 - 3000009 + 1, "names").state)
  end)

  it("🎲 refuses a seed outside 1..2147483646, on every stream", function()
    for _, seed in ipairs({ 0, -3, 1.5, 2147483647, -999999 }) do
      assert.has_error(function()
        rng.new(seed, 48271)
      end)
      for _, name in ipairs({ "map", "sim", "bots", "names" }) do
        assert.has_error(function()
          rng.stream(seed, name)
        end)
      end
    end
    for _, name in ipairs({ "map", "sim", "bots", "names" }) do
      assert.has_no.errors(function()
        rng.stream(2147483646, name)
      end)
    end
    assert.has_error(function()
      rng.stream(1, "weather")
    end)
  end)
end)

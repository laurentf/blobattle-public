local hash = require("shared.sim.hash")

local function digest(values)
  local h = hash.new()
  for _, v in ipairs(values) do
    hash.add(h, v)
  end
  return { hash.digest(h) }
end

describe("🧮 checksum hash", function()
  it("🧮 matches a reference vector", function()
    assert.are.same({ 6498341, 1094276878 }, digest({ 1, -1, 256, -3072 }))
  end)

  it("🧮 depends on order and sign", function()
    assert.are_not.same(digest({ 1, 2 }), digest({ 2, 1 }))
    assert.are_not.same(digest({ 5 }), digest({ -5 }))
  end)

  it("🧮 accepts magnitudes up to 2^50", function()
    local a, b = unpack(digest({ 1125899906842623, -1125899906842623 }))
    assert.is_true(a >= 0 and a < 2147483647 and b >= 0 and b < 2147483647)
  end)
end)

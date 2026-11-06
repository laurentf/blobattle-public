local terrain = require("shared.sim.terrain")

local function filled(width, height)
  local t = terrain.new(width, height)
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      terrain.set(t, x, y, terrain.SOIL)
    end
  end
  return t
end

local function count_solid(t)
  local n = 0
  for i = 1, #t.cells do
    n = n + t.cells[i]
  end
  return n
end

describe("💥 terrain grid", function()
  it("💥 carves exactly the 441 cells of a radius-12 disc", function()
    local t = filled(64, 64)
    assert.are.equal(441, terrain.carve(t, 32, 32, 12))
    assert.are.equal(64 * 64 - 441, count_solid(t))
    assert.is_false(terrain.solid(t, 44, 32))
    assert.is_true(terrain.solid(t, 45, 32))
    assert.is_false(terrain.solid(t, 32, 20))
    assert.is_true(terrain.solid(t, 41, 41))
  end)

  it("💥 clips a crater at every map edge and never carves twice", function()
    local t = filled(40, 30)
    assert.are.equal(26, terrain.carve(t, 0, 0, 5))
    assert.are.equal(0, terrain.carve(t, 0, 0, 5))
    assert.are.equal(26, terrain.carve(t, 39, 29, 5))
    assert.are.equal(26, terrain.carve(t, 39, 0, 5))
    assert.are.equal(26, terrain.carve(t, 0, 29, 5))
    assert.is_true(terrain.solid(t, 0, 6))
    assert.is_true(terrain.solid(t, 39, 23))
    assert.is_true(terrain.solid(t, 34, 29 - 4))
    assert.are.equal(40 * 30 - 4 * 26, count_solid(t))
  end)

  it("💥 reads air beside and above the map, soil below it", function()
    local t = filled(10, 10)
    assert.is_false(terrain.solid(t, -1, 5))
    assert.is_false(terrain.solid(t, 10, 5))
    assert.is_false(terrain.solid(t, 5, -1))
    assert.is_true(terrain.solid(t, 5, 10))
    assert.has_error(function()
      terrain.set(t, 10, 0, terrain.SOIL)
    end)
  end)

  it("💥 logs every carve so the log hash changes with each crater", function()
    local t = filled(64, 64)
    local before = { terrain.log_digest(t) }
    terrain.carve(t, 10, 10, 3)
    local after = { terrain.log_digest(t) }
    assert.are_not.same(before, after)
    local u = filled(64, 64)
    terrain.carve(u, 10, 10, 3)
    assert.are.same(after, { terrain.log_digest(u) })
  end)

  it("💥 logs a carve even when it removes nothing", function()
    local t = terrain.new(20, 20)
    local before = { terrain.log_digest(t) }
    assert.are.equal(0, terrain.carve(t, 10, 10, 3))
    assert.are_not.same(before, { terrain.log_digest(t) })
  end)

  it("💥 round-trips through run-length encoding, materials included", function()
    local t = filled(50, 20)
    for y = 2, 8 do
      terrain.set(t, 30, y, terrain.WOOD)
      terrain.set(t, 31, y, terrain.WOOD)
      terrain.set(t, 32, y, terrain.LEAVES)
    end
    terrain.carve(t, 10, 5, 6)
    terrain.carve(t, 49, 19, 4)
    terrain.carve(t, 25, 0, 9)
    local copy = assert(terrain.decode(terrain.encode(t)))
    assert.are.same(t.cells, copy.cells)
    assert.are.same({ terrain.cells_hash(t) }, { terrain.cells_hash(copy) })
    assert.are.same({ terrain.log_digest(t) }, { terrain.log_digest(copy) })
    local other = assert(terrain.decode(terrain.encode(t)))
    terrain.set(other, 31, 4, terrain.LEAVES)
    assert.are_not.same({ terrain.cells_hash(t) }, { terrain.cells_hash(other) })
  end)

  it("💥 encodes each run as its length times eight plus its material", function()
    local t = filled(4, 1)
    local data = terrain.encode(t)
    assert.are.same({ 4, 1, 7, 11, 1, 4 * 8 + terrain.SOIL }, { 4, 1, 7, 11, data[5], data[6] })
    terrain.set(t, 0, 0, terrain.STEEL)
    terrain.set(t, 1, 0, terrain.AIR)
    terrain.set(t, 2, 0, terrain.WOOD)
    terrain.set(t, 3, 0, terrain.LEAVES)
    data = terrain.encode(t)
    assert.are.same(
      { 4, 1 * 8 + 4, 1 * 8, 1 * 8 + 2, 1 * 8 + 3 },
      { data[5], data[6], data[7], data[8], data[9] }
    )
  end)

  it("💥 tells soil, wood, leaves and steel apart, and all of them from air", function()
    assert.are.same({ 0, 1, 2, 3, 4, 5, 8 }, {
      terrain.AIR,
      terrain.SOIL,
      terrain.WOOD,
      terrain.LEAVES,
      terrain.STEEL,
      terrain.MATERIALS,
      terrain.RUN,
    })
    local t = terrain.new(4, 1)
    terrain.set(t, 1, 0, terrain.WOOD)
    terrain.set(t, 2, 0, terrain.LEAVES)
    terrain.set(t, 3, 0, terrain.STEEL)
    assert.are.same({ false, true, true, true }, {
      terrain.solid(t, 0, 0),
      terrain.solid(t, 1, 0),
      terrain.solid(t, 2, 0),
      terrain.solid(t, 3, 0),
    })
    assert.are.same(
      { terrain.WOOD, terrain.LEAVES, terrain.STEEL },
      { terrain.get(t, 1, 0), terrain.get(t, 2, 0), terrain.get(t, 3, 0) }
    )
  end)

  it("💥 refuses malformed encodings with a reason", function()
    assert.is_not_nil(terrain.decode({ 4, 1, 7, 11, 2, 1 * 8 + 4, 3 * 8 + 2 }))
    local cases = {
      { 4, 1, 7, 11, 2, 1 * 8 + 1, 2 * 8 },
      { 4, 1, 7, 11, 2, 5 * 8, -1 },
      { 4, 1, 7, 11, 2, 8.5, 24.5 },
      { 4, 1, 7, 11, 2, 1, 4 * 8 },
      { 4, 1, 7, 11, 1, 4 * 8, 9 },
      { 4, 1, 7, 11, 1, 4 * 8 + 5 },
      { 4, 1, 7, 11, 1, 4 * 8 + 7 },
      { 4, 1, 7, 11, 0 },
      { 0, 1, 7, 11 },
      { 4, 2.5, 7, 11, 1, 4 * 8 },
      { 99999, 1, 7, 11, 1, 99999 * 8 },
      { 4, 1, 7 },
    }
    for i, data in ipairs(cases) do
      local t, err = terrain.decode(data)
      assert.is_nil(t, "case " .. i)
      assert.are.equal("terrain_encoding", err, "case " .. i)
    end
  end)
end)

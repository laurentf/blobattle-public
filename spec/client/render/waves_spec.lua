local waves = require("render.waves")

local function source(path)
  local f = assert(io.open(path))
  local text = f:read("*a")
  f:close()
  return text
end

describe("🌊 the waves of the liquid (§7.4)", function()
  it("🌊 uses the liquid shader's formula", function()
    local text = source("client/render/liquid.vp")
    assert.is_truthy(text:find("0.9 * sin(wave.x * 2.0 + p.x * 0.35)", 1, true))
    assert.is_truthy(text:find("0.5 * sin(wave.x * 3.1 + p.x * 0.9 + p.z * 0.4)", 1, true))
    local t, x, z = 1.7, 13.2, 9.9
    local expected = 0.9 * math.sin(t * 2 + x * 0.35) + 0.5 * math.sin(t * 3.1 + x * 0.9 + z * 0.4)
    assert.is_true(math.abs(waves.height(t, x, z) - expected) < 1e-9)
  end)

  it("🌊 follows the mesh: exact on its vertices, straight between them", function()
    local x0 = -64
    for _, t in ipairs({ 0, 0.4, 2.3 }) do
      for k = 0, 10 do
        local x = x0 + k * waves.STEP
        assert.is_true(math.abs(waves.surface(t, x, 10.4, x0) - waves.height(t, x, 10.4)) < 1e-9)
      end
      local a, b = waves.height(t, x0, 10.4), waves.height(t, x0 + waves.STEP, 10.4)
      local mid = waves.surface(t, x0 + waves.STEP / 4, 10.4, x0)
      assert.is_true(math.abs(mid - (a * 0.75 + b * 0.25)) < 1e-9)
    end
  end)
end)

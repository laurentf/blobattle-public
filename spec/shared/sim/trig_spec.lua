local trig = require("shared.sim.trig")

local function read(path)
  local file = assert(io.open(path, "rb"))
  local content = file:read("*a")
  file:close()
  return content
end

describe("📐 trigonometry table", function()
  it("📐 hits the exact values at the quarters", function()
    assert.are.same({ 0, 16384, 0, -16384 }, {
      trig.sin(0),
      trig.sin(256),
      trig.sin(512),
      trig.sin(768),
    })
    assert.are.same({ 16384, 0, -16384, 0 }, {
      trig.cos(0),
      trig.cos(256),
      trig.cos(512),
      trig.cos(768),
    })
  end)

  it("📐 is symmetric by construction on every angle", function()
    for a = 0, 1023 do
      assert.are.equal(trig.sin(a), trig.sin(512 - a))
      assert.are.equal(-trig.sin(a), trig.sin(a + 512))
      assert.are.equal(trig.sin(a + 256), trig.cos(a))
    end
  end)

  it("📐 wraps negative and large angles", function()
    assert.are.equal(-16384, trig.sin(-256))
    assert.are.equal(trig.sin(100), trig.sin(100 + 1024 * 7))
  end)

  it("📐 stays within one unit of the real sine", function()
    for a = 0, 1023 do
      local exact = math.sin(2 * math.pi * a / 1024) * 16384
      assert.is_true(math.abs(trig.sin(a) - exact) <= 0.5, "angle " .. a)
    end
  end)

  it("📐 is exactly what tools/gen_trig.lua produces", function()
    local out = os.tmpname()
    local ok = os.execute(os.getenv("BLOBATTLE_LUA") .. " tools/gen_trig.lua " .. out)
    assert.is_true(ok == true or ok == 0)
    assert.are.equal(read("shared/sim/trig.lua"), read(out))
    os.remove(out)
  end)
end)

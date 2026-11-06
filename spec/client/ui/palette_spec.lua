local palette = require("ui.palette")
local weapons = require("shared.sim.weapons.registry")

local SHOT_KINDS = { projectile = true, placed = true, walker = true, part = true }

describe("🎨 the palette", function()
  it("🎨 colours every weapon and every part that puts a shot in the world (§7.4)", function()
    local all = {}
    for _, weapon in ipairs(weapons.list) do
      all[#all + 1] = weapon
    end
    for _, part in ipairs(weapons.parts) do
      all[#all + 1] = part
    end
    for _, weapon in ipairs(all) do
      if SHOT_KINDS[weapon.kind] then
        local rgb = palette.SHOTS[weapon.id]
        assert.is_table(rgb, weapon.id)
        assert.are.equal(3, #rgb, weapon.id)
      end
    end
  end)

  it("🍇 gives the cluster's mini-blobs five bright colours, one each (§7.4)", function()
    assert.are.equal(5, #palette.BITS)
    local seen = {}
    for _, rgb in ipairs(palette.BITS) do
      assert.are.equal(3, #rgb)
      local key = table.concat(rgb, ",")
      assert.is_nil(seen[key], key)
      seen[key] = true
      assert.is_true(math.max(rgb[1], rgb[2], rgb[3]) >= 0.8, key)
    end
  end)
end)

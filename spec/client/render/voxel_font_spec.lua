local en = require("shared.i18n.en")
local voxel_font = require("render.voxel_font")

local function key(cell)
  return cell.x .. ":" .. cell.y
end

describe("🔠 the voxel title font (§7.2)", function()
  it("🔠 has a 5 × 7 glyph for every letter of the game's title in the catalogue", function()
    local title = en["app.title"]:upper()
    assert.are.equal("BLOBATTLE", title)
    for char in title:gmatch(".") do
      local cells = assert(voxel_font.glyph(char), char)
      assert.is_true(#cells >= 7, char)
      for _, c in ipairs(cells) do
        assert.is_true(c.x >= 0 and c.x < voxel_font.WIDTH and c.y >= 0 and c.y < voxel_font.HEIGHT)
      end
    end
  end)

  it("🔠 draws every capital from A to Z, each one different", function()
    local seen = {}
    for code = string.byte("A"), string.byte("Z") do
      local char = string.char(code)
      local cells = assert(voxel_font.glyph(char), char)
      local keys = {}
      for _, c in ipairs(cells) do
        keys[#keys + 1] = key(c)
      end
      table.sort(keys)
      local shape = table.concat(keys, " ")
      assert.is_nil(seen[shape], char .. " looks like " .. tostring(seen[shape]))
      seen[shape] = char
    end
  end)

  it(
    "🔠 reads its rows top down: the bar of a T is on its top row, an L's on its bottom",
    function()
      local function row(char, y)
        local n = 0
        for _, c in ipairs(voxel_font.glyph(char)) do
          if c.y == y then
            n = n + 1
          end
        end
        return n
      end
      assert.are.equal(5, row("T", voxel_font.HEIGHT - 1))
      assert.are.equal(5, row("L", 0))
    end
  )

  it("🔠 refuses a character it cannot draw", function()
    local cells, err = voxel_font.glyph("?")
    assert.is_nil(cells)
    assert.are.equal("no_glyph", err)
  end)

  it("🔠 lays a word out left to right, one column apart, a space as wide as a letter", function()
    local line = voxel_font.layout("AB C")
    assert.are.same(
      { "A", "B", "C" },
      { line.letters[1].char, line.letters[2].char, line.letters[3].char }
    )
    assert.are.same({ 0, 6, 18 }, { line.letters[1].x, line.letters[2].x, line.letters[3].x })
    assert.are.equal(23, line.width)
  end)
end)

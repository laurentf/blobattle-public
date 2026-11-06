local en = require("shared.i18n.en")
local keymap = require("input.keymap")
local keys_view = require("ui.keys_view")
local weapons = require("shared.sim.weapons.registry")

local function row_of(rows, command)
  for _, row in ipairs(rows) do
    if row.command == command then
      return row
    end
  end
  return nil
end

describe("⌨️ the Keys screen (§7.2, §7.3)", function()
  it("⌨️ names every key that can be chosen from the catalogue", function()
    local map = keymap.read({})
    for _, k in ipairs(keymap.KEYS) do
      local label = keys_view.label(map, k.id)
      assert.is_string(label, k.id)
      assert.are.equal(en["key." .. k.id:sub(5)], label, k.id)
    end
    assert.are.equal("Space", keys_view.label(map, "key_space"))
    assert.are.equal("X", keys_view.label(map, "key_x"))
  end)

  it("⌨️ shows a punctuation key by the character it typed", function()
    local map = keymap.read({})
    keymap.assign(map, "fuse", "key_semicolon", "m")
    assert.are.equal("M", keys_view.label(map, "key_semicolon"))
    keymap.assign(map, "fuse", "key_quote")
    assert.are.equal(en["key.quote"], keys_view.label(map, "key_quote"))
  end)

  it(
    "⌨️ captions the moves from the catalogue and each cell by its weapon, in grid order",
    function()
      local rows = keys_view.rows(keymap.read({}), { portrait = false })
      assert.are.equal(#keymap.COMMANDS, #rows)
      for i, command in ipairs(keymap.COMMANDS) do
        assert.are.equal(command, rows[i].command)
      end
      for i, weapon in ipairs(weapons.list) do
        assert.are.equal(en["weapon." .. weapon.id], row_of(rows, "weapon_" .. i).caption)
      end
      for _, command in ipairs({ "left", "right", "aim_up", "aim_down", "fire", "jump", "fuse" }) do
        assert.are.equal(en["keys." .. command], row_of(rows, command).caption, command)
      end
      assert.are.equal("Space", row_of(rows, "fire").key)
    end
  )

  it(
    "⌨️ lays the commands down four columns of five in landscape, two of nine in portrait",
    function()
      local map = keymap.read({})
      local wide = keys_view.rows(map, { portrait = false })
      local tall = keys_view.rows(map, { portrait = true })
      local seen = {}
      for i, row in ipairs(wide) do
        assert.is_true(row.column >= 1 and row.column <= 4, row.command)
        assert.is_true(row.line >= 1 and row.line <= 5, row.command)
        local at = row.column * 10 + row.line
        assert.is_nil(seen[at], row.command)
        seen[at] = true
        if i > 1 then
          local before = wide[i - 1]
          assert.is_true(
            row.column > before.column or row.line == before.line + 1,
            row.command .. " follows " .. before.command
          )
        end
        assert.are.same(
          { math.floor((i - 1) / 9) + 1, (i - 1) % 9 + 1 },
          { tall[i].column, tall[i].line }
        )
      end
      for _, command in ipairs({ "left", "right", "aim_up", "aim_down", "fire" }) do
        assert.are.equal(1, row_of(wide, command).column, command)
      end
      assert.are.same({ 4, 2 }, { wide[#wide].column, wide[#wide].line })
    end
  )

  it("⌨️ asks for a key on the command that waits for one, and on no other", function()
    local rows = keys_view.rows(keymap.read({}), { portrait = false, waiting = "jump" })
    for _, row in ipairs(rows) do
      assert.are.equal(row.command == "jump", row.waiting, row.command)
    end
    assert.are.equal(en["keys.press"], row_of(rows, "jump").key)
    assert.are.equal("Space", row_of(rows, "fire").key)
  end)
end)

local keymap = require("input.keymap")
local weapons = require("shared.sim.weapons.registry")

local function read(path)
  local file = assert(io.open(path, "rb"))
  local source = file:read("*a")
  file:close()
  return source
end

local function key_triggers()
  local found, count = {}, 0
  local bindings = read("client/input/game.input_binding")
  for block in bindings:gmatch("key_trigger (%b{})") do
    local input, action = block:match('input: (KEY_[%w_]+)%s+action: "([%w_]+)"')
    assert.truthy(input, block)
    assert.is_nil(found[action], action)
    found[action] = input
    count = count + 1
  end
  return found, count
end

describe("⌨️ the keyboard bindings (§7.3)", function()
  it(
    "⌨️ binds each key of the table, and Escape, to an action of its own name, and no other key",
    function()
      local found, count = key_triggers()
      assert.are.equal(#keymap.KEYS + 1, count)
      for _, k in ipairs(keymap.KEYS) do
        assert.are.equal(k.input, found[k.id], k.id)
        assert.are.equal("key_" .. k.input:sub(5):lower(), k.id)
      end
      assert.are.equal("KEY_ESC", found[keymap.ESCAPE])
    end
  )

  it("⌨️ offers neither Tab, nor the F keys, nor the Windows keys, nor the locks", function()
    local found = key_triggers()
    for _, input in pairs(found) do
      assert.is_nil(input:find("^KEY_F%d"), input)
      assert.is_nil(input:find("LOCK"), input)
      assert.is_nil(input:find("SUPER"), input)
      assert.are_not.equal("KEY_TAB", input)
    end
  end)

  it(
    "⌨️ puts each weapon of the grid on its digit by default, in its order, 0 for the tenth",
    function()
      assert.are.equal(10, #weapons.list)
      for i = 1, 9 do
        assert.are.equal("key_" .. i, keymap.DEFAULTS["weapon_" .. i])
      end
      assert.are.equal("key_0", keymap.DEFAULTS.weapon_10)
    end
  )

  it(
    "⌨️ leaves the game and the intro reading no key by its own name but Space and Enter",
    function()
      local script = read("client/game/game.script")
      for _, command in ipairs(keymap.COMMANDS) do
        assert.is_nil(script:find('hash("' .. command .. '")', 1, true), command)
      end
      local intro = read("client/screens/intro.gui_script")
      assert.truthy(intro:find('hash("key_space")', 1, true))
      assert.truthy(intro:find('hash("key_enter")', 1, true))
    end
  )
end)

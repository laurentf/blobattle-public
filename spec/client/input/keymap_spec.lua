local keymap = require("input.keymap")
local weapons = require("shared.sim.weapons.registry")

local function defaults()
  local keys = {}
  for command, key in pairs(keymap.DEFAULTS) do
    keys[command] = key
  end
  return keys
end

local function commands_of(map)
  local found = {}
  for _, k in ipairs(keymap.KEYS) do
    local command = keymap.command(map, k.id)
    if command then
      found[command] = k.id
    end
  end
  return found
end

describe("⌨️ the keys of the commands (§7.3)", function()
  it("⌨️ plays with the keys of the spec when nothing is saved", function()
    for _, saved in ipairs({ {}, { keys = false } }) do
      local map = keymap.read(saved)
      assert.are.equal("left", keymap.command(map, "key_left"))
      assert.are.equal("right", keymap.command(map, "key_right"))
      assert.are.equal("aim_up", keymap.command(map, "key_up"))
      assert.are.equal("aim_down", keymap.command(map, "key_down"))
      assert.are.equal("fire", keymap.command(map, "key_space"))
      assert.are.equal("jump", keymap.command(map, "key_enter"))
      assert.are.equal("fuse", keymap.command(map, "key_f"))
      for i = 1, #weapons.list do
        assert.are.equal("weapon_" .. i, keymap.command(map, "key_" .. i % 10))
      end
      assert.are.equal("weapon_10", keymap.command(map, "key_0"))
    end
  end)

  it(
    "⌨️ gives each command of the screen one key, a weapon for each cell of the grid",
    function()
      assert.are.equal(7 + #weapons.list, #keymap.COMMANDS)
      local map = keymap.read({})
      local found = commands_of(map)
      for _, command in ipairs(keymap.COMMANDS) do
        assert.truthy(found[command], command)
        assert.are.equal(found[command], keymap.key(map, command))
      end
    end
  )

  it("⌨️ fires with X and no longer with Space when the save puts Fire on X", function()
    local keys = defaults()
    keys.fire = "key_x"
    local map = keymap.read({ keys = keys })
    assert.are.equal("fire", keymap.command(map, "key_x"))
    assert.is_nil(keymap.command(map, "key_space"))
    assert.are.equal("jump", keymap.command(map, "key_enter"))
  end)

  it(
    "⌨️ gives the default keys back when two commands share a key, one lacks it, or one is refused",
    function()
      local shared, lacking, escape, unknown, odd =
        defaults(), defaults(), defaults(), defaults(), defaults()
      shared.jump = "key_space"
      lacking.fuse = nil
      escape.fire = "key_esc"
      unknown.fire = "key_f5"
      odd.fire = 32
      for _, keys in ipairs({ shared, lacking, escape, unknown, odd, "key_x" }) do
        local map = keymap.read({ keys = keys })
        assert.are.same(keymap.DEFAULTS, commands_of(map))
      end
    end
  )

  it("⌨️ swaps the two keys when the chosen key belongs to another command", function()
    local map = keymap.read({})
    assert.is_true(keymap.assign(map, "fire", "key_enter"))
    assert.are.equal("fire", keymap.command(map, "key_enter"))
    assert.are.equal("jump", keymap.command(map, "key_space"))
    assert.is_true(keymap.assign(map, "left", "key_a"))
    assert.are.equal("left", keymap.command(map, "key_a"))
    assert.is_nil(keymap.command(map, "key_left"))
  end)

  it(
    "⌨️ refuses Escape and the keys that are not offered, and leaves the commands as they were",
    function()
      local map = keymap.read({})
      for _, key in ipairs({ "key_esc", "key_tab", "key_f5", "key_lsuper", "no_key" }) do
        assert.is_false(keymap.assign(map, "fire", key), key)
        assert.are.same(keymap.DEFAULTS, commands_of(map))
      end
      assert.is_false(keymap.assign(map, "dance", "key_x"))
    end
  )

  it(
    "⌨️ comes back the same from its save, characters typed by the browser included",
    function()
      local map = keymap.read({})
      keymap.assign(map, "fire", "key_x")
      keymap.assign(map, "left", "key_semicolon", "m")
      local again = keymap.read(keymap.data(map))
      assert.are.same(commands_of(map), commands_of(again))
      assert.are.equal("M", keymap.typed(again, "key_semicolon"))
    end
  )

  it("⌨️ names a punctuation key by the single visible ASCII character it types", function()
    local map = keymap.read({})
    keymap.assign(map, "left", "key_semicolon", "m")
    keymap.assign(map, "right", "key_quote", "ù")
    keymap.assign(map, "fuse", "key_slash", "!")
    assert.are.equal("M", keymap.typed(map, "key_semicolon"))
    assert.is_nil(keymap.typed(map, "key_quote"))
    assert.are.equal("!", keymap.typed(map, "key_slash"))
    local saved = keymap.data(map)
    saved.labels.key_quote = "ù"
    saved.labels.key_f5 = "X"
    local again = keymap.read(saved)
    assert.is_nil(keymap.typed(again, "key_quote"))
    assert.is_nil(keymap.typed(again, "key_f5"))
  end)

  it(
    "⌨️ names the letters, digits and other keys by the catalogue, whatever they type",
    function()
      local map = keymap.read({})
      keymap.assign(map, "weapon_1", "key_1", "&")
      keymap.assign(map, "jump", "key_lshift", "Shift")
      keymap.assign(map, "fire", "key_x", "x")
      keymap.assign(map, "left", "key_kp_add", "+")
      for _, key in ipairs({ "key_1", "key_lshift", "key_x", "key_kp_add" }) do
        assert.is_nil(keymap.typed(map, key), key)
      end
      local saved = keymap.data(map)
      saved.labels.key_1 = "&"
      assert.is_nil(keymap.typed(keymap.read(saved), "key_1"))
    end
  )

  it("⌨️ leads each action of the bindings to its key, and Escape to none", function()
    local function tag(name)
      return "#" .. name
    end
    local actions = keymap.actions(tag)
    local count = 0
    for _, name in pairs(actions) do
      count = count + 1
      assert.are.equal(name, actions[tag(name)])
    end
    assert.are.equal(#keymap.KEYS, count)
    assert.is_nil(actions[tag(keymap.ESCAPE)])
  end)

  it("⌨️ gives the default keys back when the save file cannot be read", function()
    local engine = rawget(_G, "sys")
    rawset(_G, "sys", {
      get_save_file = function(app, name)
        return app .. "/" .. name
      end,
      load = function()
        error("could not read data from file")
      end,
    })
    local ok, map = pcall(keymap.load)
    rawset(_G, "sys", engine)
    assert.is_true(ok, tostring(map))
    assert.are.same(keymap.DEFAULTS, commands_of(map))
  end)

  it("⌨️ reads the keys from the blobattle save folder", function()
    local engine = rawget(_G, "sys")
    local folder
    rawset(_G, "sys", {
      get_save_file = function(app, name)
        folder = app
        return app .. "/" .. name
      end,
      load = function()
        return {}
      end,
    })
    local ok, err = pcall(keymap.load)
    rawset(_G, "sys", engine)
    assert.is_true(ok, tostring(err))
    assert.are.equal("blobattle", folder)
  end)

  it("⌨️ puts every key back with Default", function()
    local map = keymap.read({})
    keymap.assign(map, "fire", "key_x", "x")
    keymap.assign(map, "jump", "key_a")
    keymap.reset(map)
    assert.are.same(keymap.DEFAULTS, commands_of(map))
    assert.is_nil(keymap.typed(map, "key_x"))
  end)
end)

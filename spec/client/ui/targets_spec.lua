local lfs = require("lfs")

local MIN_POINTS = 44
local MIN_TEXT = 12
local WIDTH = 844
local NOTCH = 47
local SMALL_PHONE = math.min(667 / 844, 375 / 390)

local function read(path)
  local file = assert(io.open(path, "rb"))
  local source = file:read("*a")
  file:close()
  return source
end

local function nodes_of(source)
  local nodes = {}
  for block in source:gmatch("\nnodes {(.-)\n}") do
    local id = block:match('\n  id: "([^"]+)"')
    local x, y = block:match("\n  position {%s*x: ([%-%d%.]+)%s*y: ([%-%d%.]+)")
    local w, h = block:match("\n  size {%s*x: ([%d%.]+)%s*y: ([%d%.]+)")
    local s = block:match("\n  scale {%s*x: ([%d%.]+)")
    if id then
      nodes[id] = {
        x = tonumber(x or 0),
        y = tonumber(y or 0),
        w = tonumber(w or 0) * tonumber(s or 1),
        h = tonumber(h or 0) * tonumber(s or 1),
      }
    end
  end
  return nodes
end

local function text_scales(source)
  local found = {}
  for block in source:gmatch("\nnodes {(.-)\n}") do
    if block:find("\n  type: TYPE_TEXT") then
      local id = block:match('\n  id: "([^"]+)"')
      local s = block:match("\n  scale {%s*x: ([%d%.]+)")
      found[#found + 1] = { id = id, scale = tonumber(s or 1) }
    end
  end
  return found
end

local function buttons_of(source)
  local list = source:match("local BUTTONS = (%b{})")
  local names = {}
  for name in (list or ""):gmatch('"([%w_]+)"') do
    names[#names + 1] = name
  end
  return names
end

local function scenes()
  local found = {}
  for _, dir in ipairs({ "client/screens", "client/game" }) do
    for name in lfs.dir(dir) do
      if name:match("%.gui$") then
        found[#found + 1] = dir .. "/" .. name
      end
    end
  end
  table.sort(found)
  return found
end

describe("👆 touch targets (D-10)", function()
  it("👆 every button a screen answers to is at least 44 points on a 667×375 phone", function()
    local small, checked = {}, 0
    for _, path in ipairs(scenes()) do
      local script = read(path .. "_script")
      local nodes = nodes_of(read(path))
      for _, id in ipairs(buttons_of(script)) do
        local n = nodes[id]
        assert.is_table(n, path .. " has no node " .. id)
        checked = checked + 1
        local w, h = n.w * SMALL_PHONE, n.h * SMALL_PHONE
        if w < MIN_POINTS or h < MIN_POINTS then
          small[#small + 1] = string.format("%s: %s %.1f×%.1f", path, id, w, h)
        end
      end
    end
    assert.is_true(checked >= 15, checked .. " buttons checked")
    assert.are.same({}, small)
  end)

  it("👆 no button of the landscape screens lies under a side notch", function()
    local under = {}
    for _, path in ipairs(scenes()) do
      local nodes = nodes_of(read(path))
      for _, id in ipairs(buttons_of(read(path .. "_script"))) do
        local n = nodes[id]
        if n.x - n.w / 2 < NOTCH or n.x + n.w / 2 > WIDTH - NOTCH then
          under[#under + 1] = path
            .. ": "
            .. id
            .. " spans "
            .. (n.x - n.w / 2)
            .. "–"
            .. (n.x + n.w / 2)
        end
      end
    end
    assert.are.same({}, under)
  end)

  it("🔤 no text is under 12 points at the reference scale (V0 §2)", function()
    local size = tonumber(read("client/fonts/main.font"):match("\nsize: (%d+)"))
    local small, checked = {}, 0
    for _, path in ipairs(scenes()) do
      for _, t in ipairs(text_scales(read(path))) do
        checked = checked + 1
        if t.scale * size < MIN_TEXT then
          small[#small + 1] = string.format("%s: %s %.1f pt", path, t.id, t.scale * size)
        end
      end
    end
    assert.is_true(checked >= 20, checked .. " texts checked")
    assert.are.same({}, small)
  end)

  it("👆 the check reads a node's size and scale", function()
    local source = "\nnodes {\n  size {\n    x: 40.0\n    y: 60.0\n  }\n"
      .. '  scale {\n    x: 2.0\n  }\n  id: "b"\n}\n'
    assert.are.same({ b = { x = 0, y = 0, w = 80, h = 120 } }, nodes_of(source))
  end)

  it("👆 the 8 team lines never reach a thumb pad at 844×390 (§7.4, D-10)", function()
    local nodes = nodes_of(read("client/game/hud.gui"))
    local script = read("client/game/hud.gui_script")
    local step = tonumber(script:match("local HP_STEP = (%d+)"))
    local size = tonumber(read("client/fonts/main.font"):match("\nsize: (%d+)"))
    local row, value, bot = nodes.hp_row, nodes.hp_value, nodes.hp_bot
    local top = row.y
    assert.is_number(step)
    local right = row.x + math.max(value.x, bot.x + bot.w / 2)
    local half = math.max(row.h, size * 0.55) / 2
    local touching = {}
    for _, pad in ipairs({ "left", "right", "jump", "climb_up", "climb_down" }) do
      local n = nodes[pad]
      local y = n.y
      for i = 1, 8 do
        local cy = top - (i - 1) * step
        local apart = right < n.x - n.w / 2
          or row.x - row.w / 2 > n.x + n.w / 2
          or cy + half < y - n.h / 2
          or cy - half > y + n.h / 2
        if not apart then
          touching[#touching + 1] = pad .. " / line " .. i
        end
      end
    end
    assert.are.same({}, touching)
  end)

  it("👆 no two game buttons overlap, but the fuse and the grid, never shown together", function()
    local nodes = nodes_of(read("client/game/hud.gui"))
    local buttons = buttons_of(read("client/game/hud.gui_script"))
    local apart = function(a, b)
      return math.abs(a.x - b.x) >= (a.w + b.w) / 2 or math.abs(a.y - b.y) >= (a.h + b.h) / 2
    end
    local overlapping = {}
    for i = 1, #buttons do
      for j = i + 1, #buttons do
        local a, b = buttons[i], buttons[j]
        local together = not (a == "fuse" and b:match("^grid_"))
          and not (b == "fuse" and a:match("^grid_"))
        if together and not apart(nodes[a], nodes[b]) then
          overlapping[#overlapping + 1] = a .. "/" .. b
        end
      end
    end
    assert.is_true(#buttons >= 12)
    assert.are.same({}, overlapping)
  end)

  it(
    "👆 a cross ◀ ▶ ▲ ▼ at the left thumb, a Jump button with its word beside the weapon (§7.3)",
    function()
      local source = read("client/game/hud.gui")
      local nodes = nodes_of(source)
      local anchors, parents = {}, {}
      for block in source:gmatch("\nnodes {(.-)\n}") do
        local id = block:match('\n  id: "([^"]+)"')
        if id then
          anchors[id] = block:match("\n  xanchor: (XANCHOR_%u+)")
          parents[id] = block:match('\n  parent: "([^"]+)"')
        end
      end
      local l, r, up, down = nodes.left, nodes.right, nodes.climb_up, nodes.climb_down
      local cx, cy = (l.x + r.x) / 2, l.y
      local arm = r.x - cx
      assert.are.same({ cy, cx, cx, cy + arm, cy - arm }, { r.y, up.x, down.x, up.y, down.y })
      for _, pad in ipairs({ l, r, up, down }) do
        assert.are.same({ l.w, l.h }, { pad.w, pad.h })
        assert.is_true(pad.w * SMALL_PHONE >= MIN_POINTS)
      end
      assert.is_true(arm > l.w, "the arms of the cross overlap")
      assert.is_true(down.y - down.h / 2 >= 20, "▼ lies in the bottom inset")
      for _, id in ipairs({ "left", "right", "climb_up", "climb_down" }) do
        assert.are.equal("XANCHOR_LEFT", anchors[id], id)
      end
      local jump, weapon = nodes.jump, nodes.weapon
      assert.are.same({ "XANCHOR_RIGHT", "XANCHOR_RIGHT" }, { anchors.jump, anchors.weapon })
      local between = (weapon.x - weapon.w / 2) - (jump.x + jump.w / 2)
      assert.is_true(jump.y == weapon.y and between > 0 and between <= 24, "between " .. between)
      assert.is_true(jump.w * SMALL_PHONE >= MIN_POINTS and jump.h * SMALL_PHONE >= MIN_POINTS)
      assert.is_nil(nodes.jump_arrow)
      assert.are.equal("jump", parents.jump_label)
      local script = read("client/game/hud.gui_script")
      local refit = script:match("\nlocal function refit%(self%)(.-)\nend\n")
      assert.truthy(refit, "no refit function")
      assert.truthy(refit:find('gui.set_text(self.jump_label, i18n.t("hud.jump"))', 1, true))
      assert.truthy(refit:find("self.climb_grey = nil", 1, true))
      assert.are.equal("Jump", require("shared.i18n.en")["hud.jump"])
    end
  )

  it(
    "👆 the weapon grid has ten cells, two columns of five, at the right thumb (§7.3)",
    function()
      local source = read("client/game/hud.gui")
      local nodes = nodes_of(source)
      local anchors = {}
      for block in source:gmatch("\nnodes {(.-)\n}") do
        local id = block:match('\n  id: "([^"]+)"')
        if id then
          anchors[id] = block:match("\n  xanchor: (XANCHOR_%u+)")
        end
      end
      local script = read("client/game/hud.gui_script")
      assert.are.equal("10", script:match("\nlocal GRID = (%d+)"))
      local buttons = buttons_of(script)
      for i = 1, 10 do
        local cell = nodes["grid_" .. i]
        assert.is_table(cell, "grid_" .. i)
        assert.are.equal("XANCHOR_RIGHT", anchors["grid_" .. i])
        assert.truthy(script:find('"grid_' .. i .. '"', 1, true))
        local found = false
        for _, name in ipairs(buttons) do
          found = found or name == "grid_" .. i
        end
        assert.is_true(found, "grid_" .. i .. " is not a button")
      end
      for row = 1, 5 do
        local a, b = nodes["grid_" .. row], nodes["grid_" .. row + 5]
        assert.are.same({ nodes.grid_1.x, nodes.grid_6.x, a.y }, { a.x, b.x, b.y })
      end
      assert.is_true(nodes.grid_1.x > nodes.grid_6.x)
      assert.is_nil(nodes.grid_11)
      local yanchors = {}
      for block in source:gmatch("\nnodes {(.-)\n}") do
        local id = block:match('\n  id: "([^"]+)"')
        if id then
          yanchors[id] = block:match("\n  yanchor: (YANCHOR_%u+)")
        end
      end
      for i = 1, 10 do
        assert.are.same(
          { anchors.weapon, yanchors.weapon },
          { anchors["grid_" .. i], yanchors["grid_" .. i] },
          "grid_" .. i
        )
      end
      local fit = {}
      for name in (script:match("local FIT = (%b{})") or ""):gmatch('"([%w_]+)"') do
        fit[name] = true
      end
      for _, name in ipairs(buttons) do
        assert.is_true(fit[name], name .. " is not scaled with the screen")
      end
    end
  )

  it(
    "🔤 a weapon's label, its ammunition count included, fits its button at 18 points (§7.3)",
    function()
      local source = read("client/game/hud.gui")
      local size = tonumber(read("client/fonts/main.font"):match("\nsize: (%d+)"))
      local scales = {}
      for _, t in ipairs(text_scales(source)) do
        scales[t.id] = t.scale
      end
      local nodes = nodes_of(source)
      local names = { "weapon", "action" }
      for i = 1, 10 do
        names[#names + 1] = "grid_" .. i
      end
      for _, name in ipairs(names) do
        local button, label = nodes[name], nodes[name .. "_label"]
        local scale = scales[name .. "_label"]
        assert.are.equal(18, scale * size, name)
        assert.is_true(label.w <= button.w and label.w >= 110, name .. " " .. label.w)
        assert.is_true(label.h <= button.h, name)
      end
      local sample = require("shared.i18n.en")["hud.ammo"]
      assert.are.equal("{name} x{count}", sample)
    end
  )
end)

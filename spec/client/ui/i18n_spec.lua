local en = require("shared.i18n.en")
local lfs = require("lfs")
local rules = require("shared.sim.rules")
local weapons = require("shared.sim.weapons.registry")

local function read(path)
  local file = assert(io.open(path, "rb"))
  local source = file:read("*a")
  file:close()
  return source
end

local function files(dir, pattern, into)
  into = into or {}
  for name in lfs.dir(dir) do
    if name ~= "." and name ~= ".." and name ~= "shared" and name ~= "build" then
      local path = dir .. "/" .. name
      if name:sub(1, 1) ~= "." and lfs.attributes(path, "mode") == "directory" then
        files(path, pattern, into)
      elseif name:match(pattern) then
        into[#into + 1] = path
      end
    end
  end
  table.sort(into)
  return into
end

local function ids_in(source)
  local ids = {}
  for id in source:gmatch('i18n%.t%(%s*"([^"]+)"%s*%)') do
    ids[#ids + 1] = id
  end
  for id in source:gmatch('i18n%.format%(%s*"([^"]+)"%s*,') do
    ids[#ids + 1] = id
  end
  return ids
end

local SHOWN = { "gui%.set_text", "widgets%.text", "widgets%.button" }

local function args_of(inner)
  local args, depth, start, quote = {}, 0, 1, nil
  for i = 1, #inner do
    local ch = inner:sub(i, i)
    if quote then
      if ch == quote and inner:sub(i - 1, i - 1) ~= "\\" then
        quote = nil
      end
    elseif ch == '"' or ch == "'" then
      quote = ch
    elseif ch:match("[%(%{%[]") then
      depth = depth + 1
    elseif ch:match("[%)%}%]]") then
      depth = depth - 1
    elseif ch == "," and depth == 0 then
      args[#args + 1] = inner:sub(start, i - 1)
      start = i + 1
    end
  end
  args[#args + 1] = inner:sub(start)
  return args
end

local function sentences_in(source)
  local found = {}
  for _, call in ipairs(SHOWN) do
    for inner in source:gmatch(call .. "%s*(%b())") do
      local text = (args_of(inner:sub(2, -2))[2] or "")
        :gsub("i18n%.t%s*%b()", "")
        :gsub("i18n%.format%s*%b()", "")
      for _, pattern in ipairs({ '"([^"]*)"', "'([^']*)'" }) do
        for literal in text:gmatch(pattern) do
          if literal ~= "" then
            found[#found + 1] = literal
          end
        end
      end
    end
  end
  return found
end

local function client_sources()
  local sources = files("client", "%.lua$")
  for _, path in ipairs(files("client", "%.gui_script$")) do
    sources[#sources + 1] = path
  end
  for _, path in ipairs(files("client", "%.script$")) do
    sources[#sources + 1] = path
  end
  return sources
end

describe("🔤 the English catalogue (D-11)", function()
  it("🔤 has a text for every id the client asks for", function()
    local missing = {}
    local asked = 0
    for _, path in ipairs(client_sources()) do
      for _, id in ipairs(ids_in(read(path))) do
        asked = asked + 1
        if en[id] == nil then
          missing[#missing + 1] = path .. ": " .. id
        end
      end
    end
    assert.is_true(asked > 5)
    assert.are.same({}, missing)
  end)

  it("🔤 names every weapon, and every row and choice Training shows", function()
    for _, weapon in ipairs(weapons.list) do
      assert.is_string(en["weapon." .. weapon.id])
    end
    local script = read("client/screens/training.gui_script")
    local rows = 0
    for row in script:match("local STEPPERS = (%b{})"):gmatch("(%w+) =") do
      rows = rows + 1
      assert.is_string(en["training." .. row], row)
    end
    local cycles = script:match("local CYCLES = (%b{})")
    for row, setting, prefix in
      cycles:gmatch('(%w+) = {%s*setting = "([%w_]+)",%s*prefix = "([%w_%.]+)"')
    do
      rows = rows + 1
      assert.is_string(en["training." .. row], row)
      for _, choice in ipairs(rules.SETTINGS[setting].choices) do
        assert.is_string(en[prefix .. choice], prefix .. choice)
      end
    end
    assert.are.equal(4, rows)
  end)

  it("🔤 never puts a sentence written in code on screen", function()
    local written = {}
    for _, path in ipairs(client_sources()) do
      for _, literal in ipairs(sentences_in(read(path))) do
        written[#written + 1] = path .. ": " .. literal
      end
    end
    assert.are.same({}, written)
  end)

  it("🔤 the check finds a sentence written in code, not an id or an empty text", function()
    local source = 'widgets.button("dice", { text = "Roll the dice" })'
      .. ' gui.set_text(n, "Wind " .. w) widgets.text("t", i18n.t("home.title"))'
      .. ' widgets.button("x", { text = on and "" or name, enabled = true })'
      .. " gui.set_text(gui.get_node('a'), i18n.format(\"hud.hp\", { hp = 3 }))"
    assert.are.same({ "Wind ", "Roll the dice" }, sentences_in(source))
  end)

  it("🔤 leaves every text of every scene empty, filled from the catalogue", function()
    local written = {}
    for _, path in ipairs(files("client", "%.gui$")) do
      for text in read(path):gmatch('\n%s*text: "([^"]*)"') do
        if text ~= "" then
          written[#written + 1] = path .. ": " .. text
        end
      end
    end
    assert.are.same({}, written)
  end)

  it("🔤 the check finds an id missing from the catalogue", function()
    assert.are.same(
      { "home.nowhere", "hud.x" },
      ids_in('i18n.t("home.nowhere") i18n.format("hud.x", {})')
    )
  end)
end)

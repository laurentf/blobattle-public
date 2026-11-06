local lfs = require("lfs")
local guard = require("spec.support.determinism")

local FIXTURES = "spec/support/fixtures/determinism/"

local function read(path)
  local file = assert(io.open(path, "rb"))
  local source = file:read("*a")
  file:close()
  return source
end

local function lua_files(dir, into)
  into = into or {}
  local names = {}
  for name in lfs.dir(dir) do
    if name ~= "." and name ~= ".." then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local path = dir .. "/" .. name
    local mode = lfs.attributes(path, "mode")
    if mode == "directory" then
      lua_files(path, into)
    elseif name:match("%.lua$") then
      into[#into + 1] = path
    end
  end
  return into
end

local function kinds(violations)
  local found = {}
  for _, v in ipairs(violations) do
    found[v.kind] = (found[v.kind] or 0) + 1
  end
  return found
end

local function describe_all(violations)
  local lines = {}
  for _, v in ipairs(violations) do
    lines[#lines + 1] = string.format("%s:%d %s %s", v.path, v.line, v.kind, v.detail)
  end
  return table.concat(lines, "\n")
end

describe("🧊 the determinism guard (D-02)", function()
  it("🧊 accepts forbidden words inside comments and strings", function()
    local violations = guard.check("fixture/good.lua", read(FIXTURES .. "good.lua"))
    assert.are.same({}, violations, describe_all(violations))
  end)

  local cases = {
    { "bad_pairs.lua", "global" },
    { "bad_next.lua", "global" },
    { "bad_decimal.lua", "decimal" },
    { "bad_exponent.lua", "decimal" },
    { "bad_trig.lua", "global" },
    { "bad_clock.lua", "global" },
    { "bad_tostring.lua", "global" },
    { "bad_engine.lua", "global" },
    { "bad_global_write.lua", "global" },
    { "bad_division.lua", "operator" },
    { "bad_require.lua", "require" },
    { "bad_dynamic_require.lua", "require" },
    { "bad_alias.lua", "global" },
    { "bad_inline_option.lua", "global" },
    { "bad_format.lua", "global" },
    { "bad_monkeypatch.lua", "global" },
    { "bad_require_bare.lua", "require" },
  }
  for _, case in ipairs(cases) do
    it("🧊 rejects " .. case[1], function()
      local found = kinds(guard.check("fixture/" .. case[1], read(FIXTURES .. case[1])))
      assert.is_true((found[case[2]] or 0) > 0, case[1] .. " should raise a " .. case[2])
    end)
  end

  it("🧊 lets only shared/sim/fixed.lua use / % and ^", function()
    local source = "local M = {}\nfunction M.div(a, b)\n  return math.floor(a / b)\nend\nreturn M\n"
    assert.are.same({}, guard.check(guard.ARITHMETIC_OWNER, source))
    assert.are.equal(1, #guard.check("shared/sim/other.lua", source))
  end)
end)

describe("🧊 shared/ (D-01, D-02)", function()
  it("🧊 breaks no determinism or boundary rule", function()
    local violations = {}
    for _, path in ipairs(lua_files("shared")) do
      for _, v in ipairs(guard.check(path, read(path))) do
        violations[#violations + 1] = v
      end
    end
    assert.are.same({}, violations, describe_all(violations))
  end)

  it("🧊 loads every module without touching globals and returns a table", function()
    for _, path in ipairs(lua_files("shared")) do
      local chunk = assert(loadfile(path))
      setfenv(
        chunk,
        setmetatable({}, {
          __index = _G,
          __newindex = function(_, key)
            error(path .. " writes the global " .. tostring(key))
          end,
        })
      )
      local ok, result = pcall(chunk)
      assert.is_true(ok, tostring(result))
      assert.are.equal("table", type(result), path .. " must return its module table")
    end
  end)
end)

local function foreign_requires(source)
  local found = {}
  for name in source:gmatch("require%s*%(?%s*[\"']([^\"']+)[\"']") do
    if not (name == "nakama" or name:find("^shared%.") or name:find("^server%.")) then
      found[#found + 1] = name
    end
  end
  return found
end

describe("🧊 server/ (D-01)", function()
  it("🧊 the boundary check catches a require outside shared/, server/ and nakama", function()
    assert.are.same(
      { "client.ui", "dkjson" },
      foreign_requires('local ui = require("client.ui")\nlocal j = require "dkjson"\n')
    )
  end)

  it("🧊 requires only shared/, server/ and nakama", function()
    local files = lua_files("server")
    assert.is_true(#files > 0)
    for _, path in ipairs(files) do
      assert.are.same({}, foreign_requires(read(path)), path)
    end
  end)
end)

local function client_files(dir, into)
  into = into or {}
  local names = {}
  for name in lfs.dir(dir) do
    if name ~= "." and name ~= ".." and name ~= "shared" and name ~= "build" then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local path = dir .. "/" .. name
    if name:sub(1, 1) ~= "." and lfs.attributes(path, "mode") == "directory" then
      client_files(path, into)
    elseif name:match("%.lua$") or name:match("%.script$") or name:match("%.gui_script$") then
      into[#into + 1] = path
    end
  end
  return into
end

local function crossing_requires(source)
  local found = {}
  for name in source:gmatch("require%s*%(?%s*[\"']([^\"']+)[\"']") do
    if name:find("^server%.") or name:find("^tools%.") or name:find("^spec%.") then
      found[#found + 1] = name
    end
  end
  return found
end

local function nakama_requires(source)
  local found = {}
  for name in source:gmatch("require%s*%(?%s*[\"']([^\"']+)[\"']") do
    if name:find("^nakama%.") then
      found[#found + 1] = name
    end
  end
  return found
end

local SEAM = { start = true, update = true, send = true, poll = true, team = true, stop = true }

local function beyond_seam(source)
  local found = {}
  for field in source:gsub('"[^"\n]*"', '""'):gmatch("authority%s*[%.:]%s*([%a_][%w_]*)") do
    if not SEAM[field] then
      found[#found + 1] = field
    end
  end
  return found
end

describe("🧊 client/ (D-01)", function()
  it("🧊 the boundary check catches a require of server/, tools/ or spec/", function()
    assert.are.same(
      { "server.room", "spec.support.maps" },
      crossing_requires('local r = require("server.room")\nlocal m = require "spec.support.maps"\n')
    )
  end)

  it("🧊 never requires server/, tools/ or spec/", function()
    local files = client_files("client")
    assert.is_true(#files > 3)
    for _, path in ipairs(files) do
      assert.are.same({}, crossing_requires(read(path)), path)
    end
  end)

  it("🧊 the seam check catches a read of the authority beyond its interface", function()
    assert.are.same(
      { "world" },
      beyond_seam(
        'local r = require("authority.local_authority")\n'
          .. "self.authority.start() self.world = self.authority.world c.authority.send(x)"
      )
    )
  end)

  it("🧊 the network check catches a require of nakama-defold", function()
    assert.are.same(
      { "nakama.nakama", "nakama.engine.defold" },
      nakama_requires(
        'local n = require("nakama.nakama")\n' .. 'local d = require "nakama.engine.defold"\n'
      )
    )
  end)

  it("🧊 only client/net/ knows nakama-defold (§7.1)", function()
    local found = {}
    for _, path in ipairs(client_files("client")) do
      if not path:find("^client/net/") and #nakama_requires(read(path)) > 0 then
        found[#found + 1] = path
      end
    end
    assert.are.same({}, found)
  end)

  it("🧊 knows the authority only by its interface outside client/authority/ (§7.1)", function()
    for _, path in ipairs(client_files("client")) do
      if not path:find("^client/authority/") then
        assert.are.same({}, beyond_seam(read(path)), path)
      end
    end
  end)
end)

local function or_nil_lines(source)
  local found = {}
  local n = 0
  for line in (source .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local code = line:gsub("%-%-.*$", "")
    if code:find("or%s+nil%f[^%w_]") then
      found[#found + 1] = n
    end
  end
  return found
end

describe("🧊 code that runs in Nakama (gopher-lua)", function()
  it("🧊 the check catches `a and b or nil`", function()
    assert.are.same({ 2 }, or_nil_lines("local a = 1\nlocal x = a and a.b or nil\n-- or nil\n"))
  end)

  it("🧊 never writes `or nil` (gopher-lua merges its LOADNIL across a jump)", function()
    local files = lua_files("shared", lua_files("server", lua_files("tools/conformance")))
    for _, path in ipairs(files) do
      assert.are.same({}, or_nil_lines(read(path)), path)
    end
  end)
end)

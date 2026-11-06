local luacheck = require("luacheck")

local M = {}

M.READ_GLOBALS = {
  "assert",
  "error",
  "ipairs",
  "require",
  "select",
  "tonumber",
  "type",
  "unpack",
  math = { fields = { "abs", "floor", "max", "min" } },
  string = {
    fields = {
      "byte",
      "char",
      "find",
      "gmatch",
      "gsub",
      "len",
      "lower",
      "match",
      "rep",
      "sub",
      "upper",
    },
  },
  table = { fields = { "concat", "insert", "remove", "sort" } },
}

local LIBRARIES = { math = true, string = true, table = true }

M.ARITHMETIC_OWNER = "shared/sim/fixed.lua"

local GLOBAL_CODES = {
  ["111"] = true,
  ["112"] = true,
  ["113"] = true,
  ["121"] = true,
  ["122"] = true,
  ["142"] = true,
  ["143"] = true,
}

local function strip(source)
  local out = {}
  local i, n = 1, #source
  local function blank(from, to)
    out[#out + 1] = source:sub(from, to):gsub("[^\n]", " ")
  end
  while i <= n do
    local c = source:sub(i, i)
    local long = source:match("^%-%-%[(=*)%[", i)
    if long then
      local close = "]" .. long .. "]"
      local stop = source:find(close, i, true)
      stop = stop and stop + #close - 1 or n
      blank(i, stop)
      i = stop + 1
    elseif source:sub(i, i + 1) == "--" then
      local stop = source:find("\n", i, true) or n + 1
      blank(i, stop - 1)
      i = stop
    elseif source:match("^%[=*%[", i) then
      local eq = source:match("^%[(=*)%[", i)
      local close = "]" .. eq .. "]"
      local stop = source:find(close, i, true)
      stop = stop and stop + #close - 1 or n
      out[#out + 1] = '"' .. source:sub(i + 1, stop):gsub("[^\n]", " ")
      i = stop + 1
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n do
        local d = source:sub(j, j)
        if d == "\\" then
          j = j + 2
        elseif d == c or d == "\n" then
          break
        else
          j = j + 1
        end
      end
      out[#out + 1] = '"' .. source:sub(i + 1, j):gsub("[^\n]", " ")
      i = j + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local function allowed_field(library, field)
  for _, name in ipairs(M.READ_GLOBALS[library].fields) do
    if name == field then
      return true
    end
  end
  return false
end

local function line_of(code, pos)
  local _, count = code:sub(1, pos):gsub("\n", "")
  return count + 1
end

local function scan_tokens(path, code, violations)
  local i, n = 1, #code
  local owner = path == M.ARITHMETIC_OWNER
  while i <= n do
    local num = code:match("^%d[%w%.]*", i) or code:match("^%.%d[%w%.]*", i)
    local prev = i > 1 and code:sub(i - 1, i - 1) or " "
    if num and not prev:match("[%w_]") then
      local after = code:sub(i + #num, i + #num)
      if after == "+" or after == "-" then
        if num:match("[eE]$") and not num:match("^0[xX]") then
          num = num .. after .. (code:match("^%d+", i + #num + 1) or "")
        end
      end
      local hex = num:match("^0[xX]")
      if num:find(".", 1, true) or (not hex and num:find("[eE]")) then
        violations[#violations + 1] =
          { path = path, line = line_of(code, i), kind = "decimal", detail = num }
      end
      i = i + #num
    elseif code:match("^[%a_][%w_]*", i) then
      local name = code:match("^[%a_][%w_]*", i)
      local j = i - 1
      while j > 0 and code:sub(j, j):match("%s") do
        j = j - 1
      end
      local before = code:sub(j, j)
      local member = before == "." or before == ":"
      if LIBRARIES[name] and not member then
        local field = code:match("^%s*%.%s*([%a_][%w_]*)", i + #name)
        if field == nil or not allowed_field(name, field) then
          violations[#violations + 1] =
            { path = path, line = line_of(code, i), kind = "global", detail = name .. " alias" }
        end
      elseif name == "format" and member then
        violations[#violations + 1] =
          { path = path, line = line_of(code, i), kind = "global", detail = "format" }
      end
      i = i + #name
    else
      local op = code:sub(i, i)
      local two = code:sub(i, i + 1)
      if two == ".." or two == "//" then
        i = i + 2
      elseif (op == "/" or op == "%" or op == "^") and not owner then
        violations[#violations + 1] =
          { path = path, line = line_of(code, i), kind = "operator", detail = op }
        i = i + 1
      else
        i = i + 1
      end
    end
  end
end

local function scan_requires(path, source, code, violations)
  for pos in code:gmatch("()%f[%w_]require%f[^%w_]") do
    local name = source:match("^require%s*%(?%s*[\"']([^\"']*)[\"']", pos)
    if name == nil or name:sub(1, 7) ~= "shared." then
      violations[#violations + 1] =
        { path = path, line = line_of(code, pos), kind = "require", detail = name or "dynamic" }
    end
  end
end

local function scan_globals(path, source, violations)
  local raw = luacheck.get_report(source)
  raw.inline_options = {}
  local report = luacheck.process_reports({ raw }, { std = "none", read_globals = M.READ_GLOBALS })
  for _, event in ipairs(report[1]) do
    if GLOBAL_CODES[event.code] then
      local detail = event.field and (event.name .. "." .. event.field) or event.name
      violations[#violations + 1] =
        { path = path, line = event.line, kind = "global", detail = detail }
    end
  end
end

function M.check(path, source)
  local violations = {}
  local code = strip(source)
  scan_tokens(path, code, violations)
  scan_requires(path, source, code, violations)
  scan_globals(path, source, violations)
  return violations
end

return M

local names = require("shared.names")
local protocol = require("shared.protocol")
local rng = require("shared.sim.rng")
local rules = require("shared.sim.rules")

local M = {}

local MEMBERS = rules.SETTINGS.cats_per_team.max
local DEVICE_MIN, DEVICE_MAX, DEVICE_DIGITS = 10, 128, 32
local HEX = {}
for i = 1, 16 do
  HEX[i] = ("0123456789abcdef"):sub(i, i)
end

local function path()
  return sys.get_save_file("blobattle", "profile")
end

local function stream()
  return rng.stream(math.random(1, rng.MAX_SEED), "names")
end

function M.suggest_team()
  return names.team(stream(), {}).name
end

function M.valid_members(list)
  if type(list) ~= "table" or #list ~= MEMBERS then
    return false
  end
  for i = 1, MEMBERS do
    if not protocol.valid_nickname(list[i]) then
      return false
    end
  end
  return true
end

function M.valid_device(id)
  return type(id) == "string"
    and #id >= DEVICE_MIN
    and #id <= DEVICE_MAX
    and id:find("^[%w%-]+$") ~= nil
end

function M.new_device()
  local id = html5
    and html5.run(
      "self.crypto && crypto.getRandomValues ? "
        .. "Array.from(crypto.getRandomValues(new Uint8Array(16)), "
        .. "function (b) { return (b + 256).toString(16).slice(1); }).join('') : ''"
    )
  if M.valid_device(id) then
    return id
  end
  local ok, file = pcall(io.open, "/dev/urandom", "rb")
  local bytes = ok and file and file:read(DEVICE_DIGITS / 2)
  if file then
    file:close()
  end
  if bytes and #bytes == DEVICE_DIGITS / 2 then
    return (bytes:gsub(".", function(b)
      return string.format("%02x", b:byte())
    end))
  end
  local digits = {}
  for i = 1, DEVICE_DIGITS do
    digits[i] = HEX[math.random(1, #HEX)]
  end
  return table.concat(digits)
end

function M.read(data)
  local device, repaired = data.device, false
  if not M.valid_device(device) then
    device, repaired = M.new_device(), true
  end
  local team_name, named = data.team_name, protocol.valid_nickname(data.nickname)
  if not protocol.valid_nickname(team_name) then
    team_name, repaired = M.suggest_team(), true
    local p = { team_name = team_name, fresh = true, device = device }
    if named then
      p.nickname = data.nickname
    end
    return p, repaired
  end
  if not named then
    return { team_name = team_name, fresh = true, device = device }, repaired
  end
  local p = {
    nickname = data.nickname,
    team_name = team_name,
    members = data.members,
    device = device,
  }
  if M.valid_members(p.members) then
    return p, repaired
  end
  p.members = names.members(stream())
  return p, true
end

function M.save(profile)
  sys.save(path(), {
    nickname = profile.nickname,
    team_name = profile.team_name,
    members = profile.members,
    device = profile.device,
  })
end

function M.load()
  local p, repaired = M.read(sys.load(path()))
  if repaired then
    M.save(p)
  end
  return p
end

function M.complete(profile)
  profile.members = names.members(stream())
  profile.fresh = nil
  M.save(profile)
end

return M

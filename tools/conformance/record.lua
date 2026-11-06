package.path = "./?.lua;./tools/?.lua;./spec/?.lua;" .. package.path

local driver = require("shared.bots.driver")
local runner = require("conformance.runner")
local world = require("shared.sim.world")

local name, seed, teams, per_team, ticks =
  arg[1], tonumber(arg[2]), tonumber(arg[3]), tonumber(arg[4]), tonumber(arg[5])
local dynamite_turn = tonumber(arg[7] or "")
local crates = arg[8] == "crates"
local weapons = require("shared.sim.weapons.registry")
local CRATED = { "cluster", "airstrike", "waddler", "jetpack" }
local settings = { teams = teams, cats_per_team = per_team, bot_level = arg[6] or "hard" }
local w = assert(world.new(seed, settings))
local all = {}
for team = 1, teams do
  all[team] = team
end
local d = driver.new({ seed = seed, teams = all, level = settings.bot_level })
local script = {}
local function placing(game)
  if dynamite_turn == nil or game.turn.team ~= 1 or game.teams[1].turns + 1 ~= dynamite_turn then
    return nil
  end
  if game.turn.state == "aiming" and game.turn.ticks == 18 then
    return { team = 1, kind = "fire", weapon = "dynamite", angle = 0, power = 1 }
  elseif game.turn.state == "retreat" and game.turn.ticks == 2 then
    local away = game.cats[game.turn.cat].x < game.terrain.width * 128 and 1 or -1
    return { team = 1, kind = "move", direction = away }
  elseif game.turn.state == "retreat" and game.turn.ticks == 100 then
    return { team = 1, kind = "move", direction = 0 }
  end
  return nil
end

local function nearest_crate(game, c)
  local best = nil
  for _, k in ipairs(game.crates) do
    if
      k.alive
      and not k.chute
      and (best == nil or math.abs(k.x - c.x) < math.abs(best.x - c.x))
    then
      best = k
    end
  end
  return best
end

local function enemy_of(game, team)
  for _, c in ipairs(game.cats) do
    if c.alive and c.team ~= team then
      return c
    end
  end
  return nil
end

local function crated(game, team)
  if not crates then
    return nil
  end
  for _, id in ipairs(CRATED) do
    if game.teams[team].ammo[weapons.index_of(id)] > 0 then
      return id
    end
  end
  return nil
end

local playing = {}

local function using_crate(game)
  local team, at = game.turn.team, game.turn.ticks
  local state = game.turn.state
  if state == "aiming" and at == 18 then
    local id = crated(game, team)
    local c, enemy = game.cats[game.turn.cat], enemy_of(game, team)
    if id == nil or c == nil or enemy == nil then
      return nil
    end
    playing[team] = id
    local right = enemy.x > c.x
    local input = { team = team, kind = "fire", weapon = id, angle = 0, power = 1 }
    if id == "cluster" then
      input.angle, input.power, input.fuse = right and 200 or 312, 60, 3
    elseif id == "airstrike" then
      input.target = math.max(0, math.min(game.terrain.width - 1, math.floor(enemy.x / 256)))
    end
    return input
  end
  local id = playing[team]
  if id == "waddler" and state == "flight" and at == 45 then
    return { team = team, kind = "fire", weapon = id, angle = 0, power = 1 }
  elseif id == "jetpack" and state == "aiming" and at == 19 then
    return { team = team, kind = "climb", direction = -1 }
  elseif id == "jetpack" and state == "aiming" and at == 35 then
    playing[team] = nil
    return { team = team, kind = "climb", direction = 0 }
  elseif state == "turn_end" then
    playing[team] = nil
  end
  return nil
end

local function walking(game)
  if game.turn.state ~= "aiming" then
    return nil
  end
  local team = game.turn.team
  local direction = game.turn.cat % 2 == 0 and 1 or -1
  local c = game.cats[game.turn.cat]
  local k = crates and c and nearest_crate(game, c)
  if k then
    direction = k.x > c.x and 1 or -1
  end
  if game.turn.ticks == 2 then
    return { team = team, kind = "move", direction = direction }
  elseif game.turn.ticks == 9 then
    return { team = team, kind = "jump", direction = direction }
  elseif game.turn.ticks == 16 then
    return { team = team, kind = "move", direction = 0 }
  end
  return nil
end

while w.tick < ticks and w.turn.state ~= "ended" do
  local inputs = driver.inputs(d, w)
  local step = using_crate(w) or placing(w) or walking(w)
  if step then
    inputs = inputs or {}
    table.insert(inputs, 1, step)
  end
  for _, input in ipairs(inputs or {}) do
    script[#script + 1] = { at = w.tick, input = input }
  end
  world.step(w, inputs)
end
local checks = {}
for t = 0, w.tick, 300 do
  checks[#checks + 1] = t
end
if checks[#checks] ~= w.tick then
  checks[#checks + 1] = w.tick
end
local vector = { name = name, seed = seed, settings = settings, script = script, checks = checks }
vector.expected = runner.run(vector)
vector.names = runner.names(vector)

local function field(k, v)
  if type(v) == "string" then
    return k .. ' = "' .. v .. '"'
  end
  return k .. " = " .. tostring(v)
end
local lines = { "return {" }
lines[#lines + 1] = "  " .. field("name", name) .. ","
lines[#lines + 1] = "  " .. field("seed", seed) .. ","
lines[#lines + 1] = "  settings = { "
  .. table.concat({
    field("teams", teams),
    field("cats_per_team", per_team),
    field("bot_level", settings.bot_level),
  }, ", ")
  .. " },"
lines[#lines + 1] = "  script = {"
for _, entry in ipairs(script) do
  local parts = {}
  local keys = { "team", "kind", "weapon", "angle", "power", "fuse", "target", "direction" }
  for _, key in ipairs(keys) do
    if entry.input[key] ~= nil then
      parts[#parts + 1] = field(key, entry.input[key])
    end
  end
  lines[#lines + 1] = "    { at = "
    .. entry.at
    .. ", input = { "
    .. table.concat(parts, ", ")
    .. " } },"
end
lines[#lines + 1] = "  },"
lines[#lines + 1] = "  checks = { " .. table.concat(checks, ", ") .. " },"
lines[#lines + 1] = "  expected = {"
for _, sum in ipairs(vector.expected) do
  lines[#lines + 1] = "    { tick = " .. sum.tick .. ", a = " .. sum.a .. ", b = " .. sum.b .. " },"
end
lines[#lines + 1] = "  },"
lines[#lines + 1] = "  names = {"
for _, team in ipairs(vector.names) do
  local members = {}
  for i, member in ipairs(team.members) do
    members[i] = '"' .. member .. '"'
  end
  lines[#lines + 1] = '    { name = "'
    .. team.name
    .. '", members = { '
    .. table.concat(members, ", ")
    .. " } },"
end
lines[#lines + 1] = "  },"
lines[#lines + 1] = "}"
local out = assert(io.open("spec/vectors/" .. name .. ".lua", "wb"))
out:write(table.concat(lines, "\n"), "\n")
out:close()
print(
  "🧮 " .. name .. ": " .. #script .. " inputs, " .. #checks .. " checks up to tick " .. w.tick,
  w.turn.state
)

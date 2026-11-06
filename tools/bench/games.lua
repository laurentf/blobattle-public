local driver = require("shared.bots.driver")
local rng = require("shared.sim.rng")
local rules = require("shared.sim.rules")
local turn = require("shared.sim.turn")
local world = require("shared.sim.world")

local M = {}

M.LEVELS = { "easy", "medium", "hard" }
M.MAPS = { water = "forest", lava = "volcano" }
M.MAX_TICKS = 900000

function M.new_stats()
  return {
    games = 0,
    errors = {},
    turns = 0,
    skips = 0,
    ticks = 0,
    limit = 0,
    limit_settings = {},
    draws = 0,
    maps = { forest = { games = 0, limit = 0 }, volcano = { games = 0, limit = 0 } },
    quakes = 0,
    quake_deaths = 0,
    died = { hp = 0, liquid = 0 },
    shots = { easy = 0, medium = 0, hard = 0 },
    damage = { easy = 0, medium = 0, hard = 0 },
    hits = { easy = 0, medium = 0, hard = 0 },
  }
end

function M.settings_for(index)
  local pick = rng.stream(index, "map")
  return {
    index = index,
    teams = rng.range(pick, rules.SETTINGS.teams.min, rules.SETTINGS.teams.max),
    cats_per_team = rng.range(
      pick,
      rules.SETTINGS.cats_per_team.min,
      rules.SETTINGS.cats_per_team.max
    ),
    level = M.LEVELS[rng.range(pick, 1, #M.LEVELS)],
    seed = rng.range(pick, 1, rng.MAX_SEED),
  }
end

local function run(game, stats)
  local level = game.level
  local seed = game.seed or game.index
  local w = assert(world.new(seed, {
    teams = game.teams,
    cats_per_team = game.cats_per_team,
    bot_level = level,
  }))
  local all = {}
  for team = 1, game.teams do
    all[team] = team
  end
  local d = driver.new({ seed = seed, teams = all, level = level })
  local shot_open, shot_damage = false, 0
  local function close_shot()
    if shot_open then
      stats.damage[level] = stats.damage[level] + shot_damage
      if shot_damage > 0 then
        stats.hits[level] = stats.hits[level] + 1
      end
    end
    shot_open, shot_damage = false, 0
  end
  local map = stats.maps[M.MAPS[w.liquid.kind]]
  map.games = map.games + 1
  local ticks = 0
  while w.turn.state ~= "ended" do
    ticks = ticks + 1
    if ticks > M.MAX_TICKS then
      error("the game did not end within the tick guard")
    end
    local inputs = driver.inputs(d, w)
    if inputs and inputs[1].kind == "skip" then
      stats.skips = stats.skips + 1
    end
    local quaking = w.turn.state == "quake"
    for _, e in ipairs(world.step(w, inputs)) do
      if e.type == "fired" then
        close_shot()
        shot_open = true
        stats.shots[level] = stats.shots[level] + 1
      elseif e.type == "damaged" and e.cause == "explosion" and shot_open then
        shot_damage = shot_damage + e.amount
      elseif e.type == "died" then
        stats.died[e.cause] = stats.died[e.cause] + 1
        if quaking then
          stats.quake_deaths = stats.quake_deaths + 1
        end
      elseif e.type == "quaked" then
        stats.quakes = stats.quakes + 1
      elseif e.type == "turn_ended" then
        stats.turns = stats.turns + 1
      end
    end
  end
  close_shot()
  stats.ticks = stats.ticks + ticks
  local alive = 0
  for _, team in ipairs(w.teams) do
    if turn.team_alive(w, team) then
      alive = alive + 1
    end
  end
  local at_limit = alive >= 2
  if at_limit then
    stats.limit = stats.limit + 1
    map.limit = map.limit + 1
    stats.limit_settings[#stats.limit_settings + 1] = game.teams
      .. "×"
      .. game.cats_per_team
      .. " "
      .. level
  end
  if w.result.winner == nil then
    stats.draws = stats.draws + 1
  end
end

function M.play(game, stats)
  stats.games = stats.games + 1
  local ok, err = pcall(run, game, stats)
  if not ok then
    stats.errors[#stats.errors + 1] = "game " .. game.index .. ": " .. tostring(err)
  end
end

return M

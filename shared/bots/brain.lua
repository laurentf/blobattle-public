local cat = require("shared.sim.cat")
local effects = require("shared.sim.effects")
local explosion = require("shared.sim.explosion")
local fixed = require("shared.sim.fixed")
local projectile = require("shared.sim.projectile")
local rng = require("shared.sim.rng")
local rules = require("shared.sim.rules")
local weapons = require("shared.sim.weapons.registry")

local clamp, mod = fixed.clamp, fixed.mod

local M = {}

local CAT_COPY =
  { "id", "team", "index", "x", "y", "vx", "vy", "hp", "alive", "grounded", "facing" }

function M.new(fields)
  return {
    team = fields.team,
    level = rules.BOT_LEVELS[fields.level],
    stream = rng.stream(mod(fields.seed - 1 + fields.team, rng.MAX_SEED) + 1, "bots"),
    turn_key = -1,
    searches = 0,
    work = 0,
  }
end

local function turn_key(bot, w)
  return w.teams[bot.team].turns
end

local function from_crates(id)
  for _, crated in ipairs(rules.CRATE_WEAPONS) do
    if crated == id then
      return true
    end
  end
  return false
end

local function available_weapons(w, team)
  local list = {}
  for i, weapon in ipairs(weapons.list) do
    if
      weapon.kind == "projectile"
      and w.teams[team].ammo[i] ~= 0
      and not from_crates(weapon.id)
    then
      list[#list + 1] = weapon
    end
  end
  return list
end

local function candidate_list(bot, w)
  local list = {}
  local s = bot.stream
  local usable = available_weapons(w, bot.team)
  if #usable == 0 then
    return list
  end
  for i = 1, bot.level.candidates do
    local weapon = usable[rng.range(s, 1, #usable)]
    local fuse = nil
    if weapon.fuse then
      fuse = rng.range(s, rules.BOT_FUSE_MIN, rules.BOT_FUSE_MAX)
    end
    list[i] = {
      weapon = weapon.id,
      angle = rng.range(s, rules.BOT_ANGLE_MIN, rules.BOT_ANGLE_MAX),
      power = rng.range(s, rules.BOT_POWER_MIN, rules.POWER_MAX),
      fuse = fuse,
    }
  end
  return list
end

local function new_job(w, shooter, candidate)
  local weapon = weapons.get(candidate.weapon)
  local x, y = cat.muzzle(shooter)
  local vx, vy = projectile.launch_velocity(candidate.angle, candidate.power)
  local fuse = -1
  if weapon.fuse then
    fuse = candidate.fuse * rules.TICKS_PER_SECOND
  end
  local api, record = effects.dry_run()
  return {
    candidate = candidate,
    shooter = shooter,
    stage = "flight",
    weapon = weapon,
    ticks = 0,
    record = record,
    projectile = projectile.new({
      id = 0,
      weapon = weapon.id,
      owner = shooter.id,
      x = x,
      y = y,
      vx = vx,
      vy = vy,
      fuse = fuse,
    }),
    env = {
      terrain = w.terrain,
      cats = w.cats,
      liquid = w.liquid.level,
      wind = w.wind,
      events = {},
      api = api,
    },
  }
end

local function scoring_job(shooter, landed)
  return {
    shooter = shooter,
    stage = "cats",
    landed = landed,
    index = 0,
    enemy = 0,
    own = 0,
    self_damage = 0,
    kills = 0,
    nearest = nil,
  }
end

local function tally(job, c, damage, killed)
  local shooter, landed = job.shooter, job.landed
  if c.team ~= shooter.team then
    job.enemy = job.enemy + damage
    if killed then
      job.kills = job.kills + 1
    end
    local cx, cy = cat.center(c)
    local d2 = (cx - landed.x) * (cx - landed.x) + (cy - landed.y) * (cy - landed.y)
    if job.nearest == nil or d2 < job.nearest then
      job.nearest = d2
    end
  elseif c.id == shooter.id then
    job.self_damage = job.self_damage + damage
  else
    job.own = job.own + damage
  end
end

local function next_cat(job, w)
  job.index = job.index + 1
  local c = w.cats[job.index]
  if c == nil then
    return false
  end
  if not c.alive then
    return true
  end
  local hit = explosion.effect(c, job.landed)
  if not hit then
    tally(job, c, 0, false)
    return true
  end
  local ghost = {}
  for _, key in ipairs(CAT_COPY) do
    ghost[key] = c[key]
  end
  ghost.walk, ghost.walk_clock, ghost.hurt, ghost.dig, ghost.jet = 0, 0, false, 0, 0
  ghost.hp = c.hp - hit.damage
  cat.push(ghost, hit.vx, hit.vy)
  job.cat, job.ghost, job.ghost_ticks, job.scratch = c, ghost, 0, {}
  return true
end

local function settle_ghost(job)
  local c, ghost = job.cat, job.ghost
  local total = c.hp - ghost.hp
  local drowned = not ghost.alive
  local damage = math.min(total, c.hp)
  if drowned then
    damage = c.hp
  end
  tally(job, c, damage, drowned or total >= c.hp)
  job.ghost = nil
end

local function result_of(job)
  local value = job.enemy * rules.BOT_ENEMY_WEIGHT
    + job.kills * rules.BOT_KILL_BONUS
    - job.own * rules.BOT_OWN_WEIGHT
    - job.self_damage * rules.BOT_SELF_WEIGHT
  return {
    value = value,
    enemy = job.enemy,
    harmful = job.own + job.self_damage,
    nearest = job.nearest,
  }
end

local function advance(job, w)
  if job.stage == "flight" then
    local p = job.projectile
    projectile.step(job.env, p, job.weapon)
    job.ticks = job.ticks + 1
    if p.alive and job.ticks < rules.BOT_FLIGHT_TICKS then
      return nil
    end
    local landed = job.record.blast
    if landed == nil then
      return { done = true }
    end
    job.stage, job.landed = "cats", landed
    job.index, job.enemy, job.own, job.self_damage, job.kills, job.nearest = 0, 0, 0, 0, 0, nil
    return nil
  end
  if job.ghost == nil then
    if not next_cat(job, w) then
      return { done = true, result = result_of(job) }
    end
    return nil
  end
  cat.step(job.ghost, w.terrain, w.liquid.level, job.scratch)
  job.ghost_ticks = job.ghost_ticks + 1
  local ghost = job.ghost
  if not ghost.alive or cat.at_rest(ghost) or job.ghost_ticks >= rules.BOT_KNOCKBACK_TICKS then
    settle_ghost(job)
  end
  return nil
end

function M.score(w, shooter, landed)
  local job = scoring_job(shooter, landed)
  while true do
    local outcome = advance(job, w)
    if outcome then
      return outcome.result
    end
  end
end

local function consider(bot, candidate, result)
  if result.enemy > 0 and (bot.best == nil or result.value > bot.best.value) then
    bot.best = { value = result.value, candidate = candidate }
  end
  if bot.least_bad == nil or result.value > bot.least_bad.value then
    bot.least_bad = { value = result.value, candidate = candidate }
  end
  if result.harmful == 0 and result.nearest ~= nil then
    if bot.fallback == nil or result.nearest < bot.fallback.nearest then
      bot.fallback = { nearest = result.nearest, candidate = candidate }
    end
  end
end

local function refine(bot)
  bot.refined = true
  local around = bot.best and bot.best.candidate or (bot.fallback and bot.fallback.candidate)
  if around == nil or bot.level.refine == 0 then
    return
  end
  local s = bot.stream
  local spread_angle, spread_power = rules.BOT_REFINE_ANGLE, rules.BOT_REFINE_POWER
  for _ = 1, bot.level.refine do
    bot.candidates[#bot.candidates + 1] = {
      weapon = around.weapon,
      angle = clamp(around.angle + rng.range(s, -spread_angle, spread_angle), 0, 1023),
      power = clamp(around.power + rng.range(s, -spread_power, spread_power), 1, rules.POWER_MAX),
      fuse = around.fuse,
    }
  end
end

local function work_of(job)
  if job.stage == "flight" then
    return rules.BOT_WORK.flight
  end
  if job.ghost then
    return rules.BOT_WORK.knockback
  end
  return rules.BOT_WORK.cat
end

local function search(bot, w, shooter, budget)
  while bot.work < budget do
    if bot.job == nil then
      if bot.cursor > #bot.candidates then
        if bot.refined then
          return
        end
        refine(bot)
      else
        bot.job = new_job(w, shooter, bot.candidates[bot.cursor])
      end
    else
      bot.work = bot.work + work_of(bot.job)
      local outcome = advance(bot.job, w)
      if outcome then
        if outcome.result then
          consider(bot, bot.job.candidate, outcome.result)
        end
        bot.job = nil
        bot.cursor = bot.cursor + 1
      end
    end
  end
end

local function searching(bot)
  return bot.job ~= nil or bot.cursor <= #bot.candidates or not bot.refined
end

function M.choose(bot)
  if bot.best and bot.best.value > 0 then
    return bot.best.candidate
  end
  if bot.fallback then
    return bot.fallback.candidate
  end
  if bot.least_bad then
    return bot.least_bad.candidate
  end
  return nil
end

local function decide(bot)
  local chosen = M.choose(bot)
  if chosen == nil and searching(bot) then
    chosen = bot.candidates[bot.cursor]
  end
  if chosen == nil then
    return { team = bot.team, kind = "skip" }
  end
  local s = bot.stream
  local an, pn = bot.level.angle_noise, bot.level.power_noise
  return {
    team = bot.team,
    kind = "fire",
    weapon = chosen.weapon,
    angle = mod(chosen.angle + rng.range(s, -an, an), 1024),
    power = clamp(chosen.power + rng.range(s, -pn, pn), 1, rules.POWER_MAX),
    fuse = chosen.fuse,
  }
end

local function begin_turn(bot, w)
  bot.turn_key = turn_key(bot, w)
  bot.searches = bot.searches + 1
  bot.wait = rng.range(bot.stream, rules.BOT_WAIT_MIN, rules.BOT_WAIT_MAX)
  bot.offset = w.turn.state == "aiming" and w.turn.ticks or 0
  bot.candidates = candidate_list(bot, w)
  bot.cursor = 1
  bot.job = nil
  bot.refined = false
  bot.best, bot.fallback, bot.least_bad = nil, nil, nil
  bot.decision = nil
end

function M.think(bot, w, budget)
  bot.work = 0
  local state = w.turn.state
  if w.turn.team ~= bot.team or (state ~= "turn_start" and state ~= "aiming") then
    return nil
  end
  local shooter = w.cats[w.turn.cat]
  if shooter == nil or not shooter.alive then
    return nil
  end
  if bot.turn_key ~= turn_key(bot, w) then
    begin_turn(bot, w)
  end
  if bot.decision == nil and searching(bot) then
    search(bot, w, shooter, budget)
  end
  if state ~= "aiming" then
    return nil
  end
  local aimed = w.turn.ticks - bot.offset
  local last_chance = w.turn.timer <= 1
  if aimed < bot.wait and not last_chance then
    return nil
  end
  if searching(bot) and aimed < rules.BOT_DECIDE_TICKS and not last_chance then
    return nil
  end
  if bot.decision == nil then
    bot.decision = decide(bot)
  end
  return bot.decision
end

return M

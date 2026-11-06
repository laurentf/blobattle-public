local cat = require("shared.sim.cat")
local crate = require("shared.sim.crate")
local effects = require("shared.sim.effects")
local fixed = require("shared.sim.fixed")
local hash = require("shared.sim.hash")
local mapgen = require("shared.sim.mapgen")
local projectile = require("shared.sim.projectile")
local rng = require("shared.sim.rng")
local rules = require("shared.sim.rules")
local terrain = require("shared.sim.terrain")
local trig = require("shared.sim.trig")
local turn = require("shared.sim.turn")
local weapons = require("shared.sim.weapons.registry")

local M = {}

M.SNAPSHOT_VERSION = 11

local NO_INPUTS = {}

local function choice_allowed(spec, value)
  for _, v in ipairs(spec.choices) do
    if v == value then
      return true
    end
  end
  return false
end

function M.resolve_settings(input)
  input = input or {}
  local out = {}
  for _, name in ipairs({ "teams", "cats_per_team", "wind_max" }) do
    local spec = rules.SETTINGS[name]
    local value = input[name]
    if value == nil then
      value = spec.default
    end
    if
      type(value) ~= "number"
      or fixed.mod(value, 1) ~= 0
      or value < spec.min
      or value > spec.max
    then
      return nil, "invalid_" .. name
    end
    out[name] = value
  end
  for _, name in ipairs({ "turn_seconds", "map", "bot_level" }) do
    local spec = rules.SETTINGS[name]
    local value = input[name]
    if value == nil then
      value = spec.default
    end
    if not choice_allowed(spec, value) then
      return nil, "invalid_" .. name
    end
    out[name] = value
  end
  return out
end

local function ammo_table()
  local ammo = {}
  for i, weapon in ipairs(weapons.list) do
    ammo[i] = rules.AMMO[weapon.id]
  end
  return ammo
end

local function build(fields)
  local w = {
    tick = 0,
    settings = fields.settings,
    rng = { sim = rng.stream(fields.seed, "sim") },
    terrain = fields.terrain,
    liquid = fields.liquid,
    teams = {},
    cats = {},
    projectiles = {},
    next_projectile = 1,
    crates = {},
    next_crate = 1,
    turn = { state = "turn_start", ticks = 0, team = 0, cat = 0, timer = 0 },
    wind = 0,
    rounds = 0,
    wells = {},
    cracks = {},
    result = nil,
    events = {},
  }
  for id = 1, fields.settings.teams do
    w.teams[id] = { id = id, cats = {}, next_slot = 1, turns = 0, ammo = ammo_table() }
  end
  local ordered = {}
  for _, s in ipairs(fields.spawns) do
    ordered[#ordered + 1] = s
  end
  table.sort(ordered, function(a, b)
    if a.team ~= b.team then
      return a.team < b.team
    end
    return a.index < b.index
  end)
  for id, s in ipairs(ordered) do
    w.cats[id] = cat.new({ id = id, team = s.team, index = s.index, px = s.x, py = s.y })
    local members = w.teams[s.team].cats
    members[#members + 1] = id
  end
  return w
end

local function settle_spawns(w)
  local scratch = {}
  for _ = 1, 4 do
    for _, c in ipairs(w.cats) do
      cat.step(c, w.terrain, w.liquid.level, scratch)
    end
  end
end

function M.new(seed, settings_input)
  if type(seed) ~= "number" or seed < 1 or seed > rng.MAX_SEED or fixed.mod(seed, 1) ~= 0 then
    return nil, "invalid_seed"
  end
  local settings, err = M.resolve_settings(settings_input)
  if not settings then
    return nil, err
  end
  local map = mapgen.generate(seed, settings)
  local w = build({
    seed = seed,
    settings = settings,
    terrain = map.terrain,
    liquid = map.liquid,
    spawns = map.spawns,
  })
  w.wells = map.wells
  settle_spawns(w)
  turn.begin(w, map.first_team)
  w.events = {}
  return w
end

function M.from_terrain(fields)
  local settings = assert(M.resolve_settings(fields.settings))
  local w = build({
    seed = fields.seed or 1,
    settings = settings,
    terrain = fields.terrain,
    liquid = { level = fields.liquid, kind = fields.liquid_kind or "water" },
    spawns = fields.spawns,
  })
  for i, well in ipairs(fields.wells or {}) do
    w.wells[i] = { x = well.x, width = well.width }
  end
  settle_spawns(w)
  turn.begin(w, fields.first_team or 1)
  w.events = {}
  return w
end

local function environment(w)
  local env = w.env
  if env == nil then
    env = {}
    env.spawn = function(fields)
      local p = projectile.new({
        id = w.next_projectile,
        weapon = fields.weapon,
        owner = fields.owner,
        x = fields.x,
        y = fields.y,
        vx = fields.vx,
        vy = fields.vy,
        fuse = fields.fuse,
        facing = fields.facing,
      })
      w.next_projectile = w.next_projectile + 1
      w.projectiles[#w.projectiles + 1] = p
      return p
    end
    env.api = effects.new(env)
    w.env = env
  end
  env.terrain = w.terrain
  env.cats = w.cats
  env.crates = w.crates
  env.liquid = w.liquid.level
  env.wind = w.wind
  env.events = w.events
  return env
end

local function valid_integer(value, low, high)
  return type(value) == "number" and fixed.mod(value, 1) == 0 and value >= low and value <= high
end

local function fire(w, env, input)
  if not weapons.selectable(input.weapon) then
    return false
  end
  local weapon = weapons.get(input.weapon)
  local c = turn.active_cat(w)
  if c == nil or not c.alive or c.hanging then
    return false
  end
  if
    not valid_integer(input.angle, 0, trig.ANGLES - 1)
    or not valid_integer(input.power, 1, rules.POWER_MAX)
  then
    return false
  end
  local team = w.teams[w.turn.team]
  local slot = weapons.index_of(weapon.id)
  if team.ammo[slot] == 0 then
    return false
  end
  if weapon.kind == "utility" then
    local burning = c.jet > 0
    if weapon.on_use(env.api, c, { angle = input.angle, power = input.power }) ~= true then
      return false
    end
    if burning then
      cat.cut(c, w.events)
    end
    if team.ammo[slot] > 0 then
      team.ammo[slot] = team.ammo[slot] - 1
    end
    return true
  end
  if weapon.kind == "strike" then
    if not valid_integer(input.target, 0, w.terrain.width - 1) then
      return false
    end
    if team.ammo[slot] > 0 then
      team.ammo[slot] = team.ammo[slot] - 1
    end
    w.events[#w.events + 1] = { type = "fired", cat = c.id, weapon = weapon.id }
    weapon.on_use(env.api, c, { angle = input.angle, power = input.power, target = input.target })
    turn.fired(w)
    return true
  end
  local fuse = -1
  if weapon.fuse then
    local seconds = input.fuse or weapon.fuse.default
    if not valid_integer(seconds, weapon.fuse.min, weapon.fuse.max) then
      return false
    end
    fuse = seconds * rules.TICKS_PER_SECOND
  end
  if team.ammo[slot] > 0 then
    team.ammo[slot] = team.ammo[slot] - 1
  end
  if weapon.kind == "placed" then
    local x, y = cat.feet(c)
    local ticks = weapon.timer * rules.TICKS_PER_SECOND
    env.api.spawn_projectile({
      weapon = weapon.id,
      owner = c.id,
      x = x,
      y = y,
      vx = 0,
      vy = 0,
      fuse = ticks,
    })
    w.events[#w.events + 1] = { type = "fired", cat = c.id, weapon = weapon.id }
    turn.placed(w, ticks)
    return true
  end
  if weapon.kind == "walker" then
    local x, y = cat.feet(c)
    env.api.spawn_projectile({
      weapon = weapon.id,
      owner = c.id,
      x = x,
      y = y,
      vx = 0,
      vy = 0,
      fuse = weapon.timer * rules.TICKS_PER_SECOND,
      facing = c.facing,
    })
    w.events[#w.events + 1] = { type = "fired", cat = c.id, weapon = weapon.id }
    turn.fired(w)
    return true
  end
  if weapon.kind == "melee" or weapon.kind == "digger" then
    w.events[#w.events + 1] = { type = "fired", cat = c.id, weapon = weapon.id }
    weapon.on_use(env.api, c, { angle = input.angle, power = input.power })
    turn.fired(w)
    return true
  end
  local x, y = cat.muzzle(c)
  local vx, vy = projectile.launch_velocity(input.angle, input.power)
  local p = env.api.spawn_projectile({
    weapon = weapon.id,
    owner = c.id,
    x = x,
    y = y,
    vx = vx,
    vy = vy,
    fuse = fuse,
  })
  if weapon.on_fire then
    weapon.on_fire(env.api, p)
  end
  w.events[#w.events + 1] = { type = "fired", cat = c.id, weapon = weapon.id }
  turn.fired(w)
  return true
end

local function trigger(w, env)
  local any = false
  for _, p in ipairs(w.projectiles) do
    local weapon = weapons.get(p.weapon)
    local owner = w.cats[p.owner]
    if p.alive and weapon.trigger and owner and owner.team == w.turn.team then
      projectile.trigger(env, p, weapon)
      any = true
    end
  end
  return any
end

local function apply_input(w, env, input)
  if type(input) ~= "table" then
    return false
  end
  if w.turn.state == "ended" or input.team ~= w.turn.team or not turn.accepts(w, input.kind) then
    return false
  end
  local c = turn.active_cat(w)
  if input.kind == "move" then
    if not valid_integer(input.direction, -1, 1) or c == nil then
      return false
    end
    cat.set_walk(c, input.direction)
    return true
  elseif input.kind == "jump" then
    if (input.direction ~= -1 and input.direction ~= 1) or c == nil then
      return false
    end
    return cat.jump(c, input.direction, w.events)
  elseif input.kind == "climb" then
    if not valid_integer(input.direction, -1, 1) or c == nil then
      return false
    end
    return cat.set_climb(c, input.direction)
  elseif input.kind == "fire" then
    if w.turn.state == "flight" then
      return trigger(w, env)
    end
    return fire(w, env, input)
  elseif input.kind == "skip" then
    turn.skipped(w)
    return true
  end
  return false
end

local function compact(list)
  local dead = false
  for _, item in ipairs(list) do
    if not item.alive then
      dead = true
    end
  end
  if not dead then
    return list
  end
  local kept = {}
  for _, item in ipairs(list) do
    if item.alive then
      kept[#kept + 1] = item
    end
  end
  return kept
end

function M.step(w, inputs)
  local events = w.events
  for i = #events, 1, -1 do
    events[i] = nil
  end
  if w.turn.state == "ended" then
    return w.events
  end
  local env = environment(w)
  for _, input in ipairs(inputs or NO_INPUTS) do
    apply_input(w, env, input)
  end
  turn.before_physics(w)
  crate.blow(env, w.crates)
  for _, c in ipairs(w.cats) do
    cat.step(c, w.terrain, w.liquid.level, w.events, w.cats)
  end
  local count = #w.projectiles
  for i = 1, count do
    local p = w.projectiles[i]
    projectile.step(env, p, weapons.get(p.weapon))
  end
  w.projectiles = compact(w.projectiles)
  for _, k in ipairs(w.crates) do
    crate.step(env, k)
  end
  if turn.has_turn(w) then
    crate.pick(w, turn.active_cat(w))
  end
  w.crates = compact(w.crates)
  turn.after_physics(w)
  w.tick = w.tick + 1
  return w.events
end

local function flag(value)
  if value then
    return 1
  end
  return 0
end

local CAT_FIELDS = {
  "x",
  "y",
  "vx",
  "vy",
  "hp",
  "facing",
  "walk",
  "walk_clock",
  "nudge",
  "gauge",
  "anchor_x",
  "anchor_y",
  "rope",
  "climb",
  "dig",
  "dig_angle",
  "jet",
}
local CAT_FLAGS = { "alive", "grounded", "hurt", "hanging" }
local PROJECTILE_FIELDS = { "id", "owner", "x", "y", "vx", "vy", "age", "fuse", "facing" }
local PROJECTILE_FLAGS = { "resting", "alive" }
local CRATE_FIELDS = { "id", "x", "y", "vx", "vy", "fuse" }
local CRATE_FLAGS = { "chute", "alive" }

function M.checksum(w)
  local h = hash.new()
  local add = hash.add
  add(h, w.tick)
  add(h, w.rng.sim.state)
  add(h, w.wind)
  add(h, w.liquid.level)
  add(h, w.rounds)
  add(h, #w.wells)
  for _, well in ipairs(w.wells) do
    add(h, well.x)
    add(h, well.width)
  end
  add(h, #w.cracks)
  for _, crack in ipairs(w.cracks) do
    add(h, crack.x)
    add(h, crack.width)
    add(h, crack.top)
    add(h, #crack.path)
    for _, offset in ipairs(crack.path) do
      add(h, offset)
    end
  end
  add(h, turn.CODES[w.turn.state])
  add(h, w.turn.ticks)
  add(h, w.turn.team)
  add(h, w.turn.cat or 0)
  add(h, w.turn.timer)
  for _, team in ipairs(w.teams) do
    add(h, team.turns)
    add(h, team.next_slot)
    for _, n in ipairs(team.ammo) do
      add(h, n)
    end
  end
  for _, c in ipairs(w.cats) do
    for _, key in ipairs(CAT_FIELDS) do
      add(h, c[key])
    end
    for _, key in ipairs(CAT_FLAGS) do
      add(h, flag(c[key]))
    end
  end
  for _, p in ipairs(w.projectiles) do
    add(h, weapons.index_of(p.weapon))
    for _, key in ipairs(PROJECTILE_FIELDS) do
      add(h, p[key])
    end
    for _, key in ipairs(PROJECTILE_FLAGS) do
      add(h, flag(p[key]))
    end
  end
  add(h, w.next_projectile)
  add(h, #w.crates)
  for _, k in ipairs(w.crates) do
    add(h, weapons.index_of(k.weapon))
    for _, key in ipairs(CRATE_FIELDS) do
      add(h, k[key])
    end
    for _, key in ipairs(CRATE_FLAGS) do
      add(h, flag(k[key]))
    end
  end
  add(h, w.next_crate)
  local ta, tb = terrain.log_digest(w.terrain)
  add(h, ta)
  add(h, tb)
  add(h, w.result and (w.result.winner or 0) or -1)
  return hash.digest(h)
end

local function copy_list(list)
  local out = {}
  for i, v in ipairs(list) do
    out[i] = v
  end
  return out
end

local function copy_record(record, keys)
  local out = {}
  for _, key in ipairs(keys) do
    out[key] = record[key]
  end
  return out
end

local CAT_KEYS = {
  "id",
  "team",
  "index",
  "x",
  "y",
  "vx",
  "vy",
  "hp",
  "alive",
  "grounded",
  "facing",
  "walk",
  "walk_clock",
  "nudge",
  "gauge",
  "hanging",
  "anchor_x",
  "anchor_y",
  "rope",
  "climb",
  "dig",
  "dig_angle",
  "jet",
  "hurt",
}
local PROJECTILE_KEYS = {
  "id",
  "weapon",
  "owner",
  "x",
  "y",
  "vx",
  "vy",
  "age",
  "fuse",
  "facing",
  "resting",
  "alive",
}
local CRATE_KEYS = { "id", "weapon", "x", "y", "vx", "vy", "chute", "fuse", "alive" }
local SETTINGS_KEYS = { "teams", "cats_per_team", "wind_max", "turn_seconds", "map", "bot_level" }
local WELL_KEYS = { "x", "width" }
local CRACK_KEYS = { "x", "width", "top" }

local function copy_wells(list)
  local out = {}
  for i, well in ipairs(list) do
    out[i] = copy_record(well, WELL_KEYS)
  end
  return out
end

local function copy_cracks(list)
  local out = {}
  for i, crack in ipairs(list) do
    out[i] = copy_record(crack, CRACK_KEYS)
    out[i].path = copy_list(crack.path)
  end
  return out
end

local function encoded_terrain(w, cache)
  local la, lb = terrain.log_digest(w.terrain)
  if cache and cache.a == la and cache.b == lb then
    return cache.terrain, cache.cells
  end
  local encoded = terrain.encode(w.terrain)
  local cells = { terrain.hash_encoded(encoded) }
  if cache then
    cache.a, cache.b, cache.terrain, cache.cells = la, lb, encoded, cells
  end
  return encoded, cells
end

function M.snapshot(w, cache)
  local encoded, cells = encoded_terrain(w, cache)
  local teams, cats, projectiles, crates = {}, {}, {}, {}
  for i, team in ipairs(w.teams) do
    teams[i] = {
      id = team.id,
      cats = copy_list(team.cats),
      next_slot = team.next_slot,
      turns = team.turns,
      ammo = copy_list(team.ammo),
    }
  end
  for i, c in ipairs(w.cats) do
    cats[i] = copy_record(c, CAT_KEYS)
  end
  for i, p in ipairs(w.projectiles) do
    projectiles[i] = copy_record(p, PROJECTILE_KEYS)
  end
  for i, k in ipairs(w.crates) do
    crates[i] = copy_record(k, CRATE_KEYS)
  end
  return {
    version = M.SNAPSHOT_VERSION,
    tick = w.tick,
    settings = copy_record(w.settings, SETTINGS_KEYS),
    rng_sim = w.rng.sim.state,
    wind = w.wind,
    rounds = w.rounds,
    wells = copy_wells(w.wells),
    cracks = copy_cracks(w.cracks),
    turn = copy_record(w.turn, { "state", "ticks", "team", "cat", "timer" }),
    teams = teams,
    cats = cats,
    projectiles = projectiles,
    next_projectile = w.next_projectile,
    crates = crates,
    next_crate = w.next_crate,
    liquid = { level = w.liquid.level, kind = w.liquid.kind },
    terrain = encoded,
    cells = cells,
    winner = w.result and (w.result.winner or 0) or -1,
  }
end

function M.restore(s)
  if s.version ~= M.SNAPSHOT_VERSION then
    return nil, "snapshot_version"
  end
  local t = terrain.decode(s.terrain)
  if t == nil then
    return nil, "snapshot_terrain"
  end
  local ca, cb = terrain.cells_hash(t)
  if type(s.cells) ~= "table" or s.cells[1] ~= ca or s.cells[2] ~= cb then
    return nil, "snapshot_cells"
  end
  local w = {
    tick = s.tick,
    settings = copy_record(s.settings, SETTINGS_KEYS),
    rng = { sim = { state = s.rng_sim, multiplier = rng.STREAMS.sim.multiplier } },
    terrain = t,
    liquid = { level = s.liquid.level, kind = s.liquid.kind },
    teams = {},
    cats = {},
    projectiles = {},
    next_projectile = s.next_projectile,
    crates = {},
    next_crate = s.next_crate,
    turn = copy_record(s.turn, { "state", "ticks", "team", "cat", "timer" }),
    wind = s.wind,
    rounds = s.rounds,
    wells = copy_wells(s.wells),
    cracks = copy_cracks(s.cracks),
    result = nil,
    events = {},
  }
  for i, team in ipairs(s.teams) do
    w.teams[i] = {
      id = team.id,
      cats = copy_list(team.cats),
      next_slot = team.next_slot,
      turns = team.turns,
      ammo = copy_list(team.ammo),
    }
  end
  for i, c in ipairs(s.cats) do
    w.cats[i] = copy_record(c, CAT_KEYS)
  end
  for i, p in ipairs(s.projectiles) do
    w.projectiles[i] = copy_record(p, PROJECTILE_KEYS)
  end
  for i, k in ipairs(s.crates) do
    w.crates[i] = copy_record(k, CRATE_KEYS)
  end
  if s.winner >= 0 then
    w.result = {}
    if s.winner > 0 then
      w.result.winner = s.winner
    end
  end
  return w
end

return M

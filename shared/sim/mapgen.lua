local fixed = require("shared.sim.fixed")
local rng = require("shared.sim.rng")
local rules = require("shared.sim.rules")
local terrain = require("shared.sim.terrain")

local div, mod, clamp = fixed.div, fixed.mod, fixed.clamp
local AIR, SOIL, WOOD, LEAVES, STEEL =
  terrain.AIR, terrain.SOIL, terrain.WOOD, terrain.LEAVES, terrain.STEEL

local M = {}

function M.width_for(cats_total)
  return clamp(
    rules.MAP_WIDTH_BASE + rules.MAP_WIDTH_PER_CAT * cats_total,
    rules.MAP_WIDTH_MIN,
    rules.MAP_WIDTH_MAX
  )
end

local function lattice(stream, count)
  local values = {}
  for i = 1, count do
    values[i] = rng.range(stream, 0, rules.NOISE_MAX)
  end
  return values
end

local function smooth(a, b, t, span)
  local cube = span * span * span
  return a + div((b - a) * (t * t * (3 * span - 2 * t)), cube)
end

local function noise_1d(stream, width)
  local total = {}
  for x = 1, width do
    total[x] = 0
  end
  local weight_sum = 0
  for _, octave in ipairs(rules.SURFACE_OCTAVES) do
    local span, weight = octave.span, octave.weight
    local points = lattice(stream, div(width, span) + 2)
    for x = 0, width - 1 do
      local cell = div(x, span)
      local v = smooth(points[cell + 1], points[cell + 2], x - cell * span, span)
      total[x + 1] = total[x + 1] + v * weight
    end
    weight_sum = weight_sum + weight
  end
  for x = 1, width do
    total[x] = div(total[x], weight_sum)
  end
  return total
end

local function surface(stream, width, height, liquid)
  local top = div(height * rules.SURFACE_TOP_PERCENT, 100)
  local bottom = div(height * rules.SURFACE_BOTTOM_PERCENT, 100)
  local noise = noise_1d(stream, width)
  local ys = {}
  for x = 1, width do
    ys[x] = top + div((bottom - top) * noise[x], rules.NOISE_MAX)
  end
  local shore, pool = rules.SHORE_WIDTH, rules.SHORE_POOL
  local sea_floor = liquid + rules.SHORE_DROP
  local slope = shore - pool
  local left_anchor, right_anchor = ys[shore + 1], ys[width - shore]
  for i = 0, shore - 1 do
    local left, right = sea_floor, sea_floor
    if i >= pool then
      left = sea_floor - div((sea_floor - left_anchor) * (i - pool), slope)
      right = sea_floor - div((sea_floor - right_anchor) * (i - pool), slope)
    end
    ys[i + 1] = math.max(ys[i + 1], left)
    ys[width - i] = math.max(ys[width - i], right)
  end
  return ys
end

local function fill(t, ys)
  local cells, width = t.cells, t.width
  for x = 0, width - 1 do
    for y = ys[x + 1], t.height - 1 do
      cells[y * width + x + 1] = SOIL
    end
  end
end

local function near_well(wells, x0, x1, margin)
  for _, well in ipairs(wells) do
    if x1 >= well.x - margin and x0 <= well.x + well.width - 1 + margin then
      return true
    end
  end
  return false
end

local function carve_ellipse(t, cx, cy, rx, ry)
  local cells, width = t.cells, t.width
  local limit = rx * rx * ry * ry
  for y = math.max(cy - ry, 0), math.min(cy + ry, t.height - 1) do
    local dy = y - cy
    for x = math.max(cx - rx, 0), math.min(cx + rx, width - 1) do
      local dx = x - cx
      if dx * dx * ry * ry + dy * dy * rx * rx <= limit then
        cells[y * width + x + 1] = AIR
      end
    end
  end
end

local function overhangs(stream, t, ys, wells)
  local list = {}
  local width = t.width
  local x = rules.SHORE_WIDTH + rng.range(stream, rules.OVERHANG_GAP_MIN, rules.OVERHANG_GAP_MAX)
  while x < width - rules.SHORE_WIDTH do
    local rx = rng.range(stream, rules.OVERHANG_REACH_MIN, rules.OVERHANG_REACH_MAX)
    local ry = rng.range(stream, rules.OVERHANG_HEIGHT_MIN, rules.OVERHANG_HEIGHT_MAX)
    local cy = ys[x + 1] + rules.OVERHANG_LIP + ry
    local side = 0
    local clear = not near_well(wells, x - rx - 1, x + rx + 1, rules.OVERHANG_WELL_DISTANCE)
    for _, dir in ipairs({ 1, -1 }) do
      local reach, back = x + dir * (rx - 1), x - dir * (rx + 1)
      if
        clear
        and side == 0
        and reach >= 0
        and reach < width
        and back >= 0
        and back < width
        and ys[reach + 1] > cy - ry
        and ys[back + 1] < ys[x + 1] + rules.OVERHANG_LIP
      then
        side = dir
      end
    end
    if side ~= 0 then
      carve_ellipse(t, x, cy, rx, ry)
      list[#list + 1] = { x = x, y = cy, reach = rx, height = ry, side = side }
      x = x + rx
    end
    x = x + rng.range(stream, rules.OVERHANG_GAP_MIN, rules.OVERHANG_GAP_MAX)
  end
  return list
end

local function caves(stream, t, ys, liquid, threshold)
  local width, height, cells = t.width, t.height, t.cells
  local grids, weight_sum = {}, 0
  for i, octave in ipairs(rules.CAVE_OCTAVES) do
    local columns = div(width, octave.span) + 2
    local rows = div(height, octave.span) + 2
    grids[i] = {
      span = octave.span,
      weight = octave.weight,
      columns = columns,
      values = lattice(stream, columns * rows),
    }
    weight_sum = weight_sum + octave.weight
  end
  local floor_y = liquid - rules.CAVE_ABOVE_LIQUID
  local row_of, top_of, low_of = {}, {}, {}
  for x = 0, width - 1 do
    for i = 1, #grids do
      row_of[i] = -1
    end
    for y = ys[x + 1] + rules.CAVE_BELOW_SURFACE, floor_y do
      local total = 0
      for i = 1, #grids do
        local g = grids[i]
        local span = g.span
        local cy = div(y, span)
        if cy ~= row_of[i] then
          local cx = div(x, span)
          local tx = x - cx * span
          local base = cy * g.columns + cx + 1
          local values = g.values
          row_of[i] = cy
          top_of[i] = smooth(values[base], values[base + 1], tx, span)
          low_of[i] = smooth(values[base + g.columns], values[base + g.columns + 1], tx, span)
        end
        total = total + smooth(top_of[i], low_of[i], y - cy * span, span) * g.weight
      end
      if div(total, weight_sum) < threshold then
        cells[y * width + x + 1] = AIR
      end
    end
  end
end

local function place_wells(stream, width, count)
  local wells = {}
  local low = div(width * rules.WELL_ZONE_START_PERCENT, 100)
  local high = div(width * rules.WELL_ZONE_END_PERCENT, 100)
  local tries = 0
  while #wells < count and tries < rules.WELL_TRIES do
    tries = tries + 1
    local w = rng.range(stream, rules.WELL_MIN_WIDTH, rules.WELL_MAX_WIDTH)
    local x = rng.range(stream, low, high - w)
    local fits = true
    for _, other in ipairs(wells) do
      if fixed.abs((x + div(w, 2)) - (other.x + div(other.width, 2))) < rules.WELL_SPACING then
        fits = false
      end
    end
    if fits then
      wells[#wells + 1] = { x = x, width = w }
    end
  end
  table.sort(wells, function(a, b)
    return a.x < b.x
  end)
  return wells
end

local function dig_wells(t, wells, liquid)
  local cells, width = t.cells, t.width
  for _, well in ipairs(wells) do
    for x = well.x, well.x + well.width - 1 do
      for y = 0, math.min(liquid + rules.WELL_BELOW_LIQUID, t.height - 1) do
        cells[y * width + x + 1] = AIR
      end
    end
  end
end

local function flood(t, label, start, members)
  local width, total, cells = t.width, t.width * t.height, t.cells
  local stack = { start }
  local top, size = 1, 0
  label[start] = true
  while top > 0 do
    local i = stack[top]
    top = top - 1
    size = size + 1
    if members then
      members[#members + 1] = i
    end
    local x = mod(i - 1, width)
    local up, down = i - width, i + width
    if up >= 1 and cells[up] ~= AIR and not label[up] then
      label[up] = true
      top = top + 1
      stack[top] = up
    end
    if down <= total and cells[down] ~= AIR and not label[down] then
      label[down] = true
      top = top + 1
      stack[top] = down
    end
    if x > 0 and cells[i - 1] ~= AIR and not label[i - 1] then
      label[i - 1] = true
      top = top + 1
      stack[top] = i - 1
    end
    if x < width - 1 and cells[i + 1] ~= AIR and not label[i + 1] then
      label[i + 1] = true
      top = top + 1
      stack[top] = i + 1
    end
  end
  return size
end

function M.remove_islands(t)
  local width, cells = t.width, t.cells
  local total = width * t.height
  local label = {}
  for i = 1, total do
    label[i] = false
  end
  local bottom = total - width
  for x = 1, width do
    if cells[bottom + x] ~= AIR and not label[bottom + x] then
      flood(t, label, bottom + x, nil)
    end
  end
  local removed = 0
  for i = 1, total do
    if cells[i] ~= AIR and not label[i] then
      local members = {}
      local size = flood(t, label, i, members)
      if size < rules.ISLAND_MIN_CELLS then
        for _, m in ipairs(members) do
          cells[m] = AIR
        end
        removed = removed + size
      end
    end
  end
  return removed
end

local function sky_line(t)
  local sky = {}
  local cells, width, height = t.cells, t.width, t.height
  for x = 1, width do
    local y, i = 0, x
    while y < height and cells[i] == AIR do
      y, i = y + 1, i + width
    end
    sky[x] = y
  end
  return sky
end

local function highest_ground(sky, px)
  local left = px - div(rules.CAT_WIDTH, 2)
  local top = sky[left + 1]
  for x = left + 1, left + rules.CAT_WIDTH - 1 do
    top = math.min(top, sky[x + 1])
  end
  return top
end

local function on_soil(t, px, py)
  local left = px - div(rules.CAT_WIDTH, 2)
  for x = left, left + rules.CAT_WIDTH - 1 do
    local under = terrain.get(t, x, py + 1)
    if under == WOOD or under == LEAVES then
      return false
    end
  end
  return true
end

local function set_air(t, x, y, value)
  if x >= 0 and x < t.width and y >= 0 and y < t.height and terrain.get(t, x, y) == AIR then
    terrain.set(t, x, y, value)
  end
end

local function grow(t, x, ground, height, radius)
  for tx = x, x + rules.TRUNK_WIDTH - 1 do
    for y = ground - height, ground - 1 do
      set_air(t, tx, y, WOOD)
    end
  end
  local crown = ground - height - radius + rules.CROWN_OVERLAP
  for y = crown - radius, crown + radius do
    for cx = x - radius, x + 1 + radius do
      local dx, dy = 2 * cx - (2 * x + 1), 2 * (y - crown)
      if dx * dx + dy * dy <= 4 * radius * radius then
        set_air(t, cx, y, LEAVES)
      end
    end
  end
  return crown
end

local function plant(stream, t, wells, liquid)
  local trees = {}
  local sky = sky_line(t)
  local x = rules.SHORE_WIDTH + rng.range(stream, 0, rules.TREE_GAP_MIN)
  while x < t.width - rules.SHORE_WIDTH - rules.TRUNK_WIDTH do
    local height = rng.range(stream, rules.TRUNK_MIN, rules.TRUNK_MAX)
    local radius = rng.range(stream, rules.CROWN_MIN, rules.CROWN_MAX)
    local ground = sky[x + 1]
    local fits = sky[x + 2] == ground
      and sky[x] >= ground
      and sky[x + 3] >= ground
      and ground <= liquid - rules.SPAWN_ABOVE_LIQUID
      and ground - height - 2 * radius >= 0
      and not near_well(wells, x - radius, x + 1 + radius, rules.DECOR_WELL_MARGIN)
    if fits then
      local crown = grow(t, x, ground, height, radius)
      trees[#trees + 1] =
        { x = x, ground = ground, height = height, radius = radius, crown = crown }
      x = x + rng.range(stream, rules.TREE_GAP_MIN, rules.TREE_GAP_MAX)
    else
      x = x + 1
    end
  end
  return trees
end

local function hang(stream, t, wells, liquid)
  local list = {}
  local sky = sky_line(t)
  local x = rules.SHORE_POOL + rng.range(stream, rules.STALACTITE_GAP_MIN, rules.STALACTITE_GAP_MAX)
  while x < t.width - rules.SHORE_POOL do
    local half = rules.STALACTITE_HALF
    if not near_well(wells, x - half, x + half, rules.DECOR_WELL_MARGIN) then
      local y = sky[x + 1]
      while y + 1 < liquid do
        if terrain.solid(t, x, y) and not terrain.solid(t, x, y + 1) then
          local room = 0
          while y + 1 + room < liquid and not terrain.solid(t, x, y + 1 + room) do
            room = room + 1
          end
          local length = rng.range(stream, rules.STALACTITE_MIN, rules.STALACTITE_MAX)
          if room >= length + rules.STALACTITE_ROOM then
            for k = 1, length do
              local wide = div((half + 1) * (length - k), length)
              for sx = x - wide, x + wide do
                set_air(t, sx, y + k, SOIL)
              end
            end
            list[#list + 1] = { x = x, top = y + 1, length = length }
            y = y + length
          end
        end
        y = y + 1
      end
    end
    x = x + rng.range(stream, rules.STALACTITE_GAP_MIN, rules.STALACTITE_GAP_MAX)
  end
  return list
end

local function lay(stream, t, wells)
  local girders = {}
  local sky = sky_line(t)
  local limit = t.width - rules.SHORE_WIDTH
  local x = rules.SHORE_WIDTH + rng.range(stream, 0, rules.GIRDER_GAP_MIN)
  while x < limit do
    local length = rng.range(stream, rules.GIRDER_MIN, rules.GIRDER_MAX)
    local above = rng.range(stream, rules.GIRDER_ABOVE_MIN, rules.GIRDER_ABOVE_MAX)
    local placed = false
    while not placed and x + length <= limit do
      local last = x + length - 1
      local ground = sky[x + 1]
      for gx = x + 1, last do
        ground = math.min(ground, sky[gx + 1])
      end
      local top = ground - above - rules.GIRDER_THICKNESS
      if top >= 0 and not near_well(wells, x, last, rules.GIRDER_WELL_DISTANCE) then
        for gy = top, top + rules.GIRDER_THICKNESS - 1 do
          for gx = x, last do
            set_air(t, gx, gy, STEEL)
          end
        end
        girders[#girders + 1] = { x = x, y = top, length = length }
        placed = true
      else
        x = x + 1
      end
    end
    x = x + length + rng.range(stream, rules.GIRDER_GAP_MIN, rules.GIRDER_GAP_MAX)
  end
  return girders
end

local function spawn_candidates(t, sky, wells, liquid)
  local list = {}
  local margin = rules.SPAWN_EDGE_DISTANCE
  for x = margin, t.width - 1 - margin do
    local by_well = false
    for _, well in ipairs(wells) do
      if
        x > well.x - rules.SPAWN_WELL_DISTANCE
        and x < well.x + well.width + rules.SPAWN_WELL_DISTANCE
      then
        by_well = true
      end
    end
    local y = highest_ground(sky, x) - 1
    if
      not by_well
      and y >= rules.CAT_HEIGHT
      and y <= liquid - rules.SPAWN_ABOVE_LIQUID
      and on_soil(t, x, y)
    then
      list[#list + 1] = { x = x, y = y }
    end
  end
  return list
end

local function shuffle(stream, list)
  for i = #list, 2, -1 do
    local j = rng.range(stream, 1, i)
    list[i], list[j] = list[j], list[i]
  end
end

local function pick(candidates, needed, d2)
  local chosen = {}
  for _, c in ipairs(candidates) do
    local ok = true
    for _, other in ipairs(chosen) do
      local dx, dy = c.x - other.x, c.y - other.y
      if dx * dx + dy * dy < d2 then
        ok = false
        break
      end
    end
    if ok then
      chosen[#chosen + 1] = c
      if #chosen == needed then
        return chosen
      end
    end
  end
  return nil
end

local function pick_spawns(candidates, needed)
  local by_x = {}
  for i, c in ipairs(candidates) do
    by_x[i] = c
  end
  table.sort(by_x, function(a, b)
    return a.x < b.x
  end)
  local distance = rules.SPAWN_DISTANCE
  while distance >= rules.SPAWN_DISTANCE_MIN do
    local d2 = distance * distance
    local chosen = pick(candidates, needed, d2) or pick(by_x, needed, d2)
    if chosen then
      return chosen, distance
    end
    distance = distance - rules.SPAWN_RELAX
  end
  return nil
end

local function assign_teams(stream, chosen, teams, per_team)
  table.sort(chosen, function(a, b)
    if a.x ~= b.x then
      return a.x < b.x
    end
    return a.y < b.y
  end)
  local first = rng.range(stream, 1, teams)
  local next_index = {}
  for team = 1, teams do
    next_index[team] = 0
  end
  local spawns = {}
  for i, c in ipairs(chosen) do
    local team = mod(first - 1 + i - 1, teams) + 1
    next_index[team] = next_index[team] + 1
    spawns[i] = { team = team, index = next_index[team], x = c.x, y = c.y }
  end
  assert(#spawns == teams * per_team)
  return spawns
end

function M.generate(seed, settings)
  local teams, per_team = settings.teams, settings.cats_per_team
  local width = M.width_for(teams * per_team)
  local height = rules.MAP_HEIGHT
  local liquid = height - rules.LIQUID_DEPTH
  local stream = rng.stream(seed, "map")
  local biome = settings.map
  if biome == "random" then
    biome = rng.range(stream, 1, 2) == 1 and "forest" or "volcano"
  end
  local volcano = biome == "volcano"
  local kind = volcano and "lava" or "water"
  for _ = 1, rules.MAP_ATTEMPTS do
    local t = terrain.new(width, height)
    local ys = surface(stream, width, height, liquid)
    fill(t, ys)
    local wanted = 1 + div(width, rules.WELL_EVERY)
    local wells = place_wells(stream, width, wanted)
    local lips = overhangs(stream, t, ys, wells)
    caves(stream, t, ys, liquid, volcano and rules.CAVE_THRESHOLD_VOLCANO or rules.CAVE_THRESHOLD)
    dig_wells(t, wells, liquid)
    M.remove_islands(t)
    local trees, stalactites = {}, {}
    local girders = {}
    if volcano then
      stalactites = hang(stream, t, wells, liquid)
      girders = lay(stream, t, wells)
    else
      trees = plant(stream, t, wells, liquid)
    end
    local sky = sky_line(t)
    local candidates = spawn_candidates(t, sky, wells, liquid)
    shuffle(stream, candidates)
    local chosen, distance = pick_spawns(candidates, teams * per_team)
    if chosen and #wells == wanted then
      local spawns = assign_teams(stream, chosen, teams, per_team)

      return {
        first_team = rng.range(stream, 1, teams),
        biome = biome,
        terrain = t,
        surface = ys,
        liquid = { level = liquid, kind = kind },
        wells = wells,
        overhangs = lips,
        trees = trees,
        stalactites = stalactites,
        girders = girders,
        spawns = spawns,
        spawn_distance = distance,
      }
    end
  end
  error("no valid map within the allowed attempts")
end

return M

local mapgen = require("shared.sim.mapgen")
local maps = require("spec.support.maps")
local rules = require("shared.sim.rules")
local terrain = require("shared.sim.terrain")

local function check(map, settings)
  local t = map.terrain
  local total = settings.teams * settings.cats_per_team
  local width = mapgen.width_for(total)
  local problems = {}
  local function problem(text)
    problems[#problems + 1] = text
  end
  if t.width ~= width or t.height ~= rules.MAP_HEIGHT then
    problem("size " .. t.width .. "x" .. t.height)
  end
  local liquid = map.liquid.level
  if liquid ~= rules.MAP_HEIGHT - rules.LIQUID_DEPTH then
    problem("liquid level " .. liquid)
  end
  if settings.map ~= "random" and map.biome ~= settings.map then
    problem("biome " .. tostring(map.biome))
  end
  if map.liquid.kind ~= maps.LIQUID[map.biome] then
    problem("liquid kind " .. tostring(map.liquid.kind) .. " in the " .. tostring(map.biome))
  end
  for x = 0, rules.SHORE_POOL - 1 do
    for y = liquid, liquid + rules.SHORE_DROP - 1 do
      if terrain.solid(t, x, y) or terrain.solid(t, width - 1 - x, y) then
        problem("no pool at column " .. x)
      end
    end
  end
  local expected_wells = 1 + math.floor(width / rules.WELL_EVERY)
  if #map.wells ~= expected_wells then
    problem(#map.wells .. " wells instead of " .. expected_wells)
  end
  for i, well in ipairs(map.wells) do
    if well.width < rules.WELL_MIN_WIDTH or well.width > rules.WELL_MAX_WIDTH then
      problem("well width " .. well.width)
    end
    for x = well.x, well.x + well.width - 1 do
      for y = 0, liquid + 1 do
        if terrain.solid(t, x, y) then
          problem("well " .. i .. " blocked at " .. x .. "," .. y)
        end
      end
    end
    local other = map.wells[i + 1]
    if
      other
      and other.x + math.floor(other.width / 2) - well.x - math.floor(well.width / 2)
        < rules.WELL_SPACING
    then
      problem("wells too close")
    end
  end
  if #map.spawns ~= total then
    problem(#map.spawns .. " spawns instead of " .. total)
  end
  local top = math.floor(rules.MAP_HEIGHT * rules.SURFACE_TOP_PERCENT / 100)
  local bottom = math.floor(rules.MAP_HEIGHT * rules.SURFACE_BOTTOM_PERCENT / 100)
  for x = 0, width - 1 do
    for y = 0, top - 1 do
      if terrain.get(t, x, y) == terrain.SOIL then
        problem("soil above the surface band at " .. x .. "," .. y)
      end
    end
  end
  local zone_low = math.floor(width * rules.WELL_ZONE_START_PERCENT / 100)
  local zone_high = math.floor(width * rules.WELL_ZONE_END_PERCENT / 100)
  local in_well = {}
  for _, well in ipairs(map.wells) do
    if well.x < zone_low or well.x + well.width > zone_high then
      problem("well outside the central zone at " .. well.x)
    end
    for x = well.x, well.x + well.width - 1 do
      in_well[x] = true
    end
  end
  for x = rules.SHORE_WIDTH, width - 1 - rules.SHORE_WIDTH do
    if not in_well[x] then
      local surface = map.surface[x + 1]
      if surface > bottom or surface < top then
        problem("surface below the band at column " .. x)
      end
      for y = surface, math.min(surface + rules.CAVE_BELOW_SURFACE - 1, liquid - 1) do
        if not terrain.solid(t, x, y) and not maps.in_overhang(map, x, y, 2) then
          problem("cave too close to the surface at " .. x .. "," .. y)
        end
      end
      for y = liquid - rules.CAVE_ABOVE_LIQUID + 1, rules.MAP_HEIGHT - 1 do
        if not terrain.solid(t, x, y) then
          problem("hole under the cave band at " .. x .. "," .. y)
        end
      end
    end
  end
  if map.liquid.kind ~= "water" and map.liquid.kind ~= "lava" then
    problem("liquid kind " .. tostring(map.liquid.kind))
  end
  if map.spawn_distance < rules.SPAWN_DISTANCE_MIN or map.spawn_distance > rules.SPAWN_DISTANCE then
    problem("spawn distance " .. tostring(map.spawn_distance))
  end
  local per_team = {}
  for i, s in ipairs(map.spawns) do
    per_team[s.team] = (per_team[s.team] or 0) + 1
    if not maps.box_free(t, s.x, s.y) or not maps.supported(t, s.x, s.y) then
      problem("spawn " .. i .. " is not standing in the open")
    end
    if not maps.open_sky(t, s.x, s.y) then
      problem("spawn " .. i .. " has soil above it at " .. s.x .. "," .. s.y)
    end
    local left = s.x - math.floor(rules.CAT_WIDTH / 2)
    for x = left, left + rules.CAT_WIDTH - 1 do
      local under = terrain.get(t, x, s.y + 1)
      if under == terrain.WOOD or under == terrain.LEAVES then
        problem("spawn " .. i .. " stands on a tree at " .. s.x .. "," .. s.y)
      end
    end
    if s.y > liquid - rules.SPAWN_ABOVE_LIQUID then
      problem("spawn " .. i .. " too close to the liquid")
    end
    if s.x < rules.SPAWN_EDGE_DISTANCE or s.x > width - 1 - rules.SPAWN_EDGE_DISTANCE then
      problem("spawn " .. i .. " too close to an edge")
    end
    for _, well in ipairs(map.wells) do
      if
        s.x > well.x - rules.SPAWN_WELL_DISTANCE
        and s.x < well.x + well.width + rules.SPAWN_WELL_DISTANCE
      then
        problem("spawn " .. i .. " too close to a well")
      end
    end
    for j = i + 1, #map.spawns do
      local o = map.spawns[j]
      local dx, dy = s.x - o.x, s.y - o.y
      if dx * dx + dy * dy < map.spawn_distance * map.spawn_distance then
        problem("spawns " .. i .. " and " .. j .. " too close")
      end
    end
  end
  for team = 1, settings.teams do
    if per_team[team] ~= settings.cats_per_team then
      problem("team " .. team .. " has " .. tostring(per_team[team]) .. " cats")
    end
  end
  for _, tree in ipairs(map.trees) do
    if tree.x < rules.SHORE_WIDTH or tree.x > width - rules.SHORE_WIDTH - rules.TRUNK_WIDTH then
      problem("tree on a shore at " .. tree.x)
    end
  end
  for _, o in ipairs(map.overhangs) do
    if o.x < rules.SHORE_WIDTH or o.x >= width - rules.SHORE_WIDTH then
      problem("overhang on a shore at " .. o.x)
    end
    if o.y + o.height >= liquid - rules.CAVE_ABOVE_LIQUID then
      problem("overhang under the cave floor at " .. o.x)
    end
  end
  if map.first_team < 1 or map.first_team > settings.teams then
    problem("first team " .. map.first_team)
  end
  return problems
end

local function sweep(seeds, with_islands)
  local strict, total = 0, 0
  for _, settings in ipairs(maps.SETTINGS) do
    local kinds, firsts = {}, {}
    for seed = 1, seeds do
      local map = mapgen.generate(seed * 7919, settings)
      local problems = check(map, settings)
      if with_islands then
        local small = maps.small_islands(map.terrain, rules.ISLAND_MIN_CELLS)
        if small > 0 then
          problems[#problems + 1] = small .. " floating crumbs"
        end
      end
      assert.are.same(
        {},
        problems,
        "seed " .. seed * 7919 .. " with " .. settings.teams .. "x" .. settings.cats_per_team
      )
      kinds[map.liquid.kind] = true
      firsts[map.first_team] = true
      total = total + 1
      if map.spawn_distance == rules.SPAWN_DISTANCE then
        strict = strict + 1
      end
      if settings.teams * settings.cats_per_team < 48 then
        assert.are.equal(
          rules.SPAWN_DISTANCE,
          map.spawn_distance,
          "seed " .. seed * 7919 .. " with " .. settings.teams .. "x" .. settings.cats_per_team
        )
      end
    end
    if settings.map == "random" then
      assert.is_true(kinds.water and kinds.lava, "the random map never varies")
    end
    local count = 0
    for _ in pairs(firsts) do
      count = count + 1
    end
    assert.is_true(count > 1, "the first team never varies")
  end
  assert.is_true(
    strict * 2 > total,
    strict .. " of " .. total .. " maps keep the full spawn distance"
  )
end

describe("🗺️ map generation (§5.3)", function()
  it("🗺️ sizes the map by the number of cats", function()
    assert.are.equal(384, mapgen.width_for(2))
    assert.are.equal(464, mapgen.width_for(8))
    assert.are.equal(896, mapgen.width_for(32))
    assert.are.equal(1024, mapgen.width_for(48))
  end)

  it("🗺️ holds every rule of §5.3 on 10 seeds × 7 settings", function()
    sweep(10, true)
  end)

  it("🗺️ draws the spawns at random along the map, not packed from one side", function()
    local spread, leftmost = 0, {}
    for seed = 1, 20 do
      local map = mapgen.generate(seed * 7919, maps.SETTINGS[1])
      local a, b = map.spawns[1].x, map.spawns[2].x
      spread = spread + math.abs(a - b)
      leftmost[math.min(a, b)] = true
    end
    local distinct = 0
    for _ in pairs(leftmost) do
      distinct = distinct + 1
    end
    assert.is_true(spread / 20 > 80, "two cats " .. spread / 20 .. " px apart on average")
    assert.is_true(distinct > 10, distinct .. " distinct leftmost spawns over 20 seeds")
  end)

  it("🗺️ gives the same map for the same seed, another for another", function()
    local settings = maps.SETTINGS[4]
    local a, b = mapgen.generate(99, settings), mapgen.generate(99, settings)
    assert.are.same({ terrain.cells_hash(a.terrain) }, { terrain.cells_hash(b.terrain) })
    assert.are.same(a.spawns, b.spawns)
    assert.are.same(a.wells, b.wells)
    local c = mapgen.generate(100, settings)
    assert.are_not.same({ terrain.cells_hash(a.terrain) }, { terrain.cells_hash(c.terrain) })
  end)

  it("🗺️ interleaves the teams along the map", function()
    local map = mapgen.generate(4242, maps.SETTINGS[6])
    local sorted = {}
    for _, s in ipairs(map.spawns) do
      sorted[#sorted + 1] = s
    end
    table.sort(sorted, function(a, b)
      return a.x < b.x or (a.x == b.x and a.y < b.y)
    end)
    local seen = {}
    for i = 1, 8 do
      seen[sorted[i].team] = true
    end
    local n = 0
    for _ in pairs(seen) do
      n = n + 1
    end
    assert.are.equal(8, n)
  end)
end)

describe("🌲 the forest and 🌋 the volcano (§5.3)", function()
  local SEEDS = 12

  local function each(map_name, fn)
    for seed = 1, SEEDS do
      local settings = { teams = 4, cats_per_team = 3, map = map_name }
      fn(mapgen.generate(seed * 104729, settings), seed * 104729)
    end
  end

  local function count(t, material)
    local n = 0
    for i = 1, #t.cells do
      if t.cells[i] == material then
        n = n + 1
      end
    end
    return n
  end

  local function open_sky_surface(t)
    local open = 0
    for x = rules.SHORE_WIDTH, t.width - 1 - rules.SHORE_WIDTH do
      local y = 0
      while y < t.height and not terrain.solid(t, x, y) do
        y = y + 1
      end
      if y < rules.MAP_HEIGHT - rules.LIQUID_DEPTH then
        open = open + 1
      end
    end
    return open
  end

  it("🗺️ uses §5.3's figures for overhangs, trees and stalactites", function()
    assert.are.same({
      overhang = { 8, 24, 4, 9, 14, 3, 5, 16 },
      tree = { 45, 75, 2, 10, 16, 5, 8, 2, 1 },
      stalactite = { 8, 16, 3, 10, 4, 1 },
      volcano = 390,
    }, {
      overhang = {
        rules.OVERHANG_GAP_MIN,
        rules.OVERHANG_GAP_MAX,
        rules.OVERHANG_LIP,
        rules.OVERHANG_REACH_MIN,
        rules.OVERHANG_REACH_MAX,
        rules.OVERHANG_HEIGHT_MIN,
        rules.OVERHANG_HEIGHT_MAX,
        rules.OVERHANG_WELL_DISTANCE,
      },
      tree = {
        rules.TREE_GAP_MIN,
        rules.TREE_GAP_MAX,
        rules.TRUNK_WIDTH,
        rules.TRUNK_MIN,
        rules.TRUNK_MAX,
        rules.CROWN_MIN,
        rules.CROWN_MAX,
        rules.CROWN_OVERLAP,
        rules.DECOR_WELL_MARGIN,
      },
      stalactite = {
        rules.STALACTITE_GAP_MIN,
        rules.STALACTITE_GAP_MAX,
        rules.STALACTITE_MIN,
        rules.STALACTITE_MAX,
        rules.STALACTITE_ROOM,
        rules.STALACTITE_HALF,
      },
      volcano = rules.CAVE_THRESHOLD_VOLCANO,
    })
  end)

  it(
    "🌋 lays girders at varied heights, 12–56 px over the ground, and blobs may spawn on them",
    function()
      assert.are.same({ 16, 40, 90, 16, 32, 3, 12, 56 }, {
        rules.GIRDER_WELL_DISTANCE,
        rules.GIRDER_GAP_MIN,
        rules.GIRDER_GAP_MAX,
        rules.GIRDER_MIN,
        rules.GIRDER_MAX,
        rules.GIRDER_THICKNESS,
        rules.GIRDER_ABOVE_MIN,
        rules.GIRDER_ABOVE_MAX,
      })
      local girders, high, low, on_steel = 0, 0, 0, 0
      local lowest, highest = math.huge, 0
      each("volcano", function(map, seed)
        local t = map.terrain
        assert.is_true(#map.girders >= 3, "seed " .. seed)
        for i, g in ipairs(map.girders) do
          local where = "seed " .. seed .. " girder at " .. g.x .. "," .. g.y
          local before = map.girders[i - 1]
          if before then
            assert.is_true(g.x - (before.x + before.length) >= rules.GIRDER_GAP_MIN, where)
          end
          assert.is_true(g.length >= 16 and g.length <= 32, where)
          assert.is_true(
            g.x >= rules.SHORE_WIDTH and g.x + g.length <= t.width - rules.SHORE_WIDTH,
            where
          )
          for x = g.x, g.x + g.length - 1 do
            for y = g.y, g.y + rules.GIRDER_THICKNESS - 1 do
              assert.are.equal(terrain.STEEL, terrain.get(t, x, y), where)
            end
            assert.is_false(terrain.solid(t, x, g.y - 1), where)
          end
          local ground = t.height
          for x = g.x, g.x + g.length - 1 do
            local y = g.y + rules.GIRDER_THICKNESS
            while y < t.height and not terrain.solid(t, x, y) do
              y = y + 1
            end
            ground = math.min(ground, y)
          end
          local gap = ground - (g.y + rules.GIRDER_THICKNESS)
          assert.is_true(gap >= 12 and gap <= 56, where .. " floats " .. gap .. " px up")
          lowest, highest = math.min(lowest, gap), math.max(highest, gap)
          if gap >= 40 then
            high = high + 1
          elseif gap < 24 then
            low = low + 1
          end
        end
        for _, s in ipairs(map.spawns) do
          if terrain.get(t, s.x, s.y + 1) == terrain.STEEL then
            on_steel = on_steel + 1
          end
        end
        girders = girders + #map.girders
      end)
      assert.is_true(high > 0 and low > 0, high .. " high, " .. low .. " low")
      assert.is_true(
        lowest <= rules.GIRDER_ABOVE_MIN + 2 and highest >= rules.GIRDER_ABOVE_MAX - 2,
        "heights from " .. lowest .. " to " .. highest .. " px"
      )
      assert.is_true(on_steel > 0, "no blob ever spawns on a girder")
      each("forest", function(map, seed)
        assert.are.same(
          { 0, 0 },
          { #map.girders, count(map.terrain, terrain.STEEL) },
          "seed " .. seed
        )
      end)
    end
  )

  it("🗺️ gives the forest water and the volcano lava, and draws either at random", function()
    local seen = {}
    for seed = 1, 20 do
      local map = mapgen.generate(seed, { teams = 2, cats_per_team = 1, map = "random" })
      seen[map.biome] = true
      assert.are.equal(maps.LIQUID[map.biome], map.liquid.kind)
    end
    assert.is_true(seen.forest and seen.volcano)
    each("forest", function(map)
      assert.are.same({ "forest", "water" }, { map.biome, map.liquid.kind })
    end)
    each("volcano", function(map)
      assert.are.same({ "volcano", "lava" }, { map.biome, map.liquid.kind })
    end)
  end)

  it(
    "🌲 plants a tree every ~60 px of open ground: a 2 px trunk of 10–16 px, a crown of 5–8 px",
    function()
      local trees, ground = 0, 0
      each("forest", function(map, seed)
        local t = map.terrain
        assert.is_true(#map.trees >= 2, "seed " .. seed)
        for _, tree in ipairs(map.trees) do
          local where = "seed " .. seed .. " tree at " .. tree.x
          assert.is_true(tree.x >= rules.SHORE_WIDTH, where)
          assert.is_true(tree.x <= t.width - rules.SHORE_WIDTH - rules.TRUNK_WIDTH, where)
          assert.are.equal(
            tree.ground - tree.height - tree.radius + rules.CROWN_OVERLAP,
            tree.crown,
            where
          )
          assert.are.equal(
            terrain.LEAVES,
            terrain.get(t, tree.x, tree.ground - tree.height - 1),
            where
          )
          assert.is_true(tree.height >= 10 and tree.height <= 16, where)
          assert.is_true(tree.radius >= 5 and tree.radius <= 8, where)
          for x = tree.x, tree.x + 1 do
            assert.is_true(terrain.solid(t, x, tree.ground), where)
            for y = tree.ground - tree.height, tree.ground - 1 do
              assert.are.equal(terrain.WOOD, terrain.get(t, x, y), where)
            end
          end
          assert.is_false(terrain.solid(t, tree.x - 1, tree.ground - 1), where)
          assert.is_false(terrain.solid(t, tree.x + 2, tree.ground - 1), where)
          local leaves, disc = 0, 0
          for y = tree.crown - tree.radius, tree.crown + tree.radius do
            for x = tree.x - tree.radius, tree.x + 1 + tree.radius do
              local dx, dy = 2 * x - (2 * tree.x + 1), 2 * (y - tree.crown)
              if dx * dx + dy * dy <= 4 * tree.radius * tree.radius then
                disc = disc + 1
                if terrain.get(t, x, y) == terrain.LEAVES then
                  leaves = leaves + 1
                end
              end
            end
          end
          assert.is_true(leaves >= disc * 0.8, where .. ": " .. leaves .. " leaves of " .. disc)
        end
        trees = trees + #map.trees
        ground = ground + open_sky_surface(t)
      end)
      local every = ground / trees
      assert.is_true(every > 45 and every < 110, "a tree every " .. every .. " px of open ground")
      each("volcano", function(map, seed)
        assert.are.same(
          { 0, 0, 0 },
          { #map.trees, count(map.terrain, terrain.WOOD), count(map.terrain, terrain.LEAVES) },
          "seed " .. seed
        )
      end)
    end
  )

  it(
    "🗺️ carves overhangs in both maps: a lip of terrain over a hollow that opens on a slope",
    function()
      for _, name in ipairs({ "forest", "volcano" }) do
        local with = 0
        each(name, function(map, seed)
          local t = map.terrain
          if #map.overhangs > 0 then
            with = with + 1
          end
          for _, o in ipairs(map.overhangs) do
            local where = name .. " seed " .. seed .. " overhang at " .. o.x
            assert.is_true(
              o.reach >= 9 and o.reach <= 14 and o.height >= 3 and o.height <= 5,
              where
            )
            assert.is_true(o.x >= rules.SHORE_WIDTH and o.x < t.width - rules.SHORE_WIDTH, where)
            local floor_y = rules.MAP_HEIGHT - rules.LIQUID_DEPTH - rules.CAVE_ABOVE_LIQUID
            assert.is_true(o.y + o.height < floor_y, where)
            assert.is_true(maps.first_soil(t, o.x + o.side * (o.reach - 1)) > o.y - o.height, where)
            local hanging = false
            for _, s in ipairs(map.stalactites) do
              local tip = s.top + s.length - 1
              hanging = hanging or (math.abs(s.x - o.x) <= 1 and o.y >= s.top and o.y <= tip)
            end
            assert.is_true(hanging or not terrain.solid(t, o.x, o.y), where)
            assert.is_true(terrain.solid(t, o.x, o.y - o.height - 1), where)
            local lip = o.y - o.height - rules.OVERHANG_LIP
            assert.are.equal(lip, maps.first_soil(t, o.x), where)
            local opens = false
            for j = 1, o.reach do
              local surface = maps.first_soil(t, o.x + o.side * j)
              opens = opens or (surface > o.y - o.height and surface < t.height)
            end
            assert.is_true(opens, where .. " does not open on the slope")
          end
        end)
        assert.is_true(
          with >= SEEDS * 0.75,
          name .. ": " .. with .. " of " .. SEEDS .. " maps have an overhang"
        )
      end
    end
  )

  it(
    "🌋 hangs stalactites under the volcano's ceilings, and digs more caves than the forest",
    function()
      local volcano_air, forest_air, tapered, stacked, total = 0, 0, 0, 0, 0
      each("volcano", function(map, seed)
        local t = map.terrain
        local per_column = {}
        assert.is_true(#map.stalactites >= 3, "seed " .. seed)
        for _, s in ipairs(map.stalactites) do
          local where = "seed " .. seed .. " stalactite at " .. s.x .. "," .. s.top
          assert.is_true(s.length >= 3 and s.length <= 10, where)
          assert.is_true(terrain.solid(t, s.x, s.top - 1), where)
          for y = s.top, s.top + s.length - 1 do
            assert.is_true(terrain.solid(t, s.x, y), where)
          end
          local tip = s.top + s.length - 1
          for y = tip + 1, tip + rules.STALACTITE_ROOM do
            assert.is_false(terrain.solid(t, s.x, y), where)
          end
          if not terrain.solid(t, s.x - 1, tip) and not terrain.solid(t, s.x + 1, tip) then
            tapered = tapered + 1
          end
          total = total + 1
          per_column[s.x] = (per_column[s.x] or 0) + 1
          if per_column[s.x] == 2 then
            stacked = stacked + 1
          end
        end
        volcano_air = volcano_air + count(t, terrain.AIR)
      end)
      each("forest", function(map)
        assert.are.equal(0, #map.stalactites)
        forest_air = forest_air + count(map.terrain, terrain.AIR)
      end)
      assert.is_true(volcano_air > forest_air, volcano_air .. " air cells against " .. forest_air)
      assert.is_true(
        tapered > total * 0.8,
        tapered .. " of " .. total .. " stalactites end in a point"
      )
      assert.is_true(stacked > 0, "never two ceilings in one column")
    end
  )
end)

describe("🗺️ floating terrain", function()
  local function chunk(t, x0, y0, cells)
    local placed = 0
    for y = y0, y0 + 20 do
      for x = x0, x0 + 20 do
        if placed < cells then
          terrain.set(t, x, y, terrain.SOIL)
          placed = placed + 1
        end
      end
    end
  end

  it("🗺️ removes an unattached chunk of 63 cells and keeps one of 64", function()
    local t = terrain.new(120, 60)
    for x = 0, 119 do
      terrain.set(t, x, 59, terrain.SOIL)
    end
    chunk(t, 10, 10, 63)
    chunk(t, 60, 10, 64)
    assert.are.equal(63, mapgen.remove_islands(t))
    assert.is_false(terrain.solid(t, 10, 10))
    assert.is_true(terrain.solid(t, 60, 10))
    assert.is_true(terrain.solid(t, 0, 59))
  end)
end)

describe("🗺️ map generation sweep", function()
  it("🗺️ holds every rule of §5.3 on 200 seeds × 7 settings #sweep", function()
    sweep(200, true)
  end)
end)

describe("🗺️ map generation cost", function()
  it("🗺️ builds the largest map within its budget #perf", function()
    local budget = jit and 150 or 1000
    local worst = 0
    for seed = 1, 5 do
      local start = os.clock()
      mapgen.generate(
        seed,
        { teams = 8, cats_per_team = 6, map = seed % 2 == 0 and "forest" or "volcano" }
      )
      worst = math.max(worst, (os.clock() - start) * 1000)
    end
    print(
      string.format(
        "\n🗺️ largest map: %.1f ms worst of 5 under %s",
        worst,
        jit and "LuaJIT" or "Lua 5.1"
      )
    )
    assert.is_true(worst < budget, worst .. " ms")
  end)
end)

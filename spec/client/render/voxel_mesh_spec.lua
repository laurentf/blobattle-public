local terrain = require("shared.sim.terrain")
local voxel_mesh = require("render.voxel_mesh")
local world = require("shared.sim.world")

local function kind_of(nx, ny, nz)
  if nz > 0.9 then
    return "front"
  elseif ny > 0.5 then
    return "top"
  elseif ny < -0.5 then
    return "bottom"
  elseif nx < -0.5 then
    return "left"
  elseif nx > 0.5 then
    return "right"
  end
  error("a face with no direction")
end

local function cover(seen, key)
  seen[key] = (seen[key] or 0) + 1
end

local function faces_of(mesh, chunk)
  local height = mesh.terrain.height
  local seen = {}
  for _, part in ipairs(voxel_mesh.parts(chunk)) do
    local pos, nrm = part.pos, part.nrm
    assert.are.equal(0, part.n % 6)
    for q = 0, part.n / 6 - 1 do
      local base = q * 18
      local kind = kind_of(nrm[base + 1], nrm[base + 2], nrm[base + 3])
      local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
      for v = 0, 5 do
        local x, y = pos[base + v * 3 + 1], pos[base + v * 3 + 2]
        x0, x1 = math.min(x0, x), math.max(x1, x)
        y0, y1 = math.min(y0, y), math.max(y1, y)
      end
      if kind == "front" then
        for x = x0, x1 - 1 do
          cover(seen, "front:" .. x .. ":" .. (height - y1))
        end
      elseif kind == "top" then
        for x = x0, x1 - 1 do
          cover(seen, "top:" .. x .. ":" .. (height - y1))
        end
      elseif kind == "bottom" then
        for x = x0, x1 - 1 do
          cover(seen, "bottom:" .. x .. ":" .. (height - y0 - 1))
        end
      else
        local x = kind == "left" and x0 or x0 - 1
        for y = height - y1, height - y0 - 1 do
          cover(seen, kind .. ":" .. x .. ":" .. y)
        end
      end
    end
  end
  return seen
end

local function boundaries(t, x0, x1)
  local expected = {}
  for y = 0, t.height - 1 do
    for x = x0, x1 - 1 do
      if terrain.solid(t, x, y) then
        expected["front:" .. x .. ":" .. y] = 1
        if not terrain.solid(t, x, y - 1) then
          expected["top:" .. x .. ":" .. y] = 1
        end
        if not terrain.solid(t, x, y + 1) then
          expected["bottom:" .. x .. ":" .. y] = 1
        end
        if not terrain.solid(t, x - 1, y) then
          expected["left:" .. x .. ":" .. y] = 1
        end
        if not terrain.solid(t, x + 1, y) then
          expected["right:" .. x .. ":" .. y] = 1
        end
      end
    end
  end
  return expected
end

local function differences(expected, seen)
  local wrong = {}
  for key, count in pairs(seen) do
    if expected[key] ~= count then
      wrong[#wrong + 1] = key .. " covered " .. count .. " times"
    end
  end
  for key in pairs(expected) do
    if seen[key] == nil then
      wrong[#wrong + 1] = key .. " missing"
    end
  end
  table.sort(wrong)
  return wrong
end

local function signature(chunk)
  local keys = {}
  for _, part in ipairs(voxel_mesh.parts(chunk)) do
    for q = 0, part.n / 6 - 1 do
      local b = q * 18
      local k = {}
      for i = 1, 18 do
        k[i] = part.pos[b + i]
      end
      k[19], k[20], k[21] = part.nrm[b + 1], part.nrm[b + 2], part.nrm[b + 3]
      keys[#keys + 1] = table.concat(k, ",")
    end
  end
  table.sort(keys)
  return table.concat(keys, ";")
end

local function differs_from_fresh(mesh)
  local fresh = voxel_mesh.new(mesh.terrain)
  voxel_mesh.build_all(fresh)
  for i, chunk in ipairs(mesh.chunks) do
    if signature(chunk) ~= signature(fresh.chunks[i]) then
      return i
    end
  end
  return nil
end

local function rim_faces(mesh)
  local height = mesh.terrain.height
  local rims = {}
  for _, chunk in ipairs(mesh.chunks) do
    for _, part in ipairs(voxel_mesh.parts(chunk)) do
      for q = 0, part.n / 6 - 1 do
        local b = q * 18
        if part.nrm[b + 3] > 0.9 and part.nrm[b + 2] > 0.02 then
          local x0, x1 = math.huge, -math.huge
          for v = 0, 5 do
            x0, x1 = math.min(x0, part.pos[b + v * 3 + 1]), math.max(x1, part.pos[b + v * 3 + 1])
          end
          local y = height - part.pos[b + 8]
          for x = x0, x1 - 1 do
            rims[x .. ":" .. y] = true
          end
        end
      end
    end
  end
  return rims
end

local function explode_under_the_active_cat(w)
  while w.turn.state ~= "aiming" do
    world.step(w)
  end
  local craters = {}
  local fire = { team = w.turn.team, kind = "fire", weapon = "bazooka", angle = 768, power = 5 }
  local inputs = { fire }
  while #craters == 0 do
    for _, e in ipairs(world.step(w, inputs)) do
      if e.type == "exploded" then
        craters[#craters + 1] = { x = e.x, y = e.y, radius = e.radius }
      end
    end
    inputs = nil
  end
  return craters[1]
end

describe("🧱 the voxel terrain mesh (§7.4, D-09)", function()
  it("🧱 has exactly one face per soil-air boundary on a whole generated map", function()
    local w = assert(world.new(4242, { teams = 2, cats_per_team = 2 }))
    local mesh = voxel_mesh.new(w.terrain)
    voxel_mesh.build_all(mesh)
    for _, chunk in ipairs(mesh.chunks) do
      local expected = boundaries(w.terrain, chunk.x0, chunk.x1)
      assert.are.same({}, differences(expected, faces_of(mesh, chunk)), "chunk " .. chunk.index)
    end
  end)

  it("🧱 after a crater, the touched chunks have exactly one face per boundary", function()
    local w = assert(world.new(1234, { teams = 2, cats_per_team = 1 }))
    local mesh = voxel_mesh.new(w.terrain)
    voxel_mesh.build_all(mesh)
    local crater = explode_under_the_active_cat(w)
    local touched = voxel_mesh.crater(mesh, { x = crater.x, y = crater.y, radius = crater.radius })
    assert.is_true(#touched >= 1)
    local done = voxel_mesh.rebuild(mesh, function()
      return true
    end)
    assert.are.same(touched, done)
    for _, index in ipairs(touched) do
      local chunk = mesh.chunks[index]
      local expected = boundaries(w.terrain, chunk.x0, chunk.x1)
      assert.are.same({}, differences(expected, faces_of(mesh, chunk)), "chunk " .. index)
    end
  end)

  it("🧱 recomputes only the rows and columns a crater touches, never a whole chunk", function()
    local w = assert(world.new(1234, { teams = 2, cats_per_team = 1 }))
    local mesh = voxel_mesh.new(w.terrain)
    voxel_mesh.build_all(mesh)
    local crater = explode_under_the_active_cat(w)
    local r = crater.radius
    local touched = voxel_mesh.crater(mesh, { x = crater.x, y = crater.y, radius = r })
    local rows, cols = 0, 0
    voxel_mesh.rebuild(mesh, function(kind)
      if kind == "row" then
        rows = rows + 1
      else
        cols = cols + 1
      end
      return true
    end)
    local bands = math.floor((crater.y + r) / voxel_mesh.BAND)
      - math.floor((crater.y - r) / voxel_mesh.BAND)
      + 1
    assert.is_true(rows <= #touched * (2 * r + 4), rows .. " rows")
    assert.is_true(cols <= (2 * r + 3) * bands, cols .. " columns over " .. bands .. " bands")
    assert.is_true(rows < #touched * mesh.terrain.height)
    local lo = math.floor((crater.x - r - 1) / voxel_mesh.CHUNK) + 1
    local hi = math.floor((crater.x + r + 1) / voxel_mesh.CHUNK) + 1
    for _, index in ipairs(touched) do
      assert.is_true(index >= lo and index <= hi)
    end
  end)

  it(
    "🧱 after a crack, rebuilds only its rows and columns, to what a fresh build gives",
    function()
      local quake = require("shared.sim.quake")
      local w = assert(world.new(31, { teams = 2, cats_per_team = 1, map = "forest" }))
      local mesh = voxel_mesh.new(w.terrain)
      voxel_mesh.build_all(mesh)
      local crack = quake.open(w, 150)
      local bottom = w.liquid.level + 4
      local area = { x0 = crack.x - 1, x1 = crack.x + crack.width, y0 = crack.top, y1 = bottom }
      local touched = voxel_mesh.region(mesh, area)
      local rows, cols = 0, 0
      voxel_mesh.rebuild(mesh, function(kind)
        if kind == "row" then
          rows = rows + 1
        else
          cols = cols + 1
        end
        return true
      end)
      local bands = math.floor(bottom / voxel_mesh.BAND)
        - math.floor(crack.top / voxel_mesh.BAND)
        + 1
      assert.is_true(#touched >= 1 and #touched <= 2, #touched .. " chunks")
      assert.is_true(rows <= #touched * (bottom - crack.top + 4), rows .. " rows")
      assert.is_true(cols <= (crack.width + 4) * bands, cols .. " columns")
      assert.is_nil(differs_from_fresh(mesh))
    end
  )

  it("🧱 tells whether a cell's front face is drawn, as the sim's cell says", function()
    local quake = require("shared.sim.quake")
    local w = assert(world.new(31, { teams = 2, cats_per_team = 1, map = "forest" }))
    local mesh = voxel_mesh.new(w.terrain)
    voxel_mesh.build_all(mesh)
    local crack = quake.open(w, 150)
    voxel_mesh.region(mesh, { x0 = 149, x1 = 154, y0 = crack.top, y1 = w.liquid.level + 4 })
    local wrong, drawn, open = {}, 0, 0
    for _, step in ipairs({ false, true }) do
      if step then
        voxel_mesh.rebuild(mesh, function()
          return true
        end)
      end
      for y = 0, w.terrain.height - 1 do
        for x = 120, 180 do
          local solid = terrain.solid(w.terrain, x, y)
          local front = voxel_mesh.front(mesh, x, y)
          if step and front ~= solid and #wrong < 5 then
            wrong[#wrong + 1] = x .. "," .. y
          end
          if step and x >= 150 and x <= 153 and y >= crack.top and y <= crack.top + 3 then
            open = open + (front and 1 or 0)
          end
          drawn = drawn + (front and 1 or 0)
        end
      end
    end
    assert.are.same({}, wrong)
    assert.are.same({ 0, true }, { open, drawn > 1000 })
    assert.is_false(voxel_mesh.front(mesh, -1, 10))
    assert.is_false(voxel_mesh.front(mesh, w.terrain.width, 10))
  end)

  it("🧱 hands a chunk over only once all its parts are rebuilt, slice by slice", function()
    local w = assert(world.new(1234, { teams = 2, cats_per_team = 1 }))
    local mesh = voxel_mesh.new(w.terrain)
    voxel_mesh.build_all(mesh)
    local crater = explode_under_the_active_cat(w)
    local touched = voxel_mesh.crater(mesh, { x = crater.x, y = crater.y, radius = crater.radius })
    local handed, slices = {}, 0
    while #handed < #touched do
      slices = slices + 1
      local budget = 5
      for _, index in
        ipairs(voxel_mesh.rebuild(mesh, function()
          budget = budget - 1
          return budget >= 0
        end))
      do
        handed[#handed + 1] = index
      end
      assert.is_true(slices < 100)
    end
    assert.is_true(slices > 2)
    table.sort(handed)
    assert.are.same(touched, handed)
    assert.is_false(voxel_mesh.busy(mesh))
  end)

  it("🧱 rebuilds after random craters exactly what a fresh build gives", function()
    local state = 12345
    local function draw(n)
      state = state * 48271 % 2147483647
      return state % n
    end
    for trial = 1, 40 do
      local width, height = 70 + draw(40), 40 + draw(20)
      local t = terrain.new(width, height)
      for y = 0, height - 1 do
        for x = 0, width - 1 do
          if y > 8 + draw(6) and draw(10) > 0 then
            terrain.set(t, x, y, terrain.SOIL)
          end
        end
      end
      local mesh = voxel_mesh.new(t)
      voxel_mesh.build_all(mesh)
      for _ = 1, 12 do
        local r = 1 + draw(12)
        local x, y = draw(width + 30) - 15, draw(height + 30) - 15
        if draw(4) == 0 then
          x = voxel_mesh.CHUNK * (1 + draw(3)) + draw(2 * r + 3) - r - 1
        end
        terrain.carve(t, x, y, r)
        voxel_mesh.crater(mesh, { x = x, y = y, radius = r })
        local budget = draw(40)
        voxel_mesh.rebuild(mesh, function()
          budget = budget - 1
          return budget >= 0
        end)
      end
      voxel_mesh.rebuild(mesh, function()
        return true
      end)
      assert.is_nil(differs_from_fresh(mesh), "trial " .. trial)
    end
  end)

  it("🧱 follows the craters of a game played by the sim, slice by slice", function()
    local w = assert(world.new(4242, { teams = 4, cats_per_team = 2 }))
    local mesh = voxel_mesh.new(w.terrain)
    voxel_mesh.build_all(mesh)
    local craters, state = 0, 7
    for _ = 1, 400 do
      local inputs
      if w.turn.state == "aiming" then
        state = state * 48271 % 2147483647
        inputs = {
          {
            team = w.turn.team,
            kind = "fire",
            weapon = "bazooka",
            angle = state % 1024,
            power = 1 + state % 30,
          },
        }
      end
      for _, e in ipairs(world.step(w, inputs)) do
        if e.type == "exploded" then
          voxel_mesh.crater(mesh, { x = e.x, y = e.y, radius = e.radius })
          craters = craters + 1
        end
      end
      local budget = 3
      voxel_mesh.rebuild(mesh, function()
        budget = budget - 1
        return budget >= 0
      end)
    end
    voxel_mesh.rebuild(mesh, function()
      return true
    end)
    assert.is_true(craters > 2, craters .. " craters")
    assert.is_nil(differs_from_fresh(mesh))
  end)

  it(
    "🧱 follows the cracks of a forest's quakes, edges above a crack's top too, slice by slice",
    function()
      local w = assert(world.new(22, { teams = 2, cats_per_team = 2, map = "forest" }))
      local mesh = voxel_mesh.new(w.terrain)
      voxel_mesh.build_all(mesh)
      local cracked, higher = 0, 0
      for _ = 1, 30000 do
        local inputs = nil
        if w.turn.state == "aiming" then
          inputs = { { team = w.turn.team, kind = "skip" } }
        end
        for _, e in ipairs(world.step(w, inputs)) do
          if e.type == "cracked" then
            voxel_mesh.region(mesh, voxel_mesh.crack_area(e, w.liquid.level))
            cracked = cracked + 1
            for _, crack in ipairs(w.cracks) do
              if crack.x == e.x and e.top < crack.top then
                higher = higher + 1
              end
            end
          end
        end
        local budget = 3
        voxel_mesh.rebuild(mesh, function()
          budget = budget - 1
          return budget >= 0
        end)
        if w.rounds >= 11 or w.turn.state == "ended" then
          break
        end
      end
      voxel_mesh.rebuild(mesh, function()
        return true
      end)
      assert.is_true(cracked >= 5 and higher >= 1, cracked .. " cracks, " .. higher .. " higher")
      assert.is_nil(differs_from_fresh(mesh))
    end
  )

  it(
    "🧱 a crack's area spans its columns, one more on each side, from its top to 4 px under L",
    function()
      assert.are.same(
        { x0 = 139, x1 = 146, y0 = 97, y1 = 236 },
        voxel_mesh.crack_area({ x = 140, width = 6, top = 97 }, 232)
      )
    end
  )

  it("🧱 draws the rim on a front face exactly when air lies one or two cells above", function()
    local t = terrain.new(8, 10)
    for y = 3, 9 do
      for x = 0, 7 do
        terrain.set(t, x, y, terrain.SOIL)
      end
    end
    terrain.set(t, 2, 2, terrain.SOIL)
    terrain.set(t, 2, 1, terrain.SOIL)
    for y = 0, 2 do
      terrain.set(t, 5, y, terrain.SOIL)
    end
    local mesh = voxel_mesh.new(t)
    voxel_mesh.build_all(mesh)
    local rims = rim_faces(mesh)
    for x = 0, 7 do
      for y = 0, 9 do
        local expected = terrain.solid(t, x, y)
          and (not terrain.solid(t, x, y - 1) or not terrain.solid(t, x, y - 2))
        assert.are.equal(expected, rims[x .. ":" .. y] == true, x .. "," .. y)
      end
    end
  end)

  it("🧱 merges two craters on the same chunk into one pending rebuild", function()
    local t = terrain.new(64, 40)
    for y = 20, 39 do
      for x = 0, 63 do
        terrain.set(t, x, y, terrain.SOIL)
      end
    end
    local mesh = voxel_mesh.new(t)
    voxel_mesh.build_all(mesh)
    terrain.carve(t, 10, 20, 4)
    voxel_mesh.crater(mesh, { x = 10, y = 20, radius = 4 })
    terrain.carve(t, 28, 22, 6)
    voxel_mesh.crater(mesh, { x = 28, y = 22, radius = 6 })
    local done = voxel_mesh.rebuild(mesh, function()
      return true
    end)
    assert.are.same({ 1, 2 }, done)
    for _, chunk in ipairs(mesh.chunks) do
      assert.are.same({}, differences(boundaries(t, chunk.x0, chunk.x1), faces_of(mesh, chunk)))
    end
  end)
end)

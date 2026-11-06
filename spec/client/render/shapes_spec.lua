local faces = require("render.faces")
local shapes = require("render.shapes")
local voxel_mesh = require("render.voxel_mesh")

local function bounds(part)
  local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
  for i = 0, part.n - 1 do
    for k = 1, 3 do
      local v = part.pos[i * 3 + k]
      lo[k], hi[k] = math.min(lo[k], v), math.max(hi[k], v)
    end
  end
  return lo, hi
end

local function area_by_normal(part)
  local areas = {}
  for q = 0, part.n / 6 - 1 do
    local b = q * 18
    local key = part.nrm[b + 1] .. "," .. part.nrm[b + 2] .. "," .. part.nrm[b + 3]
    local ax, ay, az = part.pos[b + 1], part.pos[b + 2], part.pos[b + 3]
    local ux, uy, uz = part.pos[b + 4] - ax, part.pos[b + 5] - ay, part.pos[b + 6] - az
    local vx, vy, vz = part.pos[b + 7] - ax, part.pos[b + 8] - ay, part.pos[b + 9] - az
    local cx, cy, cz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    areas[key] = (areas[key] or 0) + math.sqrt(cx * cx + cy * cy + cz * cz)
  end
  return areas
end

describe("🫧 the voxel shapes (§7.4)", function()
  it("🫧 makes a blob of about 7 × 7 × 5 voxels standing on y = 0", function()
    local blob = shapes.blob()
    local lo, hi = bounds(blob)
    assert.are.same({ -3.5, 0, -2.5 }, lo)
    assert.are.same({ 3.5, 7, 2.5 }, hi)
    assert.are.equal(0, blob.n % 6)
  end)

  it("🫧 closes the blob: as much surface faces each way as its opposite", function()
    local areas = area_by_normal(shapes.blob())
    local pairs_of_faces = { { "1,0,0", "-1,0,0" }, { "0,1,0", "0,-1,0" }, { "0,0,1", "0,0,-1" } }
    for _, pair in ipairs(pairs_of_faces) do
      assert.is_true(areas[pair[1]] > 0)
      assert.is_true(math.abs(areas[pair[1]] - areas[pair[2]]) < 1e-9, pair[1])
    end
  end)

  it("🫧 puts the calm face on the front of the blob and makes a unit cube", function()
    local lo = bounds(shapes.face(faces.calm))
    assert.is_true(lo[3] > 2.4)
    local cube = shapes.cube()
    assert.are.equal(36, cube.n)
    local clo, chi = bounds(cube)
    assert.are.same({ -0.5, -0.5, -0.5 }, clo)
    assert.are.same({ 0.5, 0.5, 0.5 }, chi)
  end)

  it(
    "🫧 extrudes flat cells into voxels centred like the blob's, only faces to the air",
    function()
      assert.are.equal(36, shapes.extrude({ { x = 0, y = 0 } }, { depth = 2 }).n)
      local two = shapes.extrude({ { x = 0, y = 0 }, { x = 1, y = 0 } }, { depth = 2 })
      assert.are.equal(60, two.n)
      local lo, hi = bounds(two)
      assert.are.same({ -0.5, 0, -1 }, lo)
      assert.are.same({ 1.5, 1, 1 }, hi)
      local areas = area_by_normal(two)
      assert.are.same({ 2, 2, 4, 4, 2, 2 }, {
        areas["0,0,1"],
        areas["0,0,-1"],
        areas["0,1,0"],
        areas["0,-1,0"],
        areas["1,0,0"],
        areas["-1,0,0"],
      })
    end
  )

  it(
    "🫧 raises a skyline: a column per height, a side only where the neighbour is lower",
    function()
      local part = shapes.skyline({ 2, 3, 1 }, { cell = 2, depth = 4 })
      local lo, hi = bounds(part)
      assert.are.same({ -1, 0, -2 }, lo)
      assert.are.same({ 5, 6, 2 }, hi)
      local areas = area_by_normal(part)
      assert.are.same({ 24, 24, 24, 24 }, {
        areas["0,0,1"],
        areas["0,1,0"],
        areas["1,0,0"],
        areas["-1,0,0"],
      })
      local rim = shapes.skyline({ 3 }, { cell = 1, depth = 1, band = 1 })
      local rlo, rhi = bounds(rim)
      assert.are.same({ -0.5, 2, -0.5 }, rlo)
      assert.are.same({ 0.5, 3, 0.5 }, rhi)
    end
  )

  it("🚀 makes a rocket lying along +x, nose forward, fins at the back", function()
    local rocket = shapes.rocket()
    local lo, hi = bounds(rocket)
    local length, width = hi[1] - lo[1], hi[2] - lo[2]
    assert.is_true(length >= 2 * width, length .. " × " .. width)
    assert.is_true(math.abs(lo[1] + hi[1]) < 1e-9, "centred on its middle")
    local nose, tail = 0, 0
    for i = 0, rocket.n - 1 do
      local x, y = rocket.pos[i * 3 + 1], rocket.pos[i * 3 + 2]
      if x > hi[1] - 0.6 then
        nose = math.max(nose, math.abs(y))
      elseif x < lo[1] + 0.6 then
        tail = math.max(tail, math.abs(y))
      end
    end
    assert.is_true(nose < tail, "a narrow nose and wide fins")
  end)

  it("🧨 makes a dynamite stick standing upright on the shot's feet, under its fuse", function()
    local fuse = require("render.fuse")
    local lo, hi = bounds(shapes.dynamite())
    local height, width = hi[2] - lo[2], hi[1] - lo[1]
    assert.is_true(height >= 2 * width, height .. " × " .. width)
    assert.are.equal(-1, lo[2])
    assert.is_true(math.abs(lo[1] + hi[1]) < 1e-9 and math.abs(lo[3] + hi[3]) < 1e-9, "centred")
    assert.are.equal(fuse.BASE, hi[2])
    assert.is_true(fuse.TIP > fuse.BASE)
    assert.are.equal(hi[1] - lo[1], hi[3] - lo[3])
    local areas = area_by_normal(shapes.dynamite())
    local opposite = { { "1,0,0", "-1,0,0" }, { "0,1,0", "0,-1,0" }, { "0,0,1", "0,0,-1" } }
    for _, pair in ipairs(opposite) do
      assert.is_true(areas[pair[1]] > 0 and math.abs(areas[pair[1]] - areas[pair[2]]) < 1e-9)
    end
  end)

  it("🧨 stands in front of the blob in depth, so a stick at its feet is seen", function()
    local fuse = require("render.fuse")
    local _, blob_hi = bounds(shapes.blob())
    local lo = bounds(shapes.dynamite())
    assert.is_true(fuse.Z + lo[3] > blob_hi[3], "behind the blob's front")
    assert.is_true(fuse.Z - lo[3] < require("render.voxel_mesh").DEPTH, "out of the ground")
  end)

  it("🫧 draws a face's rectangles as thin voxels on the front of the blob", function()
    local part = shapes.face({ eyes = { { -1, 4, 0, 5 } }, mouth = { { 0, 2, 1, 3 } } })
    assert.are.equal(72, part.n)
    local lo = bounds(part)
    assert.is_true(lo[3] > 2.4)
  end)

  it(
    "🫧 spans the liquid over the map and its margins, its surface marked for the waves",
    function()
      local part = shapes.liquid({ x0 = -64, x1 = 528, top = 24, bottom = -30 })
      local lo, hi = bounds(part)
      assert.are.same({ -64, -30, -voxel_mesh.DEPTH }, lo)
      assert.are.same({ 528, 24, voxel_mesh.DEPTH + 0.4 }, hi)
      for i = 0, part.n - 1 do
        local surface = part.nrm[i * 3 + 1] == 1
        assert.are.equal(surface, part.pos[i * 3 + 2] == 24)
      end
    end
  )
end)

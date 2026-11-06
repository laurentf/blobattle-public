local faces = require("render.faces")
local shapes = require("render.shapes")

local function front_reach()
  local blob, reach = shapes.blob(), {}
  for q = 0, blob.n / 6 - 1 do
    local b = q * 18
    if blob.nrm[b + 3] == 1 then
      local z = blob.pos[b + 3]
      local xs, ys = {}, {}
      for v = 0, 2 do
        xs[#xs + 1], ys[#ys + 1] = blob.pos[b + v * 3 + 1], blob.pos[b + v * 3 + 2]
      end
      local row = math.floor(math.min(ys[1], ys[2], ys[3]))
      local r = reach[row]
      if r == nil or z > r.z then
        r = { lo = math.huge, hi = -math.huge, z = z }
        reach[row] = r
      end
      if z == r.z then
        r.lo = math.min(r.lo, xs[1], xs[2], xs[3])
        r.hi = math.max(r.hi, xs[1], xs[2], xs[3])
      end
    end
  end
  return reach
end

local function centre_y(rect)
  return (rect[2] + rect[4]) / 2
end

local function height(rect)
  return rect[4] - rect[2]
end

local function inner_lower(brow)
  local outer, inner = brow[1], brow[2]
  return centre_y(inner) < centre_y(outer)
end

describe("😠 the blobs' faces (§7.2)", function()
  it("😠 lays every feature on the blob's foremost face, eyes above the mouth", function()
    local reach = front_reach()
    for _, name in ipairs(faces.NAMES) do
      local face = faces[name]
      for part, rects in pairs(face) do
        for _, r in ipairs(rects) do
          assert.is_true(r[1] < r[3] and r[2] < r[4], name .. " " .. part)
          for row = math.floor(r[2]), math.ceil(r[4]) - 1 do
            local front = reach[row]
            local where = name .. " " .. part .. " row " .. row
            assert.is_table(front, where)
            assert.are.equal(2.5, front.z, where)
            assert.is_true(r[1] >= front.lo and r[3] <= front.hi, where)
          end
        end
      end
      for _, m in ipairs(face.mouth or {}) do
        for _, e in ipairs(face.eyes) do
          assert.is_true(m[4] <= e[2], name)
        end
      end
    end
  end)

  it("😨 a scared blob opens its eyes wider, raises its brows and rounds its mouth", function()
    assert.is_true(height(faces.scared.eyes[1]) > height(faces.calm.eyes[1]))
    assert.is_false(inner_lower({ faces.scared.brows[1], faces.scared.brows[2] }))
    assert.is_false(inner_lower({ faces.scared.brows[4], faces.scared.brows[3] }))
    local lo_x, lo_y, hi_x, hi_y = math.huge, math.huge, -math.huge, -math.huge
    for _, r in ipairs(faces.scared.mouth) do
      lo_x, lo_y = math.min(lo_x, r[1]), math.min(lo_y, r[2])
      hi_x, hi_y = math.max(hi_x, r[3]), math.max(hi_y, r[4])
    end
    local cx, cy = (lo_x + hi_x) / 2, (lo_y + hi_y) / 2
    for _, r in ipairs(faces.scared.mouth) do
      assert.is_false(r[1] < cx and cx < r[3] and r[2] < cy and cy < r[4], "the O has a hole")
    end
  end)

  it("😠 an angry blob frowns: brows down toward the middle, mouth corners down", function()
    assert.is_true(inner_lower({ faces.angry.brows[1], faces.angry.brows[2] }))
    assert.is_true(inner_lower({ faces.angry.brows[4], faces.angry.brows[3] }))
    local mouth = faces.angry.mouth
    local middle, corner = mouth[1], mouth[2]
    assert.is_true(centre_y(corner) < centre_y(middle))
  end)
end)

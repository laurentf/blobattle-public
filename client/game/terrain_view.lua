local buffers = require("render.buffers")
local materials = require("render.materials")
local voxel_mesh = require("render.voxel_mesh")

local M = {}

local generation = 0

local MATERIALS_FORMAT = { { name = hash("class"), type = buffer.VALUE_TYPE_UINT8, count = 1 } }
local FOG_HEIGHT = 70

local function paint(view, t, look)
  local started = socket.gettime()
  local buf = buffer.create(t.width * t.height, MATERIALS_FORMAT)
  materials.fill(t, buffer.get_stream(buf, hash("class")))
  view.texture_path = "/materials_" .. generation .. ".texturec"
  view.texture = resource.create_texture(view.texture_path, {
    type = graphics.TEXTURE_TYPE_2D,
    width = t.width,
    height = t.height,
    format = graphics.TEXTURE_FORMAT_LUMINANCE,
  }, buf)
  view.colours = {}
  for i, name in ipairs(materials.CONSTANTS) do
    local c = look[name]
    view.colours[i] = { name = name, value = vmath.vector4(c[1], c[2], c[3], 1) }
  end
  view.map_size = vmath.vector4(t.width, t.height, 0, 0)
  local fog = look.fog or { 0, 0, 0, 0 }
  view.fog = vmath.vector4(fog[1], fog[2], fog[3], fog[4])
  view.height = t.height
  view.fog_band = vmath.vector4(t.height - view.liquid, FOG_HEIGHT, 0, 0)
  view.paint_ms = (socket.gettime() - started) * 1000
end

local function upload(view, i)
  local buf, n = buffers.assemble(voxel_mesh.parts(view.mesh.chunks[i]))
  local path = view.paths[i]
  if path then
    resource.set_buffer(path, buf)
  else
    path = "/terrain_" .. generation .. "_" .. i .. ".bufferc"
    local res = resource.create_buffer(path, { buffer = buf })
    local id = factory.create(view.factory)
    local mesh = msg.url(nil, id, "mesh")
    go.set(mesh, "vertices", res)
    view.meshes[i] = mesh
    go.set(mesh, "texture0", view.texture)
    go.set(mesh, "map_size", view.map_size)
    go.set(mesh, "fog", view.fog)
    go.set(mesh, "fog_band", view.fog_band)
    for _, c in ipairs(view.colours) do
      go.set(mesh, c.name, c.value)
    end
    view.paths[i], view.objects[i] = path, id
  end
  view.vertices[i] = n
end

function M.new(t, fields)
  generation = generation + 1
  local view = {
    liquid = fields.liquid.level,
    mesh = voxel_mesh.new(t, { seal = buffers.seal }),
    factory = fields.factory,
    paths = {},
    objects = {},
    meshes = {},
    vertices = {},
    uploads = {},
    part_ms = 0.5,
    upload_ms = 0.5,
    slices = 0,
  }
  paint(view, t, materials.look(fields.liquid))
  voxel_mesh.build_all(view.mesh)
  for i = 1, #view.mesh.chunks do
    upload(view, i)
  end
  return view
end

local function mark(view, kind)
  if view.since == nil then
    view.since, view.kind, view.slices = socket.gettime(), kind, 0
  elseif kind == "crack" then
    view.kind = kind
  end
end

function M.crater(view, blast)
  mark(view, "crater")
  voxel_mesh.crater(view.mesh, blast)
end

function M.region(view, area, kind)
  mark(view, kind)
  voxel_mesh.region(view.mesh, area)
end

local DECAY = 0.95

local function learn(view, key, spent, limit_ms)
  view[key] = math.min(limit_ms, math.max(view[key] * DECAY, spent))
end

function M.rebuild(view, limit_ms)
  local queue = view.uploads
  if #queue == 0 and not voxel_mesh.busy(view.mesh) then
    return nil
  end
  local started = os.clock()
  local worked = false
  while #queue > 0 do
    local before = os.clock()
    if worked and (before - started) * 1000 + view.upload_ms > limit_ms then
      break
    end
    upload(view, table.remove(queue, 1))
    learn(view, "upload_ms", (os.clock() - before) * 1000, limit_ms)
    worked = true
  end
  local last = nil
  local done = voxel_mesh.rebuild(view.mesh, function()
    local now = os.clock()
    if last then
      learn(view, "part_ms", (now - last) * 1000, limit_ms)
    end
    last = now
    if not worked then
      worked = true
      return true
    end
    return (now - started) * 1000 + view.part_ms <= limit_ms
  end)
  for _, i in ipairs(done) do
    queue[#queue + 1] = i
  end
  view.slices = view.slices + 1
  if #queue == 0 and not voxel_mesh.busy(view.mesh) and view.since then
    view.finished, view.finished_kind = socket.gettime() - view.since, view.kind
    view.finished_slices, view.since, view.slices = view.slices, nil, 0
  end
  return (os.clock() - started) * 1000
end

function M.finished(view)
  local seconds = view.finished
  view.finished = nil
  return seconds, view.finished_kind, view.finished_slices
end

function M.vertex_count(view)
  local total = 0
  for _, n in ipairs(view.vertices) do
    total = total + n
  end
  return total
end

function M.set_liquid(view, level)
  view.fog_band.x = view.height - level
  for _, mesh in ipairs(view.meshes) do
    go.set(mesh, "fog_band", view.fog_band)
  end
end

function M.destroy(view)
  for i, id in ipairs(view.objects) do
    go.delete(id)
    resource.release(view.paths[i])
  end
  resource.release(view.texture_path)
end

return M

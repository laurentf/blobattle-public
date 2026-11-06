local buffers = require("render.buffers")
local faces = require("render.faces")
local shapes = require("render.shapes")

local M = {}

local generation = 0

function M.new()
  generation = generation + 1
  return { generation = generation, resources = {} }
end

local function build(name)
  local face = name:match("^face_(%a+)$")
  if face then
    return shapes.face(faces[face])
  end
  return shapes[name]()
end

function M.get(set, name)
  local res = set.resources[name]
  if res == nil then
    local part = buffers.seal(build(name))
    local path = "/model_" .. set.generation .. "_" .. name .. ".bufferc"
    res = resource.create_buffer(path, { buffer = part.buf })
    set.resources[name] = res
  end
  return res
end

function M.release(set)
  for _, path in pairs(set.resources) do
    resource.release(path)
  end
  set.resources = {}
end

return M

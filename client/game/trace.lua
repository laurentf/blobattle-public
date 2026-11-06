local M = {}

M.EVERY = 30
M.KEEP = 40

local MODULUS = 2147483647
local FACTOR = 1000003
local FIELDS = {
  "team",
  "cat",
  "kind",
  "direction",
  "weapon",
  "angle",
  "power",
  "fuse",
  "x",
  "y",
  "radius",
  "amount",
  "cause",
  "winner",
  "level",
  "wind",
  "projectile",
  "n",
  "width",
  "top",
}

function M.new()
  return { digest = 0, checkpoints = {}, counts = {} }
end

local function mix(t, value)
  if type(value) == "string" then
    for i = 1, #value do
      t.digest = (t.digest * FACTOR + value:byte(i)) % MODULUS
    end
    return
  end
  if type(value) == "boolean" then
    value = value and 1 or 2
  end
  t.digest = (t.digest * FACTOR + (value or 0) % MODULUS) % MODULUS
end

local function record(t, fields)
  mix(t, fields.type or fields.kind)
  for _, key in ipairs(FIELDS) do
    mix(t, fields[key])
  end
end

local function count(t, key)
  t.counts[key] = (t.counts[key] or 0) + 1
end

local function count_input(t, input)
  if input.kind == "move" then
    if input.direction ~= 0 then
      count(t, "walk")
    end
  elseif input.kind == "fire" then
    count(t, "fire:" .. input.weapon)
  else
    count(t, input.kind)
  end
end

local function count_event(t, e)
  if e.type == "damaged" then
    count(t, "damaged:" .. e.cause)
  elseif e.type ~= "turn_started" and e.type ~= "turn_ended" and e.type ~= "landed" then
    count(t, e.type)
  end
end

function M.step(t, tick, inputs, events, active)
  local ended = false
  mix(t, tick)
  for _, input in ipairs(inputs or {}) do
    record(t, input)
    count_input(t, input)
  end
  for _, e in ipairs(events) do
    record(t, e)
    count_event(t, e)
    ended = ended or e.type == "game_ended"
  end
  if active then
    mix(t, active.x)
    mix(t, active.y)
  end
  if tick % M.EVERY == 0 or ended then
    local list = t.checkpoints
    if #list == M.KEEP then
      table.remove(list, 1)
    end
    list[#list + 1] = { tick = tick, sum = t.digest }
  end
end

function M.face(t, tick, cat, face)
  mix(t, tick)
  mix(t, cat)
  mix(t, face)
  count(t, "face:" .. face)
end

return M

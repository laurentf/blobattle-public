local cat = require("shared.sim.cat")

local M = {}

M.SECONDS = 2
M.SCARE_RADII = 3
M.MUNCH_HOLD = 0.2
M.MUNCH_RATE = 8

function M.new()
  return {}
end

local function feel(m, id, face, until_time, onsets)
  local mood = m[id]
  if mood == nil then
    mood = {}
    m[id] = mood
  end
  mood.face, mood.until_time = face, until_time
  if onsets then
    onsets[#onsets + 1] = { id = id, face = face }
  end
end

local function angry(m, id, now)
  local mood = m[id]
  return mood ~= nil and mood.face == "angry" and now < mood.until_time
end

local function scare(m, w, e, now, onsets)
  local reach = M.SCARE_RADII * e.radius
  for _, c in ipairs(w.cats) do
    if c.alive and not angry(m, c.id, now) then
      local cx, cy = cat.center(c)
      local dx, dy = cx - e.x, cy - e.y
      if dx * dx + dy * dy <= reach * reach then
        feel(m, c.id, "scared", now + M.SECONDS, onsets)
      end
    end
  end
end

function M.react(m, events, fields)
  local now, onsets = fields.now, fields.onsets
  for _, e in ipairs(events) do
    if e.type == "damaged" and e.amount > 0 then
      feel(m, e.cat, "angry", now + M.SECONDS, onsets)
    elseif e.type == "chomped" then
      feel(m, e.cat, "munch", now + M.MUNCH_HOLD, onsets)
    elseif e.type == "exploded" then
      scare(m, fields.world, e, now, onsets)
    end
  end
end

function M.face(m, id, now)
  local mood = m[id]
  if mood == nil or now >= mood.until_time then
    return "calm"
  end
  if mood.face == "munch" and math.floor(now * M.MUNCH_RATE) % 2 == 1 then
    return "chew"
  end
  return mood.face
end

return M

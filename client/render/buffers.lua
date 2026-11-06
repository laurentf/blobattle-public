local M = {}

local POSITION, NORMAL = hash("position"), hash("normal")
local FORMAT = {
  { name = POSITION, type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
  { name = NORMAL, type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
}

function M.seal(part)
  local n = part.n
  local buf = buffer.create(math.max(n, 1), FORMAT)
  local ps, ns = buffer.get_stream(buf, POSITION), buffer.get_stream(buf, NORMAL)
  local pos, nrm = part.pos, part.nrm
  for i = 1, n * 3 do
    ps[i] = pos[i]
    ns[i] = nrm[i]
  end
  return { n = n, ps = ps, ns = ns, buf = buf }
end

function M.assemble(parts)
  local total = 0
  for _, part in ipairs(parts) do
    total = total + part.n
  end
  local buf = buffer.create(math.max(total, 3), FORMAT)
  local ps, ns = buffer.get_stream(buf, POSITION), buffer.get_stream(buf, NORMAL)
  local offset = 0
  for _, part in ipairs(parts) do
    if part.n > 0 then
      buffer.copy_stream(ps, offset, part.ps, 0, part.n * 3)
      buffer.copy_stream(ns, offset, part.ns, 0, part.n * 3)
      offset = offset + part.n * 3
    end
  end
  if total == 0 then
    for k = 1, 9 do
      ps[k] = 0
      ns[k] = 1
    end
  end
  return buf, total
end

return M

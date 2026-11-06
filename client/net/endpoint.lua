local protocol = require("shared.protocol")

local M = {}

M.TLS_PORT = 443

function M.resolve(fields)
  local host = fields.hostname
  if host == nil or host == "" then
    host = fields.host
  end
  if fields.protocol ~= "https:" then
    return { host = host, port = fields.port, ssl = false }
  end
  return { host = host, port = tonumber(fields.page_port or "") or M.TLS_PORT, ssl = true }
end

function M.room_param(search)
  local code = (search or ""):match("[?&]room=(%w+)")
  if code == nil then
    return nil
  end
  code = code:upper()
  if not protocol.valid_code(code) then
    return nil
  end
  return code
end

function M.room_link(fields)
  return fields.origin .. fields.pathname .. "?room=" .. fields.code
end

return M

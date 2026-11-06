local defold = require("nakama.engine.defold")
local endpoint = require("net.endpoint")
local link = require("net.link")
local nakama = require("nakama.nakama")

local M = {}

local function page()
  if not html5 then
    return {}
  end
  return json.decode(
    html5.run(
      "JSON.stringify({ hostname: location.hostname, protocol: location.protocol, "
        .. "port: location.port })"
    )
  )
end

function M.new(profile)
  local where = page()
  return link.new({
    nakama = nakama,
    engine = defold,
    endpoint = endpoint.resolve({
      hostname = where.hostname,
      protocol = where.protocol,
      page_port = where.port,
      host = sys.get_config_string("nakama.host", "127.0.0.1"),
      port = sys.get_config_int("nakama.port", 7550),
    }),
    server_key = sys.get_config_string("nakama.server_key", ""),
    json = json,
    after = function(seconds, fn)
      timer.delay(seconds, false, function()
        fn()
      end)
    end,
    clock = socket.gettime,
    disconnect = function(s)
      if s.connection then
        websocket.disconnect(s.connection)
      end
    end,
    profile = profile,
  })
end

return M

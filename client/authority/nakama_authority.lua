local link = require("net.link")
local protocol = require("shared.protocol")

local M = {}

function M.new(fields)
  local self = {}
  local l = fields.link
  local messages, spare = {}, {}
  local me, stopped = nil, false

  local function clear(list)
    for i = #list, 1, -1 do
      list[i] = nil
    end
  end

  function self.start() end

  function self.update(_) end

  function self.send(name, body)
    if stopped then
      return
    end
    local op = protocol.OPS[name]
    if op == nil or protocol.CLIENT_OPS[op] == nil then
      messages[#messages + 1] = { name = "refused", data = { code = "unknown_op" } }
      return
    end
    link.send(l, name, body)
  end

  function self.poll()
    clear(spare)
    local out = messages
    messages, spare = spare, out
    if stopped then
      clear(out)
      return out
    end
    for _, m in ipairs(link.game_messages(l)) do
      if m.name == "game_start" then
        me = nil
        for _, entry in ipairs(m.data.roster or {}) do
          if entry.user == l.user_id then
            me = entry.team
          end
        end
      end
      out[#out + 1] = m
    end
    return out
  end

  function self.team()
    return me
  end

  function self.stop()
    stopped = true
  end

  return self
end

return M

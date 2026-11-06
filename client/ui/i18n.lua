local catalogue = require("shared.i18n.en")

local M = {}

function M.t(id)
  local text = catalogue[id]
  if text == nil then
    error("no text for " .. id)
  end
  return text
end

function M.format(id, params)
  return (
    M.t(id):gsub("{(%w+)}", function(key)
      local value = params[key]
      if value == nil then
        error("no value for {" .. key .. "} in " .. id)
      end
      return tostring(value)
    end)
  )
end

function M.has(id)
  return catalogue[id] ~= nil
end

return M

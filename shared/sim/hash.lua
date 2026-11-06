local fixed = require("shared.sim.fixed")

local M = {}

M.MODULUS = 2147483647
M.MULTIPLIERS = { 31, 131 }

function M.new()
  return { a = 7, b = 11 }
end

function M.add(h, value)
  local x = fixed.mod(value, M.MODULUS)
  h.a = fixed.mod(h.a * M.MULTIPLIERS[1] + x, M.MODULUS)
  h.b = fixed.mod(h.b * M.MULTIPLIERS[2] + x, M.MODULUS)
  return h
end

function M.digest(h)
  return h.a, h.b
end

return M

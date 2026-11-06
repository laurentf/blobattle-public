local fixed = require("shared.sim.fixed")

local M = {}

M.MODULUS = 2147483647
M.MAX_SEED = 2147483646

M.STREAMS = {
  map = { multiplier = 48271, offset = 0 },
  sim = { multiplier = 69621, offset = 1000003 },
  bots = { multiplier = 16807, offset = 2000006 },
  names = { multiplier = 39373, offset = 3000009 },
}

local function check_seed(seed)
  if type(seed) ~= "number" or seed < 1 or seed > M.MAX_SEED or fixed.mod(seed, 1) ~= 0 then
    error("a seed is an integer from 1 to 2147483646")
  end
end

local function state_of(seed, offset)
  return fixed.mod(seed - 1 + offset, M.MODULUS - 1) + 1
end

function M.new(seed, multiplier)
  check_seed(seed)
  return { state = state_of(seed, 0), multiplier = multiplier }
end

function M.stream(seed, name)
  local spec = M.STREAMS[name]
  if spec == nil then
    error("unknown random stream: " .. name)
  end
  check_seed(seed)
  return { state = state_of(seed, spec.offset), multiplier = spec.multiplier }
end

function M.next(stream)
  stream.state = fixed.mod(stream.state * stream.multiplier, M.MODULUS)
  return stream.state
end

function M.range(stream, low, high)
  if high < low then
    error("an empty random range")
  end
  return low + fixed.mod(M.next(stream), high - low + 1)
end

return M

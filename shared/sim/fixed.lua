local floor = math.floor

local M = {}

M.FP = 256

local function nonzero(b)
  if b == 0 then
    error("division by zero")
  end
end

local function positive_zero(v)
  if v == 0 then
    return 0
  end
  return v
end

function M.div(a, b)
  nonzero(b)
  return positive_zero(floor(a / b))
end

function M.mod(a, b)
  nonzero(b)
  return positive_zero(a - floor(a / b) * b)
end

function M.round_div(a, b)
  nonzero(b)
  if b < 0 then
    a, b = -a, -b
  end
  local half = floor(b / 2)
  if a >= 0 then
    return positive_zero(floor((a + half) / b))
  end
  return positive_zero(0 - floor((half - a) / b))
end

function M.mul(a, b)
  return positive_zero(floor(a * b / M.FP))
end

function M.isqrt(n)
  if n < 0 then
    error("isqrt of a negative number")
  end
  if n < 2 then
    return n
  end
  local x = 1
  while x <= floor(n / x) do
    x = x * 2
  end
  while true do
    local y = floor((x + floor(n / x)) / 2)
    if y >= x then
      return x
    end
    x = y
  end
end

function M.clamp(value, low, high)
  if value < low then
    return low
  end
  if value > high then
    return high
  end
  return value
end

function M.sign(value)
  if value > 0 then
    return 1
  end
  if value < 0 then
    return -1
  end
  return 0
end

function M.abs(value)
  if value < 0 then
    return -value
  end
  return value
end

return M

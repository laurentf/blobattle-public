local M = {}

local floor = math.floor
local TWO32 = 4294967296
local MODP = 2147483647

function M.rng_new(seed)
	local s = seed % MODP
	if s <= 0 then s = s + MODP - 1 end
	return { s = s }
end

function M.rng_next(r)
	r.s = (r.s * 48271) % MODP
	return r.s
end

function M.rng_range(r, n)
	return M.rng_next(r) % n
end

local function mix(chk, v)
	return (chk * 31 + v % TWO32) % TWO32
end

function M.projectile_fixed(seed, steps)
	local r = M.rng_new(seed)
	local FP = 65536
	local x, y = 100 * FP, 600 * FP
	local vx = (M.rng_range(r, 2001) - 1000) * 64
	local vy = M.rng_range(r, 2001) * 96
	local g = -12288
	local wind = M.rng_range(r, 201) - 100
	local chk = 0
	for i = 1, steps do
		if i % 100 == 0 then
			wind = M.rng_range(r, 201) - 100
		end
		vx = vx + wind
		vy = vy + g
		vx = vx - floor(vx * 3 / 1024)
		vy = vy - floor(vy * 3 / 1024)
		x = x + vx
		y = y + vy
		if y < 0 then
			y = -y
			vy = -floor(vy * 3 / 4)
		end
		chk = mix(chk, x + 2 * y)
	end
	return chk, x, y
end

function M.projectile_float(seed, steps)
	local r = M.rng_new(seed)
	local x, y = 100.0, 600.0
	local vx = (M.rng_range(r, 2001) - 1000) / 1024
	local vy = M.rng_range(r, 2001) / 683
	local g = -0.1875
	local wind = (M.rng_range(r, 201) - 100) / 65536
	local chk = 0
	for i = 1, steps do
		if i % 100 == 0 then
			wind = (M.rng_range(r, 201) - 100) / 65536
		end
		vx = (vx + wind) * 0.99707
		vy = (vy + g) * 0.99707
		x = x + vx
		y = y + vy
		if y < 0 then
			y = -y
			vy = -vy * 0.75
		end
		chk = mix(chk, floor(x * 1048576) + floor(y * 1048576))
	end
	return chk, x, y
end

function M.trig(n)
	local chk = 0
	local s = 0
	for i = 1, n do
		local a = i * 0.0123
		local v = math.sin(a) + math.cos(a) * 0.5 + math.atan2(a, 1.7) + math.sqrt(a) + math.exp(-a * 0.01) + math.log(a + 1)
		s = s + v
		chk = mix(chk, floor(v * 4503599627370496 / 4096))
	end
	return chk, s
end

function M.bitops()
	local have = {}
	have.bit = type(bit) == "table"
	have.bit32 = type(bit32) == "table"
	local b = (have.bit and bit) or (have.bit32 and bit32)
	if not b then
		return have, nil
	end
	local x = 2463534242
	local chk = 0
	for _ = 1, 1000 do
		x = b.bxor(x, b.lshift(x, 13))
		x = b.bxor(x, b.rshift(x, 17))
		x = b.bxor(x, b.lshift(x, 5))
		x = x % TWO32
		chk = mix(chk, x)
	end
	have.raw_lshift = b.lshift(0xFFFFFFFF, 4)
	return have, chk
end

function M.run()
	local res = {}
	res.version = _VERSION
	res.jit = type(jit) == "table" and jit.version or false
	res.fixed = string.format("%.0f", (M.projectile_fixed(12345, 1000)))
	res.float = string.format("%.0f", (M.projectile_float(12345, 1000)))
	local _, fx, fy = M.projectile_float(12345, 1000)
	res.float_xy = string.format("%.17g,%.17g", fx, fy)
	local tchk, ts = M.trig(1000)
	res.trig = string.format("%.0f", tchk)
	res.trig_sum = string.format("%.17g", ts)
	local have, bchk = M.bitops()
	res.has_bit = have.bit
	res.has_bit32 = have.bit32
	res.bit_raw_lshift = have.raw_lshift and string.format("%.0f", have.raw_lshift) or "n/a"
	res.xorshift = bchk and string.format("%.0f", bchk) or "n/a"
	return res
end

function M.bench(steps)
	return (M.projectile_fixed(777, steps))
end

return M

local probe = require("shared.sim.probe")

local M = {}

local floor = math.floor

local function octave(heights, w, r, step, lo, span)
	local pts = {}
	for i = 0, floor(w / step) + 1 do
		pts[i] = lo + probe.rng_range(r, span)
	end
	local s3 = step * step * step
	for x = 0, w - 1 do
		local i = floor(x / step)
		local f = x - i * step
		local num = f * f * (3 * step - 2 * f)
		heights[x] = heights[x] + pts[i] + floor((pts[i + 1] - pts[i]) * num / s3)
	end
end

function M.heights(w, h, seed)
	local r = probe.rng_new(seed)
	local heights = {}
	for x = 0, w - 1 do heights[x] = 0 end
	octave(heights, w, r, floor(w / 8), floor(h * 0.20), floor(h * 0.40))
	octave(heights, w, r, floor(w / 64), 0, floor(h * 0.08))
	return heights
end

function M.craters(w, h, heights, seed, n, radius)
	local r = probe.rng_new(seed)
	local list = {}
	for i = 1, n do
		local x = radius + probe.rng_range(r, w - 2 * radius)
		local y = heights[x] - probe.rng_range(r, radius)
		if y < radius then y = radius end
		list[i] = { x = x, y = y }
	end
	return list
end

return M

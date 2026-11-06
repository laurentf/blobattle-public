local gen = require("shared.sim.terrain_gen")
local bitgrid = require("shared.sim.bitgrid")

local M = {}

M.SEED = 4242
M.CRATER_SEED = 99
M.CRATERS = 50
M.RADIUS = 40

function M.run(w, h, clock, lookups)
	lookups = lookups or 200000
	local res = { w = w, h = h }
	local t0 = clock()
	local heights = gen.heights(w, h, M.SEED)
	local t1 = clock()
	local g = bitgrid.from_heights(w, h, heights)
	local t2 = clock()
	res.heights_ms = (t1 - t0) * 1000
	res.grid_build_ms = (t2 - t1) * 1000
	res.grid_chk_before = string.format("%.0f", bitgrid.checksum(g))
	local craters = gen.craters(w, h, heights, M.CRATER_SEED, M.CRATERS, M.RADIUS)
	local t3 = clock()
	for i = 1, #craters do
		bitgrid.carve(g, craters[i].x, craters[i].y, M.RADIUS)
	end
	local t4 = clock()
	res.grid_carve_avg_ms = (t4 - t3) * 1000 / #craters
	res.grid_chk_after = string.format("%.0f", bitgrid.checksum(g))
	local s = 12345
	local t5 = clock()
	for _ = 1, lookups do
		s = (s * 48271) % 2147483647
		local x = s % w
		local y = (s * 7) % h
	end
	local t6 = clock()
	local solid = 0
	local get = bitgrid.get
	for _ = 1, lookups do
		s = (s * 48271) % 2147483647
		local x = s % w
		local y = (s * 7) % h
		if get(g, x, y) then solid = solid + 1 end
	end
	local t7 = clock()
	res.lookup_ns = (((t7 - t6) - (t6 - t5)) * 1e9) / lookups
	res.lookup_solid = solid
	return res, g, heights, craters
end

return M

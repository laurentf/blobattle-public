local gen = require("shared.sim.terrain_gen")
local bitgrid = require("shared.sim.bitgrid")

local M = {}

function M.run(w, h, clock, n)
	local heights = gen.heights(w, h, 4242)
	local res = { w = w, h = h, n = n }
	local g = bitgrid.from_heights(w, h, heights)
	local t0 = clock()
	local tbl = {}
	local idx = 1
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			tbl[idx] = heights[x] > y and 1 or 0
			idx = idx + 1
		end
	end
	local t1 = clock()
	res.table_build_ms = (t1 - t0) * 1000
	local rows = {}
	local chars = {}
	for y = 0, h - 1 do
		local parts = {}
		for x0 = 0, w - 1, 64 do
			for i = 1, 64 do
				local x = x0 + i - 1
				chars[i] = (x < w and heights[x] > y) and "\1" or ""
				if x < w and heights[x] <= y then chars[i] = "\0" end
			end
			parts[#parts + 1] = table.concat(chars)
		end
		rows[y] = table.concat(parts)
	end
	local t2 = clock()
	res.strings_build_ms = (t2 - t1) * 1000
	local byte = string.byte
	local get = bitgrid.get
	local function loop(kind)
		local s = 12345
		local hits = 0
		local a = clock()
		if kind == 0 then
			for _ = 1, n do
				s = (s * 48271) % 2147483647
				local x = s % w
				local y = (s * 7) % h
			end
		elseif kind == 1 then
			for _ = 1, n do
				s = (s * 48271) % 2147483647
				local x = s % w
				local y = (s * 7) % h
				if tbl[y * w + x + 1] == 1 then hits = hits + 1 end
			end
		elseif kind == 2 then
			for _ = 1, n do
				s = (s * 48271) % 2147483647
				local x = s % w
				local y = (s * 7) % h
				if byte(rows[y], x + 1) == 1 then hits = hits + 1 end
			end
		else
			for _ = 1, n do
				s = (s * 48271) % 2147483647
				local x = s % w
				local y = (s * 7) % h
				if get(g, x, y) then hits = hits + 1 end
			end
		end
		return (clock() - a), hits
	end
	local base = loop(0)
	local tt, h1 = loop(1)
	local ts, h2 = loop(2)
	local tg, h3 = loop(3)
	res.base_ns = base * 1e9 / n
	res.table_ns = (tt - base) * 1e9 / n
	res.string_ns = (ts - base) * 1e9 / n
	res.grid_ns = (tg - base) * 1e9 / n
	res.hits_agree = (h1 == h2 and h2 == h3)
	return res
end

return M

-- Throwaway prototype: one voxel per sim cell, extruded into a slab.
-- A chunk keeps its geometry per row (front, top and bottom faces) and per column (side faces),
-- so a crater only recomputes the rows and columns it touches.
local M = {}

local POSITION, NORMAL = hash("position"), hash("normal")
-- a front face whose normal leans up by this much is drawn in the rim colour by the shader
local RIM_NY, RIM_NZ = 0.05, 0.9987

function M.new_chunk(x0, x1)
	return { x0 = x0, x1 = x1, rows = {}, cols = {} }
end

local function writer()
	local w = { pos = {}, nrm = {}, n = 0 }
	function w.quad(ax, ay, az, bx, by, bz, cx, cy, cz, dx, dy, dz, nx, ny, nz)
		local pos, nrm, i = w.pos, w.nrm, w.n * 3
		pos[i + 1], pos[i + 2], pos[i + 3] = ax, ay, az
		pos[i + 4], pos[i + 5], pos[i + 6] = bx, by, bz
		pos[i + 7], pos[i + 8], pos[i + 9] = cx, cy, cz
		pos[i + 10], pos[i + 11], pos[i + 12] = ax, ay, az
		pos[i + 13], pos[i + 14], pos[i + 15] = cx, cy, cz
		pos[i + 16], pos[i + 17], pos[i + 18] = dx, dy, dz
		for k = 1, 18, 3 do
			nrm[i + k], nrm[i + k + 1], nrm[i + k + 2] = nx, ny, nz
		end
		w.n = w.n + 6
	end
	function w.seal()
		local n = w.n
		local buf = buffer.create(math.max(n, 1), {
			{ name = POSITION, type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
			{ name = NORMAL, type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
		})
		local ps, ns = buffer.get_stream(buf, POSITION), buffer.get_stream(buf, NORMAL)
		local pos, nrm = w.pos, w.nrm
		for i = 1, n * 3 do
			ps[i] = pos[i]
			ns[i] = nrm[i]
		end
		return { ps = ps, ns = ns, n = n, buf = buf }
	end
	return w
end

local function build_row(chunk, t, y, dz)
	local W, H, cells = t.width, t.height, t.cells
	local x0, x1 = chunk.x0, chunk.x1
	local out = writer()
	local base = y * W + 1
	local function solid(x, yy)
		if yy < 0 then
			return false
		end
		if yy >= H then
			return true
		end
		return cells[yy * W + x + 1] ~= 0
	end
	local top, bottom = H - y, H - y - 1
	-- front faces, in runs of the same kind (rim when air is at most two cells above)
	local x = x0
	while x < x1 do
		if cells[base + x] ~= 0 then
			local rim = not solid(x, y - 1) or not solid(x, y - 2)
			local s = x
			x = x + 1
			while x < x1 and cells[base + x] ~= 0 and (not solid(x, y - 1) or not solid(x, y - 2)) == rim do
				x = x + 1
			end
			local ny, nz = 0, 1
			if rim then
				ny, nz = RIM_NY, RIM_NZ
			end
			out.quad(s, bottom, dz, x, bottom, dz, x, top, dz, s, top, dz, 0, ny, nz)
		else
			x = x + 1
		end
	end
	-- top faces (air above) and bottom faces (air below)
	x = x0
	while x < x1 do
		if cells[base + x] ~= 0 and not solid(x, y - 1) then
			local s = x
			x = x + 1
			while x < x1 and cells[base + x] ~= 0 and not solid(x, y - 1) do
				x = x + 1
			end
			out.quad(s, top, dz, x, top, dz, x, top, -dz, s, top, -dz, 0, 1, 0)
		else
			x = x + 1
		end
	end
	x = x0
	while x < x1 do
		if cells[base + x] ~= 0 and not solid(x, y + 1) then
			local s = x
			x = x + 1
			while x < x1 and cells[base + x] ~= 0 and not solid(x, y + 1) do
				x = x + 1
			end
			out.quad(s, bottom, -dz, x, bottom, -dz, x, bottom, dz, s, bottom, dz, 0, -1, 0)
		else
			x = x + 1
		end
	end
	chunk.rows[y + 1] = out.seal()
end

local function build_col(chunk, t, x, dz)
	local W, H, cells = t.width, t.height, t.cells
	local out = writer()
	local function solid(xx, yy)
		if xx < 0 or xx >= W then
			return false
		end
		return cells[yy * W + xx + 1] ~= 0
	end
	for side = -1, 1, 2 do
		local y = 0
		local fx = side < 0 and x or x + 1
		while y < H do
			if solid(x, y) and not solid(x + side, y) then
				local s = y
				y = y + 1
				while y < H and solid(x, y) and not solid(x + side, y) do
					y = y + 1
				end
				local hi, lo = H - s, H - y
				if side < 0 then
					out.quad(fx, lo, -dz, fx, lo, dz, fx, hi, dz, fx, hi, -dz, -1, 0, 0)
				else
					out.quad(fx, lo, dz, fx, lo, -dz, fx, hi, -dz, fx, hi, dz, 1, 0, 0)
				end
			else
				y = y + 1
			end
		end
	end
	chunk.cols[x - chunk.x0 + 1] = out.seal()
end

function M.build_row(chunk, t, y, dz)
	if y >= 0 and y < t.height then
		build_row(chunk, t, y, dz)
	end
end

function M.build_col(chunk, t, x, dz)
	if x >= chunk.x0 and x < chunk.x1 then
		build_col(chunk, t, x, dz)
	end
end

function M.build_all(chunk, t, dz)
	for y = 0, t.height - 1 do
		build_row(chunk, t, y, dz)
	end
	for x = chunk.x0, chunk.x1 - 1 do
		build_col(chunk, t, x, dz)
	end
end

function M.to_buffer(chunk)
	local total = 0
	for _, part in pairs(chunk.rows) do
		total = total + part.n
	end
	for _, part in pairs(chunk.cols) do
		total = total + part.n
	end
	local buf = buffer.create(math.max(total, 3), {
		{ name = POSITION, type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
		{ name = NORMAL, type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
	})
	local ps, ns = buffer.get_stream(buf, POSITION), buffer.get_stream(buf, NORMAL)
	local i3 = 0
	for _, list in ipairs({ chunk.rows, chunk.cols }) do
		for _, part in pairs(list) do
			if part.n > 0 then
				buffer.copy_stream(ps, i3, part.ps, 0, part.n * 3)
				buffer.copy_stream(ns, i3, part.ns, 0, part.n * 3)
				i3 = i3 + part.n * 3
			end
		end
	end
	if total == 0 then
		for k = 1, 9 do
			ps[k] = 0
			ns[k] = 1
		end
	end
	return buf, total
end

return M

-- Throwaway prototype: marching squares over the sim cells, extruded into a slab.
-- A chunk keeps its geometry per row of squares, so a crater only recomputes the rows it touches.
local M = {}

local POSITION, NORMAL = hash("position"), hash("normal")

-- corners: TL = 8, TR = 4, BR = 2, BL = 1; points: 1 BL, 2 BR, 3 TR, 4 TL, 5 B, 6 R, 7 T, 8 L
local POLYS = {
	[1] = { { 1, 5, 8 } },
	[2] = { { 5, 2, 6 } },
	[3] = { { 1, 2, 6, 8 } },
	[4] = { { 6, 3, 7 } },
	[5] = { { 1, 5, 8 }, { 6, 3, 7 } },
	[6] = { { 5, 2, 3, 7 } },
	[7] = { { 1, 2, 3, 7, 8 } },
	[8] = { { 8, 7, 4 } },
	[9] = { { 1, 5, 7, 4 } },
	[10] = { { 5, 2, 6 }, { 8, 7, 4 } },
	[11] = { { 1, 2, 6, 7, 4 } },
	[12] = { { 8, 6, 3, 4 } },
	[13] = { { 1, 5, 6, 3, 4 } },
	[14] = { { 8, 5, 2, 3, 4 } },
}
local PX = { 0, 1, 1, 0, 0.5, 1, 0.5, 0 }
local PY = { 0, 0, 1, 1, 0, 0.5, 1, 0.5 }

function M.new_chunk(x0, x1)
	return { x0 = x0, x1 = x1, rows = {} }
end

local function build_row(chunk, t, y, dz, pal)
	local W, H, cells = t.width, t.height, t.cells
	local pos, nrm = {}, {}
	local n = 0
	local function vert(x, yy, z, nx, ny, nz)
		local i = n * 3
		pos[i + 1], pos[i + 2], pos[i + 3] = x, yy, z
		nrm[i + 1], nrm[i + 2], nrm[i + 3] = nx, ny, nz
		n = n + 1
	end
	local x_lo, x_hi = chunk.x0 - 1, chunk.x1
	-- the samples of one row over the chunk's columns, indexed x + 2
	local function samples(yy)
		local out = {}
		if yy < 0 then
			for x = x_lo, x_hi do
				out[x + 2] = 0
			end
			return out
		end
		local base = yy * W + 1
		for x = x_lo, x_hi do
			if x < 0 or x >= W then
				out[x + 2] = 0
			elseif yy >= H then
				out[x + 2] = 1
			else
				out[x + 2] = cells[base + x] ~= 0 and 1 or 0
			end
		end
		return out
	end
	-- the square between sample rows y (top) and y + 1 (bottom), sample centres at cell centres
	local top, bottom = H - y - 0.5, H - y - 1.5
	local run = nil
	local function flush_run(x)
		if run then
			vert(run + 0.5, bottom, dz, 0, 0, 1)
			vert(x + 0.5, bottom, dz, 0, 0, 1)
			vert(x + 0.5, top, dz, 0, 0, 1)
			vert(run + 0.5, bottom, dz, 0, 0, 1)
			vert(x + 0.5, top, dz, 0, 0, 1)
			vert(run + 0.5, top, dz, 0, 0, 1)
			run = nil
		end
	end
	local wall_y = bottom + 0.5
	local up, down = nil, nil
	local function wall(px, py, qx, qy, nx, ny)
		vert(px, py, -dz, nx, ny, 0)
		vert(qx, qy, -dz, nx, ny, 0)
		vert(qx, qy, dz, nx, ny, 0)
		vert(px, py, -dz, nx, ny, 0)
		vert(qx, qy, dz, nx, ny, 0)
		vert(px, py, dz, nx, ny, 0)
	end
	local function flush_walls()
		if up then
			wall(up[2], wall_y, up[1], wall_y, 0, 1)
			up = nil
		end
		if down then
			wall(down[1], wall_y, down[2], wall_y, 0, -1)
			down = nil
		end
	end
	local x_first, x_last = chunk.x0, chunk.x1 - 1
	if x_first == 0 then
		x_first = -1
	end
	local above, row_top, row_bottom = samples(y - 1), samples(y), samples(y + 1)
	for x = x_first, x_last do
		local tl, tr = row_top[x + 2], row_top[x + 3]
		local bl, br = row_bottom[x + 2], row_bottom[x + 3]
		local case = tl * 8 + tr * 4 + br * 2 + bl
		local rim = tl + tr < 2 or above[x + 2] + above[x + 3] < 2
		if case == 15 and not rim then
			run = run or x
		else
			flush_run(x)
			local polys = POLYS[case] or (case == 15 and { { 1, 2, 3, 4 } }) or nil
			if polys then
				local fny, fnz = 0, 1
				if rim then
					fny, fnz = 0.05, 0.9987
				end
				for _, poly in ipairs(polys) do
					-- front face: a fan over the convex polygon
					local ax, ay = x + 0.5 + PX[poly[1]], bottom + PY[poly[1]]
					for k = 2, #poly - 1 do
						local b, c = poly[k], poly[k + 1]
						vert(ax, ay, dz, 0, fny, fnz)
						vert(x + 0.5 + PX[b], bottom + PY[b], dz, 0, fny, fnz)
						vert(x + 0.5 + PX[c], bottom + PY[c], dz, 0, fny, fnz)
					end
					-- walls along the contour edges (both ends at edge midpoints), solid on the left
					for k = 1, #poly do
						local p, q = poly[k], poly[k % #poly + 1]
						if p >= 5 and q >= 5 then
							local px, py = x + 0.5 + PX[p], bottom + PY[p]
							local qx, qy = x + 0.5 + PX[q], bottom + PY[q]
							local dx, dy = qx - px, qy - py
							if dy == 0 then
								local a, b = math.min(px, qx), math.max(px, qx)
								if dx < 0 then
									if up and up[2] == a then
										up[2] = b
									else
										if up then
											wall(up[2], wall_y, up[1], wall_y, 0, 1)
										end
										up = { a, b }
									end
								else
									if down and down[2] == a then
										down[2] = b
									else
										if down then
											wall(down[1], wall_y, down[2], wall_y, 0, -1)
										end
										down = { a, b }
									end
								end
							else
								local len = math.sqrt(dx * dx + dy * dy)
								wall(px, py, qx, qy, dy / len, -dx / len)
							end
						end
					end
				end
			end
		end
	end
	flush_run(x_last + 1)
	flush_walls()
	local rowbuf = buffer.create(math.max(n, 1), {
		{ name = POSITION, type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
		{ name = NORMAL, type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
	})
	local ps, ns = buffer.get_stream(rowbuf, POSITION), buffer.get_stream(rowbuf, NORMAL)
	for i = 1, n * 3 do
		ps[i] = pos[i]
		ns[i] = nrm[i]
	end
	chunk.rows[y + 2] = { ps = ps, ns = ns, n = n, buf = rowbuf }
end

function M.build_rows(chunk, t, y_first, y_last, dz, pal)
	for y = math.max(-1, y_first), math.min(t.height - 1, y_last) do
		build_row(chunk, t, y, dz, pal)
	end
end

function M.to_buffer(chunk)
	local total = 0
	for _, row in pairs(chunk.rows) do
		total = total + row.n
	end
	local n = math.max(total, 3)
	local buf = buffer.create(n, {
		{ name = POSITION, type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
		{ name = NORMAL, type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
	})
	local ps, ns = buffer.get_stream(buf, POSITION), buffer.get_stream(buf, NORMAL)
	local i3 = 0
	for _, row in pairs(chunk.rows) do
		if row.n > 0 then
			buffer.copy_stream(ps, i3, row.ps, 0, row.n * 3)
			buffer.copy_stream(ns, i3, row.ns, 0, row.n * 3)
			i3 = i3 + row.n * 3
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

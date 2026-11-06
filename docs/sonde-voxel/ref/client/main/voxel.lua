-- Throwaway prototype: voxel models as mesh buffers (x and z centred on 0, base on y = 0).
local M = {}

local POSITION, NORMAL = hash("position"), hash("normal")

local function box(pos, nrm, x0, y0, z0, x1, y1, z1, faces)
	local function quad(a, b, c, d, nx, ny, nz)
		for _, v in ipairs({ a, b, c, a, c, d }) do
			local k = #pos
			pos[k + 1], pos[k + 2], pos[k + 3] = v[1], v[2], v[3]
			nrm[k + 1], nrm[k + 2], nrm[k + 3] = nx, ny, nz
		end
	end
	if faces.pz then
		quad({ x0, y0, z1 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z1 }, 0, 0, 1)
	end
	if faces.nz then
		quad({ x1, y0, z0 }, { x0, y0, z0 }, { x0, y1, z0 }, { x1, y1, z0 }, 0, 0, -1)
	end
	if faces.px then
		quad({ x1, y0, z1 }, { x1, y0, z0 }, { x1, y1, z0 }, { x1, y1, z1 }, 1, 0, 0)
	end
	if faces.nx then
		quad({ x0, y0, z0 }, { x0, y0, z1 }, { x0, y1, z1 }, { x0, y1, z0 }, -1, 0, 0)
	end
	if faces.py then
		quad({ x0, y1, z1 }, { x1, y1, z1 }, { x1, y1, z0 }, { x0, y1, z0 }, 0, 1, 0)
	end
	if faces.ny then
		quad({ x0, y0, z0 }, { x1, y0, z0 }, { x1, y0, z1 }, { x0, y0, z1 }, 0, -1, 0)
	end
end

local ALL = { pz = true, nz = true, px = true, nx = true, py = true, ny = true }

local function to_buffer(pos, nrm)
	local buf = buffer.create(#pos / 3, {
		{ name = POSITION, type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
		{ name = NORMAL, type = buffer.VALUE_TYPE_FLOAT32, count = 3 },
	})
	local ps, ns = buffer.get_stream(buf, POSITION), buffer.get_stream(buf, NORMAL)
	for i = 1, #pos do
		ps[i] = pos[i]
		ns[i] = nrm[i]
	end
	return buf
end

function M.blob()
	local set = {}
	local function key(i, j, k)
		return i .. ":" .. j .. ":" .. k
	end
	for i = -3, 3 do
		for j = 0, 6 do
			for k = -2, 2 do
				local d = (i / 3.6) ^ 2 + ((j + 0.5 - 3.4) / 3.6) ^ 2 + (k / 2.9) ^ 2
				if d <= 1 or (j == 0 and math.abs(i) <= 2 and math.abs(k) <= 1) then
					set[key(i, j, k)] = true
				end
			end
		end
	end
	local pos, nrm = {}, {}
	for i = -3, 3 do
		for j = 0, 6 do
			for k = -2, 2 do
				if set[key(i, j, k)] then
					box(pos, nrm, i - 0.5, j, k - 0.5, i + 0.5, j + 1, k + 0.5, {
						pz = not set[key(i, j, k + 1)],
						nz = not set[key(i, j, k - 1)],
						px = not set[key(i + 1, j, k)],
						nx = not set[key(i - 1, j, k)],
						py = not set[key(i, j + 1, k)],
						ny = not set[key(i, j - 1, k)],
					})
				end
			end
		end
	end
	return to_buffer(pos, nrm)
end

function M.eyes()
	local pos, nrm = {}, {}
	box(pos, nrm, -1.45, 4.0, 2.45, -0.55, 5.4, 2.62, ALL)
	box(pos, nrm, 0.55, 4.0, 2.45, 1.45, 5.4, 2.62, ALL)
	return to_buffer(pos, nrm)
end

function M.cube()
	local pos, nrm = {}, {}
	box(pos, nrm, -0.5, -0.5, -0.5, 0.5, 0.5, 0.5, ALL)
	return to_buffer(pos, nrm)
end

return M

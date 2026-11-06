local nk = require("nakama")
local probe = require("shared.sim.probe")

local function create_match(context, payload)
	local match_id = nk.match_create("spike_match", {})
	return nk.json_encode({ match_id = match_id })
end
nk.register_rpc(create_match, "create_match")

local function probe_rpc(context, payload)
	local res = probe.run()
	local t0 = os.clock()
	res.bench1m = string.format("%.0f", probe.bench(1000000))
	res.bench1m_ms = (os.clock() - t0) * 1000
	return nk.json_encode(res)
end
nk.register_rpc(probe_rpc, "probe")

local env = probe.run()
nk.logger_info(string.format("probe at load: fixed=%s float=%s trig=%s has_bit=%s has_bit32=%s xorshift=%s version=%s",
	env.fixed, env.float, env.trig, tostring(env.has_bit), tostring(env.has_bit32), env.xorshift, env.version))

local gridbench = require("shared.sim.gridbench")

local function grid_bench_rpc(context, payload)
	local req = {}
	if payload and payload ~= "" then req = nk.json_decode(payload) end
	local w = tonumber(req.w) or 2048
	local h = tonumber(req.h) or 1024
	local res = gridbench.run(w, h, os.clock, tonumber(req.lookups) or 1000000)
	return nk.json_encode(res)
end
nk.register_rpc(grid_bench_rpc, "grid_bench")

local lookupbench = require("shared.sim.lookupbench")

local function lookup_bench_rpc(context, payload)
	local req = {}
	if payload and payload ~= "" then req = nk.json_decode(payload) end
	local before = collectgarbage("count")
	local res = lookupbench.run(tonumber(req.w) or 2048, tonumber(req.h) or 1024, os.clock, tonumber(req.n) or 1000000)
	res.lua_kb_before = before
	res.lua_kb_after = collectgarbage("count")
	return nk.json_encode(res)
end
nk.register_rpc(lookup_bench_rpc, "lookup_bench")

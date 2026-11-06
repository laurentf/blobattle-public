local nk = require("nakama")

local M = {}

local OP_TICK = 100

function M.match_init(context, setupstate)
	local state = { presences = {}, count = 0, empty_ticks = 0 }
	return state, 10, "spike"
end

function M.match_join_attempt(context, dispatcher, tick, state, presence, metadata)
	return state, true
end

function M.match_join(context, dispatcher, tick, state, presences)
	for _, p in ipairs(presences) do
		state.presences[p.session_id] = p
		state.count = state.count + 1
	end
	return state
end

function M.match_leave(context, dispatcher, tick, state, presences)
	for _, p in ipairs(presences) do
		state.presences[p.session_id] = nil
		state.count = state.count - 1
	end
	return state
end

function M.match_loop(context, dispatcher, tick, state, messages)
	for _, m in ipairs(messages) do
		dispatcher.broadcast_message(m.op_code, m.data, nil, m.sender)
	end
	if tick % 10 == 0 then
		dispatcher.broadcast_message(OP_TICK, nk.json_encode({ tick = tick, players = state.count }))
	end
	if state.count == 0 then
		state.empty_ticks = state.empty_ticks + 1
		if state.empty_ticks > 600 then
			return nil
		end
	else
		state.empty_ticks = 0
	end
	return state
end

function M.match_terminate(context, dispatcher, tick, state, grace_seconds)
	return state
end

function M.match_signal(context, dispatcher, tick, state, data)
	return state, data
end

return M

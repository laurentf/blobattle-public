local protocol = require("shared.protocol")

local M = {}

M.FIND_ATTEMPTS = 5
M.FIND_WAIT = 0.5
M.RETRY_SECONDS = 2
M.TIMEOUT_SECONDS = 10
M.WATCHDOG_SECONDS = 25
M.PROBE_SECONDS = 5
M.KICK_SECONDS = 5
M.MAX_KICKS = 3

M.REASONS = {
  room_not_found = true,
  room_full = true,
  game_in_progress = true,
  nickname_required = true,
  invalid_nickname = true,
  invalid_team_name = true,
  invalid_member_name = true,
  room_code_unavailable = true,
}

local SERVER_OPS = {}
for name, op in pairs(protocol.OPS) do
  if protocol.CLIENT_OPS[op] == nil then
    SERVER_OPS[op] = name
  end
end

local function none() end

function M.new(fields)
  return {
    nakama = fields.nakama,
    engine = fields.engine,
    endpoint = fields.endpoint,
    server_key = fields.server_key,
    json = fields.json,
    after = fields.after,
    clock = fields.clock,
    disconnect = fields.disconnect,
    profile = fields.profile,
    status = "idle",
    generation = 0,
    kicks = 0,
    lobby_queue = {},
    lobby_spare = {},
    game_queue = {},
    game_spare = {},
    game = 0,
    measures = { rejoins = 0 },
  }
end

local function failed(result)
  return type(result) ~= "table" or result.error ~= nil
end

local function reason_of(result, default)
  local message = type(result) == "table" and result.message
  if type(result) == "table" and type(result.error) == "table" and result.error.message then
    message = result.error.message
  end
  if type(message) == "string" and M.REASONS[message] then
    return message
  end
  return default
end

local function push(queue, name, data)
  queue[#queue + 1] = { name = name, data = data }
end

local function clear(list)
  for i = #list, 1, -1 do
    list[i] = nil
  end
end

local function close(l)
  local socket = l.socket
  l.socket = nil
  if socket then
    l.disconnect(socket)
  end
end

local function fail(l, reason)
  close(l)
  l.generation = l.generation + 1
  l.busy = false
  l.status, l.reason = "failed", reason
end

local function begin_game(l, data)
  if l.rejoined and l.seed == data.seed and l.phase ~= "lobby" then
    l.rejoined = false
    return
  end
  l.rejoined = false
  l.game, l.seed = l.game + 1, data.seed
  l.team = nil
  for _, entry in ipairs(data.roster or {}) do
    if entry.user == l.user_id then
      l.team = entry.team
    end
  end
  clear(l.game_queue)
  push(l.game_queue, "game_start", data)
end

local function measure(l, inputs)
  local probe = l.probe
  for _, entry in ipairs(inputs or {}) do
    local input = entry.input
    if input.team == l.team and input.kind == probe.kind and input.direction == probe.direction then
      local m = l.measures
      m.rtt_ms = (l.clock() - probe.at) * 1000
      m.rtt_n = (m.rtt_n or 0) + 1
      m.rtt_avg_ms = (m.rtt_avg_ms or 0) + (m.rtt_ms - (m.rtt_avg_ms or 0)) / m.rtt_n
      l.probe = nil
      return
    end
  end
end

local function receive(l, socket, md)
  if socket ~= l.socket or type(md) ~= "table" then
    return
  end
  local name = SERVER_OPS[tonumber(md.op_code)]
  if name == nil then
    return
  end
  local text = md.data
  if text == nil or text == "" then
    text = "{}"
  end
  local ok, data = pcall(l.json.decode, text)
  if not ok or type(data) ~= "table" then
    return
  end
  if name == "ticks" and l.probe then
    measure(l, data.inputs)
  end
  if name == "lobby_state" then
    l.phase, l.lobby, l.rejoined, l.host = "lobby", data, false, data.host
    push(l.lobby_queue, name, data)
  elseif name == "game_start" then
    begin_game(l, data)
    l.phase = "playing"
  elseif name == "refused" and l.phase == "lobby" then
    push(l.lobby_queue, name, data)
  else
    if name == "game_end" then
      l.phase = "ended"
      if data.host ~= nil then
        l.host = data.host
      end
    elseif name == "snapshot" then
      l.measures.snapshot_bytes = #text
    end
    push(l.game_queue, name, data)
  end
end

local function lost(l, socket)
  if socket ~= l.socket then
    return
  end
  l.socket = nil
  if l.status ~= "joined" then
    return
  end
  if l.clock() - l.joined_at < M.KICK_SECONDS then
    l.kicks = l.kicks + 1
  else
    l.kicks = 0
  end
  if l.kicks >= M.MAX_KICKS then
    return fail(l, "elsewhere")
  end
  l.status = "reconnecting"
  l.retry_at = l.clock() + M.RETRY_SECONDS
end

local function sleep(l, seconds)
  local co = coroutine.running()
  l.after(seconds, function()
    local ok, err = coroutine.resume(co)
    if not ok then
      error(err)
    end
  end)
  coroutine.yield()
end

local function account(l)
  local client = l.client
  local session = client.authenticate_device(l.profile.device, nil, true)
  if failed(session) then
    return "offline"
  end
  client.set_bearer_token(session.token)
  l.user_id = session.user_id
  local updated = client.update_account(nil, l.profile.nickname)
  if failed(updated) then
    return reason_of(updated, "offline")
  end
  local team = client.rpc_func(
    "team_set",
    l.json.encode({ name = l.profile.team_name, members = l.profile.members })
  )
  if failed(team) then
    return reason_of(team, "offline")
  end
  return nil
end

local function locate(l, request, generation)
  local client = l.client
  if request.code == nil then
    local created = client.rpc_func("room_create", l.json.encode({ settings = request.settings }))
    if failed(created) then
      return nil, reason_of(created, "offline")
    end
    local out = l.json.decode(created.payload)
    l.code = out.code
    return out.match_id
  end
  for attempt = 1, M.FIND_ATTEMPTS do
    local found = client.rpc_func("room_find", l.json.encode({ code = request.code }))
    if l.generation ~= generation then
      return nil, "cancelled"
    end
    if not failed(found) then
      l.code = request.code
      return l.json.decode(found.payload).match_id
    end
    local reason = reason_of(found, "offline")
    if reason ~= "room_not_found" or attempt == M.FIND_ATTEMPTS then
      return nil, reason
    end
    sleep(l, M.FIND_WAIT)
  end
end

local function join(l, match_id, generation)
  local socket = l.client.create_socket()
  socket.on_match_data(function(message)
    receive(l, socket, message.match_data)
  end)
  socket.on_disconnect(function()
    lost(l, socket)
  end)
  l.socket = socket
  local connected = socket.connect()
  if l.generation ~= generation then
    l.disconnect(socket)
    return "cancelled"
  end
  if not connected or l.socket ~= socket then
    return "offline"
  end
  local joined = socket.match_join(match_id)
  if l.generation ~= generation then
    l.disconnect(socket)
    return "cancelled"
  end
  if l.socket ~= socket then
    return "offline"
  end
  if failed(joined) then
    return reason_of(joined, "room_not_found")
  end
  l.match_id, l.joined_at = match_id, l.clock()
  return nil
end

local function create_client(l)
  local e = l.endpoint
  l.client = l.nakama.create_client({
    host = e.host,
    port = e.port,
    use_ssl = e.ssl,
    username = l.server_key,
    password = "",
    engine = l.engine,
    timeout = M.TIMEOUT_SECONDS,
  })
end

local function run(l, fn)
  l.generation = l.generation + 1
  local generation = l.generation
  l.nakama.sync(function()
    fn(generation)
  end)
end

function M.enter(l, request)
  close(l)
  l.status, l.reason, l.started = "connecting", nil, l.clock()
  create_client(l)
  run(l, function(generation)
    local reason = account(l)
    local match_id
    if reason == nil and l.generation == generation then
      match_id, reason = locate(l, request, generation)
    end
    if reason == nil and l.generation == generation then
      reason = join(l, match_id, generation)
    end
    if l.generation ~= generation or reason == "cancelled" then
      return
    end
    if reason then
      return fail(l, reason)
    end
    l.status = "joined"
    l.measures.joined_s = l.clock() - l.started
  end)
end

local function rejoin(l)
  l.busy, l.started, l.rejoined = true, l.clock(), true
  run(l, function(generation)
    local reason = account(l)
    if reason == nil and l.generation == generation then
      reason = join(l, l.match_id, generation)
    end
    if l.generation ~= generation or reason == "cancelled" then
      return
    end
    l.busy = false
    if reason == "offline" then
      close(l)
      l.retry_at = l.clock() + M.RETRY_SECONDS
    elseif reason then
      fail(l, reason)
    else
      l.status = "joined"
      l.measures.rejoins = l.measures.rejoins + 1
      l.measures.rejoined_s = l.clock() - l.started
    end
  end)
end

function M.update(l)
  local now = l.clock()
  if l.status == "connecting" and now - l.started > M.WATCHDOG_SECONDS then
    fail(l, "offline")
  elseif l.status == "reconnecting" and l.busy and now - l.started > M.WATCHDOG_SECONDS then
    close(l)
    l.generation, l.busy, l.retry_at = l.generation + 1, false, now
  elseif l.status == "reconnecting" and not l.busy and now >= l.retry_at then
    rejoin(l)
  end
end

function M.send(l, name, body)
  local op = protocol.OPS[name]
  if l.status ~= "joined" or op == nil or protocol.CLIENT_OPS[op] == nil then
    return false
  end
  if name == "input" and (l.probe == nil or l.clock() - l.probe.at > M.PROBE_SECONDS) then
    l.probe = { kind = body.kind, direction = body.direction, at = l.clock() }
  end
  return (pcall(l.socket.match_data_send, l.match_id, op, l.json.encode(body), nil, nil, none))
end

local function drain(l, queue, spare)
  local out = l[queue]
  clear(l[spare])
  l[queue], l[spare] = l[spare], out
  return out
end

function M.lobby_messages(l)
  return drain(l, "lobby_queue", "lobby_spare")
end

function M.game_messages(l)
  return drain(l, "game_queue", "game_spare")
end

function M.hosting(l)
  return l.host ~= nil and l.host == l.user_id
end

function M.leave(l)
  local socket = l.socket
  l.status = "closed"
  l.generation, l.busy = l.generation + 1, false
  if socket and l.match_id then
    socket.match_leave(l.match_id, none)
  end
  close(l)
end

return M

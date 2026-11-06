local json = require("dkjson")

local M = {}

local function encode(value)
  return json.encode(value)
end

function M.new()
  local server = {
    now = 0,
    timers = {},
    rooms = {},
    calls = {},
    sockets = {},
    sent = {},
    users = {},
    find_misses = 0,
    held = {},
    join_error = nil,
    auth_error = false,
    connect_error = false,
    next_code = { "ABCDE", "FGHJK", "LMNPQ" },
  }

  local function call(name, value)
    server.calls[#server.calls + 1] = { name = name, value = value }
  end

  local rpc = {}

  function rpc.team_set(session, request)
    server.users[session.user_id].team = request
    return { payload = encode(request) }
  end

  function rpc.room_create(_, request)
    local code = table.remove(server.next_code, 1)
    local match_id = "match-" .. code
    server.rooms[code] = { match_id = match_id, settings = request.settings }
    return { payload = encode({ code = code, match_id = match_id }) }
  end

  function rpc.room_find(_, request)
    local room = server.rooms[request.code]
    if room == nil or server.find_misses > 0 then
      server.find_misses = math.max(0, server.find_misses - 1)
      return { error = {}, message = "room_not_found", code = 5 }
    end
    return { payload = encode({ match_id = room.match_id }) }
  end

  local function new_socket(session)
    local socket = { session = session, connected = false, closed = false, handlers = {} }
    function socket.on_match_data(fn)
      socket.handlers.match_data = fn
    end
    function socket.on_disconnect(fn)
      socket.handlers.disconnect = fn
    end
    function socket.connect()
      if server.connect_error then
        return false, "refused"
      end
      socket.connected = true
      return true
    end
    function socket.match_join(match_id)
      call("match_join", match_id)
      if server.hold_join then
        server.held[#server.held + 1] = { co = coroutine.running(), match_id = match_id }
        return coroutine.yield()
      end
      if server.join_error then
        return { cid = "1", error = { code = 3, message = server.join_error } }
      end
      socket.match_id = match_id
      return { cid = "1", match = { match_id = match_id } }
    end
    function socket.match_data_send(match_id, op_code, data, presences, reliable, callback)
      assert(presences == nil and reliable == nil)
      if not socket.connected then
        error("Connection isn't connected")
      end
      server.sent[#server.sent + 1] =
        { match_id = match_id, op = op_code, data = json.decode(data) }
      callback({})
    end
    function socket.match_leave(match_id, callback)
      call("match_leave", match_id)
      callback({})
    end
    server.sockets[#server.sockets + 1] = socket
    return socket
  end

  local nakama = {}

  function nakama.sync(fn)
    local co = coroutine.create(fn)
    local ok, err = coroutine.resume(co)
    if not ok then
      error(err)
    end
  end

  function nakama.create_client(config)
    call("create_client", config)
    local client = { config = config }
    local session, bearer = nil, nil
    local function signed()
      return session ~= nil and bearer == session.token
    end
    function client.authenticate_device(id, vars, create)
      call("authenticate_device", { id = id, vars = vars, create = create })
      if server.auth_error then
        return { error = true, message = "Unable to decode response" }
      end
      local user_id = "user-" .. id
      server.users[user_id] = server.users[user_id] or {}
      session, bearer = { token = "token-" .. id, user_id = user_id }, nil
      return session
    end
    function client.set_bearer_token(token)
      call("set_bearer_token", token)
      bearer = token
    end
    function client.update_account(avatar, display_name)
      assert(avatar == nil)
      call("update_account", display_name)
      if not signed() then
        return { error = {}, message = "Auth token invalid", code = 16 }
      end
      if #display_name < 2 then
        return { error = {}, message = "invalid_nickname", code = 3 }
      end
      server.users[session.user_id].nickname = display_name
      return {}
    end
    function client.rpc_func(id, payload)
      call("rpc", { id = id, payload = json.decode(payload) })
      if not signed() then
        return { error = {}, message = "Auth token invalid", code = 16 }
      end
      return rpc[id](session, json.decode(payload))
    end
    function client.create_socket()
      assert(signed(), "a socket needs the session token")
      return new_socket(session)
    end
    return client
  end

  server.nakama = nakama

  function server.after(seconds, fn)
    server.timers[#server.timers + 1] = { at = server.now + seconds, fn = fn }
  end

  function server.clock()
    return server.now
  end

  function server.advance(seconds)
    server.now = server.now + seconds
    local due = {}
    for i = #server.timers, 1, -1 do
      if server.timers[i].at <= server.now then
        due[#due + 1] = table.remove(server.timers, i)
      end
    end
    for i = #due, 1, -1 do
      due[i].fn()
    end
  end

  function server.release(index, result)
    local held = table.remove(server.held, index or 1)
    local ok, err =
      coroutine.resume(held.co, result or { cid = "1", match = { match_id = held.match_id } })
    if not ok then
      error(err)
    end
  end

  function server.socket()
    return server.sockets[#server.sockets]
  end

  function server.push(op, value, socket)
    socket = socket or server.socket()
    local data = type(value) == "string" and value or encode(value)
    socket.handlers.match_data({
      match_data = { match_id = socket.match_id, op_code = tostring(op), data = data },
    })
  end

  function server.cut(socket)
    socket = socket or server.socket()
    socket.connected = false
  end

  function server.drop(socket)
    socket = socket or server.socket()
    socket.connected = false
    socket.handlers.disconnect()
  end

  function server.disconnect(socket)
    socket.closed = true
  end

  function server.called(name)
    local out = {}
    for _, c in ipairs(server.calls) do
      if c.name == name then
        out[#out + 1] = c.value
      end
    end
    return out
  end

  return server
end

return M

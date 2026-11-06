local json = require("dkjson")

local M = {}

M.CODES = {
  INVALID_ARGUMENT = 3,
  NOT_FOUND = 5,
  PERMISSION_DENIED = 7,
  UNAVAILABLE = 14,
  UNAUTHENTICATED = 16,
}

local function label_matches(label, query)
  if query == nil or query == "" then
    return true
  end
  local decoded = json.decode(label or "")
  for field, value in query:gmatch("%+label%.([%w_]+):(%S+)") do
    if type(decoded) ~= "table" or tostring(decoded[field]) ~= value then
      return false
    end
  end
  return true
end

function M.new()
  local nk = {
    logs = {},
    matches = {},
    order = {},
    users = {},
    storage = {},
    uuids = {},
    now = 0,
    created = 0,
  }

  function nk.json_encode(value)
    return json.encode(value)
  end

  function nk.json_decode(text)
    local value, _, err = json.decode(text)
    if err then
      error(err)
    end
    return value
  end

  function nk.uuid_v4()
    local queued = table.remove(nk.uuids, 1)
    if queued then
      return queued
    end
    nk.created = nk.created + 1
    return string.format("%08x-0000-4000-8000-%012x", nk.created, nk.created)
  end

  function nk.time()
    return nk.now
  end

  for _, level in ipairs({ "debug", "info", "warn", "error" }) do
    nk["logger_" .. level] = function(message)
      nk.logs[#nk.logs + 1] = { level = level, message = message }
    end
  end

  function nk.match_create(module, params)
    local handler = require(module)
    local id = "match-" .. (#nk.order + 1) .. ".blobattle1"
    local state, rate, label = handler.match_init({ match_id = id }, params)
    nk.matches[id] = {
      match_id = id,
      handler = handler,
      state = state,
      rate = rate,
      label = label,
      authoritative = true,
      open = true,
    }
    nk.order[#nk.order + 1] = id
    return id
  end

  function nk.match_list(limit, authoritative, _, _, _, query)
    if query ~= nil and not query:find("^%+label%.code:[A-Z]+$") then
      error("unexpected match query: " .. query)
    end
    local found = {}
    for _, id in ipairs(nk.order) do
      local m = nk.matches[id]
      if m.open and (authoritative == nil or m.authoritative == authoritative) then
        if label_matches(m.label, query) then
          found[#found + 1] = { match_id = m.match_id, label = m.label, authoritative = true }
        end
      end
      if #found >= (limit or 1) then
        break
      end
    end
    return found
  end

  function nk.users_get_id(ids)
    local out = {}
    for _, id in ipairs(ids) do
      if nk.users[id] then
        out[#out + 1] = nk.users[id]
      end
    end
    return out
  end

  local function storage_key(o)
    return o.user_id .. "/" .. o.collection .. "/" .. o.key
  end

  function nk.storage_write(objects)
    nk.writes = (nk.writes or 0) + 1
    for _, o in ipairs(objects) do
      nk.storage[storage_key(o)] = {
        value = json.decode(json.encode(o.value)),
        permission_read = o.permission_read,
        permission_write = o.permission_write,
      }
    end
    return {}
  end

  function nk.storage_read(requests)
    local found = {}
    for _, r in ipairs(requests) do
      local o = nk.storage[storage_key(r)]
      if o then
        found[#found + 1] =
          { user_id = r.user_id, collection = r.collection, key = r.key, value = o.value }
      end
    end
    return found
  end

  function nk.add_user(id, display_name)
    nk.users[id] = { user_id = id, username = "u-" .. id, display_name = display_name }
  end

  function nk.logged(pattern)
    local found = {}
    for _, line in ipairs(nk.logs) do
      if line.message:find(pattern) then
        found[#found + 1] = line
      end
    end
    return found
  end

  return nk
end

function M.presence(user_id, session_id)
  return {
    user_id = user_id,
    session_id = session_id or ("s-" .. user_id),
    username = "u-" .. user_id,
    node = "blobattle1",
  }
end

function M.message(sender, op_code, data)
  if type(data) == "table" then
    data = json.encode(data)
  end
  return { sender = sender, op_code = op_code, data = data or "", reliable = true }
end

function M.match(nk, id)
  local m = nk.matches[id]
  local ctx = { match_id = id }
  local d = { sent = {}, labels = {}, kicked = {}, tick = 0 }
  d.dispatcher = {
    match_kick = function(presences)
      for _, p in ipairs(presences) do
        d.kicked[#d.kicked + 1] = p
      end
    end,
    broadcast_message = function(op_code, data, presences, sender)
      d.sent[#d.sent + 1] =
        { op_code = op_code, data = data, presences = presences, sender = sender }
    end,
    match_label_update = function(label)
      m.label = label
      d.labels[#d.labels + 1] = label
    end,
  }

  local function settle(state)
    m.state = state
    if state == nil then
      m.open = false
    end
    return state ~= nil
  end

  local function join_result(...)
    local count = select("#", ...)
    local state, accepted, reason = ...
    if type(accepted) ~= "boolean" or count > 3 or (count == 3 and type(reason) ~= "string") then
      error("match_join_attempt must return state, boolean[, string] (Nakama stops the match)")
    end
    return state, accepted, reason
  end

  function d.join(presence, metadata)
    local state, accepted, reason = join_result(
      m.handler.match_join_attempt(ctx, d.dispatcher, d.tick, m.state, presence, metadata or {})
    )
    settle(state)
    if not accepted then
      return false, reason
    end
    settle(m.handler.match_join(ctx, d.dispatcher, d.tick, m.state, { presence }))
    return true
  end

  function d.leave(presence)
    return settle(m.handler.match_leave(ctx, d.dispatcher, d.tick, m.state, { presence }))
  end

  function d.loop(messages)
    local open = settle(m.handler.match_loop(ctx, d.dispatcher, d.tick, m.state, messages or {}))
    d.tick = d.tick + 1
    return open
  end

  function d.state()
    return m.state
  end

  function d.open()
    return m.open
  end

  function d.label()
    return m.label
  end

  function d.received(op_code, presence)
    local out = {}
    for _, sent in ipairs(d.sent) do
      local to_them = sent.presences == nil
      for _, p in ipairs(sent.presences or {}) do
        if presence == nil or p.session_id == presence.session_id then
          to_them = true
        end
      end
      if sent.op_code == op_code and (presence == nil or to_them) then
        out[#out + 1] = json.decode(sent.data)
      end
    end
    return out
  end

  return d
end

function M.install()
  local nk = M.new()
  package.loaded.nakama = nk
  for name in pairs(package.loaded) do
    if name:find("^server%.") then
      package.loaded[name] = nil
    end
  end
  return nk
end

function M.rpc_error(fn, ...)
  local ok, err = pcall(fn, ...)
  if ok then
    return nil
  end
  if type(err) == "table" then
    return err[1], err[2]
  end
  return tostring(err), nil
end

return M

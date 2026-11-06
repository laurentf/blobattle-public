local fake = require("spec.support.nakama")

describe("🏠 the nickname guard (§6.1)", function()
  local identity

  before_each(function()
    fake.install()
    identity = require("server.identity")
  end)

  it("🏠 lets a valid nickname through unchanged", function()
    local payload = { display_name = "Mimi_2" }
    assert.are.equal(payload, identity.update_account({ user_id = "u1" }, payload))
  end)

  it("🏠 refuses an invalid nickname", function()
    for _, name in ipairs({ "A", " Mimi", "Zoé", "12345678901234567" }) do
      local message, code = fake.rpc_error(identity.update_account, { user_id = "u1" }, {
        display_name = name,
      })
      assert.are.equal("invalid_nickname", message, name)
      assert.are.equal(fake.CODES.INVALID_ARGUMENT, code)
    end
  end)

  it("🏠 refuses any other account field", function()
    for _, payload in ipairs({
      { display_name = "Mimi", location = "Paris" },
      { lang_tag = "fr" },
      { username = "mimi" },
      { avatar_url = "http://x" },
      { timezone = "UTC" },
    }) do
      local message, code = fake.rpc_error(identity.update_account, { user_id = "u1" }, payload)
      assert.are.equal("invalid_account", message)
      assert.are.equal(fake.CODES.INVALID_ARGUMENT, code)
    end
  end)

  it("🏠 refuses a client-chosen username at device authentication", function()
    local payload = { account = { id = "device-0123456789" }, create = true }
    assert.are.equal(payload, identity.authenticate_device({}, payload))
    payload.username = "Jean Dupont"
    local message, code = fake.rpc_error(identity.authenticate_device, {}, payload)
    assert.are.equal("invalid_account", message)
    assert.are.equal(fake.CODES.INVALID_ARGUMENT, code)
  end)
end)

describe("🏠 the team of a player, deposited by team_set (§6.1, §6.2)", function()
  local nk, identity

  local MEMBERS = { "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot" }

  before_each(function()
    nk = fake.install()
    identity = require("server.identity")
  end)

  local function deposit(user, body)
    local payload = type(body) == "string" and body or nk.json_encode(body)
    return identity.team_set({ user_id = user }, payload)
  end

  it("🏠 keeps a valid team on the account and gives it back", function()
    local out = nk.json_decode(deposit("u1", { name = "Blob Squad", members = MEMBERS }))
    assert.are.same({ name = "Blob Squad", members = MEMBERS }, out)
    assert.are.same({ name = "Blob Squad", members = MEMBERS }, identity.team_of("u1"))
    assert.is_nil(identity.team_of("u2"))
  end)

  it("🏠 a second deposit replaces the first", function()
    deposit("u1", { name = "Blob Squad", members = MEMBERS })
    local renamed = { "Mimi", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot" }
    deposit("u1", { name = "Gel Gang", members = renamed })
    assert.are.same({ name = "Gel Gang", members = renamed }, identity.team_of("u1"))
  end)

  it("🏠 stores it where no client can read or write it", function()
    deposit("u1", { name = "Blob Squad", members = MEMBERS })
    local stored = nk.storage["u1/team/team"]
    assert.are.equal(0, stored.permission_read)
    assert.are.equal(0, stored.permission_write)
  end)

  it("🚫 refuses a team name outside the nickname rules", function()
    for _, name in ipairs({ "A", " Blob", "Zoé team", "12345678901234567", 12 }) do
      local message, code = fake.rpc_error(deposit, "u1", { name = name, members = MEMBERS })
      assert.are.equal("invalid_team_name", message, tostring(name))
      assert.are.equal(fake.CODES.INVALID_ARGUMENT, code)
    end
    assert.is_nil(identity.team_of("u1"))
  end)

  it("🚫 refuses members that are not six valid names", function()
    local short = { "Alpha", "Bravo" }
    local bad = { "Alpha", "Bravo", "Charlie", "Delta", "Echo", "F" }
    local long = { "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf" }
    for _, members in ipairs({ short, bad, long, "Alpha", { name = "x" } }) do
      local message = fake.rpc_error(deposit, "u1", { name = "Blob Squad", members = members })
      assert.are.equal("invalid_member_name", message)
    end
    assert.is_nil(identity.team_of("u1"))
  end)

  it("🚫 refuses a body over 1 KiB, and writes nothing for the same team twice (D-14)", function()
    local long =
      nk.json_encode({ name = "Blob Squad", members = MEMBERS, pad = string.rep("x", 1100) })
    assert.are.equal("too_large", (fake.rpc_error(deposit, "u1", long)))
    assert.is_nil(identity.team_of("u1"))
    deposit("u1", { name = "Blob Squad", members = MEMBERS })
    deposit("u1", { name = "Blob Squad", members = MEMBERS })
    assert.are.equal(1, nk.writes)
    deposit("u1", { name = "Gel Gang", members = MEMBERS })
    assert.are.equal(2, nk.writes)
  end)

  it("🚫 refuses a body that is not a JSON object, and a call without a session", function()
    for _, body in ipairs({ "[1,2]", "nope", "12" }) do
      assert.are.equal("malformed", (fake.rpc_error(deposit, "u1", body)))
    end
    local message, code = fake.rpc_error(identity.team_set, {}, "{}")
    assert.are.equal("unauthenticated", message)
    assert.are.equal(fake.CODES.UNAUTHENTICATED, code)
  end)

  it("🏠 ignores a stored team that no longer passes the rules", function()
    nk.storage["u1/team/team"] = { value = { name = "X", members = MEMBERS } }
    assert.is_nil(identity.team_of("u1"))
    nk.storage["u1/team/team"] = { value = { name = "Blob Squad", members = { "Alpha", "B" } } }
    assert.is_nil(identity.team_of("u1"))
    nk.storage["u1/team/team"] = { value = { name = "Blob Squad", members = "Alpha" } }
    assert.is_nil(identity.team_of("u1"))
  end)
end)

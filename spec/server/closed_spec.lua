local fake = require("spec.support.nakama")

describe("🚫 the closed parts of Nakama (§6.1, D-15)", function()
  local closed

  before_each(function()
    fake.install()
    closed = require("server.closed")
  end)

  local function listed(list)
    local names = {}
    for _, name in ipairs(list) do
      names[name] = true
    end
    return names
  end

  it("🚫 closes every other way to sign in or link an account, but not the device", function()
    local names = listed(closed.ACCOUNTS)
    local sample = { "AuthenticateEmail", "AuthenticateGoogle", "LinkEmail", "LinkSteam" }
    for _, name in ipairs(sample) do
      assert.is_true(names[name], name)
    end
    assert.is_nil(names.AuthenticateDevice)
  end)

  it("🚫 closes the APIs where a player would write what the game does not use", function()
    local requests = listed(closed.REQUESTS)
    for _, name in ipairs({ "WriteStorageObjects", "CreateGroup", "AddFriends", "ListMatches" }) do
      assert.is_true(requests[name], name)
    end
    local realtime = listed(closed.REALTIME)
    for _, name in ipairs({ "ChannelJoin", "ChannelMessageSend", "MatchCreate", "StatusUpdate" }) do
      assert.is_true(realtime[name], name)
    end
    for _, name in ipairs({ "MatchJoin", "MatchLeave", "MatchDataSend" }) do
      assert.is_nil(realtime[name], name)
    end
  end)

  it("🚫 refuses with unsupported", function()
    local message, code = fake.rpc_error(closed.refuse, {}, {})
    assert.are.equal("unsupported", message)
    assert.are.equal(fake.CODES.PERMISSION_DENIED, code)
  end)
end)

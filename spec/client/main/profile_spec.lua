local profile = require("main.profile")
local rules = require("shared.sim.rules")

local MEMBERS = rules.SETTINGS.cats_per_team.max

local function members()
  local list = {}
  for i = 1, MEMBERS do
    list[i] = "Member" .. i
  end
  return list
end

describe("👤 the saved profile (§6.1)", function()
  it("👤 keeps a saved nickname, team and members as they were", function()
    local saved = {
      nickname = "Mia",
      team_name = "Blue Paws",
      members = members(),
      device = "0b5e2f3c-7d41-4c8e-9a0f-3f2d1e6b7a90",
    }
    local p, repaired = profile.read(saved)
    assert.are.same(saved, p)
    assert.is_false(repaired)
  end)

  it("👤 draws new members when the saved ones are missing or malformed", function()
    local short = members()
    short[MEMBERS] = nil
    local odd = members()
    odd[2] = "no{way}"
    for _, broken in ipairs({ false, short, odd, { 1, 2, 3, 4, 5, 6 } }) do
      local p, repaired = profile.read({
        nickname = "Mia",
        team_name = "Blue Paws",
        members = broken or nil,
        device = "0b5e2f3c-7d41-4c8e-9a0f-3f2d1e6b7a90",
      })
      assert.is_true(repaired)
      assert.are.equal("Mia", p.nickname)
      assert.are.equal("Blue Paws", p.team_name)
      assert.are.equal(MEMBERS, #p.members)
      assert.is_true(profile.valid_members(p.members))
    end
  end)

  it("👤 starts a fresh profile when the nickname or the team is not valid", function()
    local p = profile.read({ nickname = "x", team_name = "Blue Paws", members = members() })
    assert.is_true(p.fresh)
    assert.is_nil(p.nickname)
    assert.is_nil(p.members)
    assert.is_true(#p.team_name > 1)
  end)

  it("👤 draws a device id once, keeps it, and replaces a malformed one (D-15, §7.1)", function()
    local named = { nickname = "Mia", team_name = "Blue Paws", members = members() }
    for _, broken in ipairs({ false, "short", "bad id with spaces!", 42, string.rep("a", 129) }) do
      named.device = broken or nil
      local p, repaired = profile.read(named)
      assert.is_true(repaired, tostring(broken))
      assert.is_true(profile.valid_device(p.device), tostring(p.device))
      assert.are_not.equal(broken, p.device)
    end
    local fresh = profile.read({})
    assert.is_true(fresh.fresh)
    assert.is_true(profile.valid_device(fresh.device))
    local a, b = profile.new_device(), profile.new_device()
    assert.are_not.equal(a, b)
  end)

  it(
    "👤 keeps the proposed team, what was typed and the device across launches (§6.1)",
    function()
      local first, repaired = profile.read({})
      assert.is_true(first.fresh)
      assert.is_true(repaired, "a first launch must be saved at once")
      local again = profile.read({ team_name = first.team_name, device = first.device })
      assert.are.same(
        { first.team_name, first.device, true },
        { again.team_name, again.device, again.fresh }
      )
      local typed = profile.read({ nickname = "Mia", device = first.device })
      assert.are.equal("Mia", typed.nickname)
      assert.is_true(typed.fresh)
    end
  )

  it("👤 keeps the profile in the blobattle save folder", function()
    local engine = rawget(_G, "sys")
    local folders = {}
    rawset(_G, "sys", {
      get_save_file = function(app, name)
        folders[#folders + 1] = app
        return app .. "/" .. name
      end,
      load = function()
        return {}
      end,
      save = function() end,
    })
    local ok, err = pcall(profile.load)
    rawset(_G, "sys", engine)
    assert.is_true(ok, tostring(err))
    assert.is_true(#folders > 0)
    for _, folder in ipairs(folders) do
      assert.are.equal("blobattle", folder)
    end
  end)
end)

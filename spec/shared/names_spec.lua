local names = require("shared.names")
local protocol = require("shared.protocol")
local rng = require("shared.sim.rng")
local rules = require("shared.sim.rules")

local function all_names(game)
  local list = {}
  for _, team in ipairs(game) do
    list[#list + 1] = team.name
    for _, member in ipairs(team.members) do
      list[#list + 1] = member
    end
  end
  return list
end

local function from_dictionary(name)
  for _, head in ipairs(names.HEADS) do
    for _, tail in ipairs(names.TAILS) do
      if head .. tail == name then
        return true
      end
    end
  end
  return false
end

describe("🏷️ generated names (§6.1)", function()
  it(
    "🏷️ names each team and six members, distinct valid nicknames of the dictionary",
    function()
      local members = rules.SETTINGS.cats_per_team.max
      for seed = 1, 200 do
        local game = names.game(seed * 7919, rules.SETTINGS.teams.max)
        assert.are.equal(rules.SETTINGS.teams.max, #game)
        local seen = {}
        for _, team in ipairs(game) do
          assert.are.equal(members, #team.members)
        end
        for _, name in ipairs(all_names(game)) do
          assert.is_true(protocol.valid_nickname(name), name)
          assert.is_true(#name <= protocol.NICKNAME_MAX, name)
          assert.is_true(from_dictionary(name), name .. " is not a portmanteau of the dictionary")
          assert.is_nil(seen[name], name .. " drawn twice with seed " .. seed * 7919)
          seen[name] = true
        end
      end
    end
  )

  it("🏷️ gives the same names for the same seed and others for another seed", function()
    assert.are.same(names.game(4242, 4), names.game(4242, 4))
    assert.are_not.same(all_names(names.game(4242, 4)), all_names(names.game(4243, 4)))
  end)

  it("🏷️ names a team the same whatever the number of teams after it", function()
    local two, eight = names.game(99, 2), names.game(99, 8)
    assert.are.same(two[1], eight[1])
    assert.are.same(two[2], eight[2])
  end)

  it("🏷️ draws on the names stream of the game seed only", function()
    local stream = rng.stream(4242, "names")
    local first = names.team(stream, {})
    assert.are.same(names.game(4242, 1)[1], first)
    assert.are_not.same(names.game(4242, 1)[1], names.team(rng.stream(4242, "bots"), {}))
  end)

  it("🏷️ never draws a name already taken", function()
    local stream = rng.stream(5, "names")
    local taken, seen = { Purrnado = true }, { Purrnado = true }
    for _ = 1, 40 do
      local team = names.team(stream, taken)
      for _, name in ipairs({ team.name, unpack(team.members) }) do
        assert.is_nil(seen[name], name .. " drawn although taken")
        seen[name] = true
        assert.is_true(taken[name])
      end
    end
  end)

  it("🏷️ draws six distinct members for a player's own team", function()
    local members = names.members(rng.stream(31337, "names"))
    assert.are.equal(rules.SETTINGS.cats_per_team.max, #members)
    local seen = {}
    for _, name in ipairs(members) do
      assert.is_true(protocol.valid_nickname(name), name)
      assert.is_nil(seen[name])
      seen[name] = true
    end
  end)
end)

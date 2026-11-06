local rng = require("shared.sim.rng")
local rules = require("shared.sim.rules")

local M = {}

M.HEADS = {
  "Blob",
  "Squish",
  "Wobble",
  "Jelly",
  "Goo",
  "Gloop",
  "Splat",
  "Squelch",
  "Purr",
  "Meow",
  "Mew",
  "Mrow",
  "Whisker",
  "Paw",
  "Claw",
  "Fluff",
  "Floof",
  "Snuggle",
  "Mitten",
  "Kitty",
  "Tabby",
  "Furr",
  "Hiss",
  "Nap",
  "Pounce",
  "Catnip",
  "Scratch",
  "Fuzz",
  "Nibble",
  "Yowl",
  "Scruff",
  "Chonk",
  "Biscuit",
  "Loaf",
  "Bean",
  "Tuna",
  "Zoom",
  "Blep",
  "Snoot",
  "Tail",
}

M.TAILS = {
  "nado",
  "bytes",
  "zilla",
  "tron",
  "saurus",
  "nator",
  "tastic",
  "berry",
  "muffin",
  "bolt",
  "storm",
  "quake",
  "blaster",
  "rocket",
  "noodle",
  "pickle",
  "sprout",
  "pants",
  "wizard",
  "ninja",
  "boom",
  "dragon",
  "cannon",
  "pirate",
  "bandit",
  "comet",
  "pudding",
  "waffle",
  "nugget",
  "sparkle",
  "zap",
  "bot",
  "ble",
  "tank",
}

local MEMBERS = rules.SETTINGS.cats_per_team.max

local function draw(stream, taken)
  for _ = 1, #M.HEADS * #M.TAILS do
    local name = M.HEADS[rng.range(stream, 1, #M.HEADS)] .. M.TAILS[rng.range(stream, 1, #M.TAILS)]
    if not taken[name] then
      taken[name] = true
      return name
    end
  end
  error("no free name left")
end

function M.team(stream, taken)
  local team = { name = draw(stream, taken), members = {} }
  for i = 1, MEMBERS do
    team.members[i] = draw(stream, taken)
  end
  return team
end

function M.members(stream)
  local taken, list = {}, {}
  for i = 1, MEMBERS do
    list[i] = draw(stream, taken)
  end
  return list
end

function M.game(seed, teams)
  local stream = rng.stream(seed, "names")
  local taken, list = {}, {}
  for i = 1, teams do
    list[i] = M.team(stream, taken)
  end
  return list
end

return M

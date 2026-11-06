return {
  name = "duel",
  seed = 1240,
  settings = { teams = 2, cats_per_team = 2, bot_level = "hard" },
  script = {
    { at = 62, input = { team = 2, kind = "move", direction = -1 } },
    { at = 69, input = { team = 2, kind = "jump", direction = -1 } },
    { at = 76, input = { team = 2, kind = "move", direction = 0 } },
    { at = 100, input = { team = 2, kind = "fire", weapon = "bazooka", angle = 68, power = 44 } },
    { at = 272, input = { team = 1, kind = "move", direction = -1 } },
    { at = 279, input = { team = 1, kind = "jump", direction = -1 } },
    { at = 286, input = { team = 1, kind = "move", direction = 0 } },
    {
      at = 303,
      input = { team = 1, kind = "fire", weapon = "grenade", angle = 246, power = 75, fuse = 2 },
    },
    { at = 461, input = { team = 2, kind = "move", direction = 1 } },
    { at = 468, input = { team = 2, kind = "jump", direction = 1 } },
    { at = 475, input = { team = 2, kind = "move", direction = 0 } },
    {
      at = 479,
      input = { team = 2, kind = "fire", weapon = "grenade", angle = 313, power = 57, fuse = 3 },
    },
  },
  checks = { 0, 300, 600, 673 },
  expected = {
    { tick = 0, a = 317043626, b = 452765164 },
    { tick = 300, a = 887312350, b = 792167172 },
    { tick = 600, a = 1244371416, b = 1878989565 },
    { tick = 673, a = 373021880, b = 1374548030 },
  },
  names = {
    {
      name = "Whiskertron",
      members = {
        "Mewwaffle",
        "Meowbandit",
        "Splatzap",
        "Whiskerrocket",
        "Squelchwizard",
        "Gooninja",
      },
    },
    {
      name = "Scruffcannon",
      members = {
        "Fluffsprout",
        "Pawcomet",
        "Gootastic",
        "Pouncesparkle",
        "Zoomwizard",
        "Pounceble",
      },
    },
  },
}

local fixed = require("shared.sim.fixed")
local rules = require("shared.sim.rules")

local M = {
  id = "airstrike",
  kind = "strike",
  aim = "target",
}

function M.on_use(api, user, aim)
  local half = fixed.div(fixed.FP, 2)
  for k, offset in ipairs(rules.AIRSTRIKE_OFFSETS) do
    api.spawn_projectile({
      weapon = "airstrike_shell",
      owner = user.id,
      x = (aim.target + offset) * fixed.FP + half,
      y = -rules.AIRSTRIKE_ABOVE[k] * fixed.FP + half,
      vx = 0,
      vy = rules.AIRSTRIKE_VY,
    })
  end
  return true
end

return M

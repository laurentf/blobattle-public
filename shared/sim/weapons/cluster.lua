local fixed = require("shared.sim.fixed")
local rules = require("shared.sim.rules")

local M = {
  id = "cluster",
  kind = "projectile",
  aim = "angle_power",
  fuse = { min = 1, max = 5, default = 3 },
  wind_percent = 0,
  bounce = { restitution = 55, friction = 80 },
  explosion = { carve = 12, radius = 16, damage = 40, push = 1280 },
}

function M.on_timer(api, p, at)
  api.explode({ x = at.x, y = at.y, spec = M.explosion })
  api.remove_projectile(p)
  local half = fixed.div(fixed.FP, 2)
  for _, v in ipairs(rules.CLUSTER_BITS) do
    api.spawn_projectile({
      weapon = "cluster_bit",
      owner = p.owner,
      x = at.x * fixed.FP + half,
      y = at.y * fixed.FP + half,
      vx = v[1],
      vy = v[2],
    })
  end
end

return M

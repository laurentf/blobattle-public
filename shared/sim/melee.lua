local cat = require("shared.sim.cat")
local fixed = require("shared.sim.fixed")
local rules = require("shared.sim.rules")

local M = {}

function M.reaches(striker, target, reach)
  local px, py = cat.pixel(striker)
  local qx, qy = cat.pixel(target)
  local ahead = (qx - px) * striker.facing
  return ahead >= 1 and ahead < rules.CAT_WIDTH + reach and fixed.abs(qy - py) < rules.CAT_HEIGHT
end

function M.strike(env, fields)
  local user, spec, events = fields.cat, fields.spec, env.events
  local hit = false
  for _, c in ipairs(env.cats) do
    if c.alive and M.reaches(user, c, spec.reach) then
      cat.damage(c, { amount = spec.damage, cause = "melee" }, events)
      cat.push(c, user.facing * spec.push_x, -spec.push_y)
      hit = true
    end
  end
  return hit
end

return M

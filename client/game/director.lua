local weapons = require("shared.sim.weapons.registry")

local M = {}

M.HOLD_SECONDS = 1.2
M.AFTERMATH = { flight = true, retreat = true, settling = true, turn_end = true, quake = true }

function M.new()
  return {
    blast = { x = 0, y = 0, active = false, until_time = -1 },
    crack = { x = 0, y = 0, active = false, until_time = -1 },
    death = { id = nil, until_time = -1 },
  }
end

function M.event(d, e, fields)
  if e.type == "exploded" then
    local blast = d.blast
    blast.x, blast.y, blast.active = fields.x, fields.y, true
    blast.until_time = fields.now + M.HOLD_SECONDS
  elseif e.type == "cracked" then
    local crack = d.crack
    crack.x, crack.y, crack.active = fields.x, fields.y, true
    crack.until_time = fields.now + M.HOLD_SECONDS
  elseif e.type == "quaked" then
    d.blast.active = false
  elseif e.type == "turn_started" then
    d.blast.active = false
    d.crack.active = false
  elseif e.type == "died" then
    d.death.id, d.death.until_time = e.cat, fields.now + M.HOLD_SECONDS
  end
end

function M.follows(weapon)
  return weapons.get(weapon).kind ~= "placed"
end

function M.dying(d)
  return d.death.id
end

function M.target(d, view)
  local now, aftermath = view.now, M.AFTERMATH[view.state]
  if view.projectile then
    return "projectile", view.projectile.x, view.projectile.y
  end
  local crack = d.crack
  if (view.state == "quake" and crack.active) or now < crack.until_time then
    return "crack", crack.x, crack.y
  end
  if aftermath and view.thrown then
    return "thrown", view.thrown.x, view.thrown.y
  end
  if view.dead and now < d.death.until_time then
    return "death", view.dead.x, view.dead.y
  end
  local blast = d.blast
  if (aftermath and blast.active) or now < blast.until_time then
    return "blast", blast.x, blast.y
  end
  if view.crate then
    return "crate", view.crate.x, view.crate.y
  end
  if view.active then
    return "active", view.active.x, view.active.y
  end
  return nil
end

return M

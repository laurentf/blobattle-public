local cat = require("shared.sim.cat")
local fixed = require("shared.sim.fixed")
local rules = require("shared.sim.rules")
local terrain = require("shared.sim.terrain")

local div, round_div = fixed.div, fixed.round_div

local M = {}

function M.effect(c, blast)
  local px, py = cat.pixel(c)
  local dx = 2 * px - (2 * blast.x + 1)
  local dy = 2 * py - rules.CAT_HEIGHT + 2 - (2 * blast.y + 1)
  local d = fixed.isqrt(dx * dx + dy * dy)
  local reach = 2 * blast.spec.radius
  if d >= reach then
    return nil
  end
  local share = reach - d
  local strength = div(blast.spec.push * share, reach)
  local vy = round_div(strength * dy, d)
  if vy > -rules.PUSH_MIN_UP then
    vy = -rules.PUSH_MIN_UP
  end
  return {
    damage = div(blast.spec.damage * share, reach),
    vx = round_div(strength * dx, d),
    vy = vy,
  }
end

local NONE = {}

local function doom_crates(env, blast)
  local reach = 2 * blast.spec.radius
  for _, k in ipairs(env.crates or NONE) do
    if k.alive and k.fuse < 0 then
      local px, py = div(k.x, fixed.FP), div(k.y, fixed.FP)
      local dx = 2 * px - (2 * blast.x + 1)
      local dy = 2 * py - rules.CRATE_SIZE + 2 - (2 * blast.y + 1)
      if dx * dx + dy * dy < reach * reach then
        k.fuse = 1
      end
    end
  end
end

function M.apply(env, blast)
  terrain.carve(env.terrain, blast.x, blast.y, blast.spec.carve)
  local events = env.events
  events[#events + 1] = { type = "exploded", x = blast.x, y = blast.y, radius = blast.spec.carve }
  for _, c in ipairs(env.cats) do
    if c.alive then
      local hit = M.effect(c, blast)
      if hit then
        cat.damage(c, { amount = hit.damage, cause = "explosion" }, events)
        cat.release(c, events)
        cat.push(c, hit.vx, hit.vy)
      end
    end
  end
  doom_crates(env, blast)
end

return M

local cat = require("shared.sim.cat")
local explosion = require("shared.sim.explosion")
local melee = require("shared.sim.melee")
local projectile = require("shared.sim.projectile")

local M = {}

function M.new(env)
  local api = {}

  function api.explode(blast)
    explosion.apply(env, blast)
  end

  function api.remove_projectile(p)
    p.alive = false
  end

  function api.spawn_projectile(fields)
    if env.spawn == nil then
      error("this environment cannot spawn projectiles")
    end
    return env.spawn(fields)
  end

  function api.grapple(fields)
    return cat.grapple(
      fields.cat,
      { terrain = env.terrain, angle = fields.angle, events = env.events }
    )
  end

  function api.dig(fields)
    return cat.burrow(fields.cat, fields.angle)
  end

  function api.jetpack(fields)
    return cat.ignite(fields.cat, env.events)
  end

  function api.strike(fields)
    return melee.strike(env, fields)
  end

  return api
end

function M.dry_run()
  local record = { blast = nil }
  local api = {}

  function api.explode(blast)
    if record.blast == nil then
      record.blast = blast
    end
  end

  function api.remove_projectile(p)
    p.alive = false
  end

  function api.spawn_projectile(fields)
    return projectile.new(fields)
  end

  return api, record
end

return M

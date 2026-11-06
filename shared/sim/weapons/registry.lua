local M = {}

M.list = {
  require("shared.sim.weapons.bazooka"),
  require("shared.sim.weapons.grenade"),
  require("shared.sim.weapons.tentacle"),
  require("shared.sim.weapons.uppercut"),
  require("shared.sim.weapons.chomp"),
  require("shared.sim.weapons.dynamite"),
  require("shared.sim.weapons.cluster"),
  require("shared.sim.weapons.airstrike"),
  require("shared.sim.weapons.waddler"),
  require("shared.sim.weapons.jetpack"),
}

M.parts = {
  require("shared.sim.weapons.cluster_bit"),
  require("shared.sim.weapons.airstrike_shell"),
}

M.by_id = {}
local chosen = {}
for _, weapon in ipairs(M.list) do
  M.by_id[weapon.id] = weapon
  chosen[weapon.id] = true
end
for _, part in ipairs(M.parts) do
  M.by_id[part.id] = part
end

function M.index_of(id)
  for i, weapon in ipairs(M.list) do
    if weapon.id == id then
      return i
    end
  end
  for j, part in ipairs(M.parts) do
    if part.id == id then
      return #M.list + j
    end
  end
  return nil
end

function M.selectable(id)
  return id ~= nil and chosen[id] == true
end

function M.get(id)
  return M.by_id[id]
end

function M.ends_turn(id)
  return M.by_id[id].kind ~= "utility"
end

return M

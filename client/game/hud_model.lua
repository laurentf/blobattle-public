local M = {}

function M.reset()
  M.buttons = {}
  M.aim = nil
  M.aim_origin = nil
  M.weapon = nil
  M.weapons = {}
  M.ammo = {}
  M.fuse = nil
  M.grid = false
  M.mine = false
  M.hanging = false
  M.jetting = false
  M.touch_device = true
  M.turn = nil
  M.teams = {}
  M.seconds = nil
  M.wind = 0
  M.labels = {}
  M.marker = nil
  M.action = nil
  M.target = nil
  M.pops = {}
end

M.reset()

return M

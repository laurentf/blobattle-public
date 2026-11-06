local M = {
  id = "uppercut",
  kind = "melee",
  aim = "none",
  melee = { reach = 10, damage = 30, push_x = 512, push_y = 1024 },
}

function M.on_use(api, user)
  return api.strike({ cat = user, spec = M.melee })
end

return M

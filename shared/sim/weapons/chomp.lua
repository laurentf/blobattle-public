return {
  id = "chomp",
  kind = "digger",
  aim = "angle",
  on_use = function(api, user, aim)
    return api.dig({ cat = user, angle = aim.angle })
  end,
}

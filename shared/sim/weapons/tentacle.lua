return {
  id = "tentacle",
  kind = "utility",
  aim = "angle",
  on_use = function(api, user, aim)
    return api.grapple({ cat = user, angle = aim.angle })
  end,
}

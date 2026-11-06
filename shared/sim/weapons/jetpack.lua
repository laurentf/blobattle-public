return {
  id = "jetpack",
  kind = "utility",
  aim = "none",
  on_use = function(api, user)
    return api.jetpack({ cat = user })
  end,
}

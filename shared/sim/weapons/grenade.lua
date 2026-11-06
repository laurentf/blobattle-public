return {
  id = "grenade",
  kind = "projectile",
  aim = "angle_power",
  fuse = { min = 1, max = 5, default = 3 },
  wind_percent = 0,
  bounce = { restitution = 55, friction = 80 },
  explosion = { carve = 12, radius = 16, damage = 50, push = 1280 },
}

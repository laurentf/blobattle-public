local intro = require("ui.intro")

describe("🎬 the intro (§7.2)", function()
  it(
    "🎬 shows the studio first, shaking harder and harder, then the game's logo, then the home",
    function()
      local early = intro.at(0.2)
      assert.is_true(early.studio > 0 and early.logo == 0 and early.cover == 1 and not early.home)
      local calm, mad = intro.at(1).shake, intro.at(intro.SHAKE_UNTIL - 0.1).shake
      assert.is_true(calm > 0 and calm < mad / 2, calm .. " then " .. mad)
      assert.is_true(mad >= 0.9 * intro.SHAKE_MAX)
      assert.is_true(intro.at(intro.SHAKE_UNTIL - 0.1).zoom > intro.at(1).zoom)
      local between = intro.at((intro.STUDIO_OUT + intro.LOGO_IN) / 2)
      assert.are.same({ 0, 0 }, { between.studio, between.logo })
      local logo = intro.at((intro.LOGO_FULL + intro.LOGO_OUT) / 2)
      assert.are.same({ 0, 1, 1 }, { logo.studio, logo.logo, logo.cover })
      local home = intro.at(intro.HOME)
      assert.is_true(home.home and home.logo == 0 and home.cover == 1 and not home.over)
      local fading = intro.at((intro.HOME + intro.OVER) / 2)
      assert.is_true(fading.cover > 0 and fading.cover < 1)
      local over = intro.at(intro.OVER)
      assert.is_true(over.over and over.cover == 0)
    end
  )

  it("🎬 keeps the timings and sizes of §7.2", function()
    assert.are.same({ 0.4, 2.9, 3.3, 3.5, 4, 5.7, 6.1, 6.5, 1, 14, 0.15 }, {
      intro.STUDIO_IN,
      intro.SHAKE_UNTIL,
      intro.STUDIO_OUT,
      intro.LOGO_IN,
      intro.LOGO_FULL,
      intro.LOGO_OUT,
      intro.HOME,
      intro.OVER,
      intro.SHAKE_MIN,
      intro.SHAKE_MAX,
      intro.ZOOM,
    })
  end)

  it("🎬 shakes in the square of the time: a quarter of the way at half time", function()
    local half = intro.at(intro.SHAKE_UNTIL / 2).shake - intro.SHAKE_MIN
    local span = intro.SHAKE_MAX - intro.SHAKE_MIN
    assert.is_true(math.abs(half - span / 4) < 0.01, half .. " of " .. span)
    assert.are.equal(intro.SHAKE_MAX, intro.at(intro.STUDIO_OUT).shake)
  end)

  it("🎬 the logo pops in with a bounce, then holds still", function()
    local biggest, smallest = 0, math.huge
    for step = 0, 50 do
      local scale = intro.at(intro.LOGO_IN + step / 100).logo_scale
      biggest, smallest = math.max(biggest, scale), math.min(smallest, scale)
    end
    assert.is_true(biggest > 1.05 and smallest < 0.8, smallest .. " to " .. biggest)
    assert.are.equal(1, intro.at(intro.LOGO_FULL).logo_scale)
    assert.are.equal(1, intro.at(intro.LOGO_OUT).logo_scale)
  end)

  it("🎬 a tap skips to the home, never back", function()
    assert.are.equal(intro.HOME, intro.skip(0.5))
    assert.are.equal(intro.HOME, intro.skip(intro.LOGO_FULL))
    assert.are.equal(intro.HOME + 0.1, intro.skip(intro.HOME + 0.1))
  end)

  it("🎬 fills the table it is given", function()
    local out = {}
    assert.are.equal(out, intro.at(1, out))
  end)
end)

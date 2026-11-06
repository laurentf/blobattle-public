local shorten = require("ui.shorten")

local function width(text)
  return #text * 7
end

local function fit(text, max)
  return shorten.fit({ text = text, max = max, width = width, mark = "." })
end

describe("✂️ a name cut to fit its line (§7.4)", function()
  it("✂️ leaves a name that fits as it is", function()
    assert.are.equal("Gel Gang", fit("Gel Gang", 70))
    assert.are.equal("Gel Gang", fit("Gel Gang", 56))
  end)

  it("✂️ cuts a long name and marks the cut, within the width", function()
    local out = fit("Snugglebytes Crew", 70)
    assert.are.equal("Snuggleby.", out)
    assert.is_true(width(out) <= 70)
  end)

  it("✂️ never cuts to nothing, nor ends the cut on a space", function()
    assert.are.equal("S.", fit("Snugglebytes", 5))
    assert.are.equal("Blob.", fit("Blob Squad Team", 38))
    assert.are.equal("Blob.", fit("Blob Squad Team", 45))
  end)

  it("✂️ marks the cut with the catalogue's mark", function()
    assert.are.equal(
      "Snuggl~",
      shorten.fit({ text = "Snugglebytes", max = 50, width = width, mark = "~" })
    )
  end)
end)

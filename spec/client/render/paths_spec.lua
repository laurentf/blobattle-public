local paths = require("render.paths")

describe("📦 resource paths", function()
  it("📦 hands out a new buffer path on every call, for as long as the module lives", function()
    local seen = {}
    for _ = 1, 50 do
      local p = paths.next("menu")
      assert.is_nil(seen[p], p)
      assert.is_truthy(p:match("^/menu_%d+%.bufferc$"))
      seen[p] = true
    end
    assert.are_not.equal(paths.next("liquid"), paths.next("liquid"))
  end)
end)

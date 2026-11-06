local measures = require("game.measures")

describe("📏 the measures published in test mode (§11)", function()
  it("📏 summarises the average, the 95th percentile and the worst", function()
    local list = measures.new()
    for i = 1, 100 do
      measures.add(list, i)
    end
    assert.are.same({ avg = 50.5, p95 = 95, max = 100, n = 100 }, measures.summary(list))
    assert.are.same({ avg = 0, p95 = 0, max = 0, n = 0 }, measures.summary(measures.new()))
  end)

  it("📏 keeps only the last 300 values", function()
    local list = measures.new()
    for i = 1, 400 do
      measures.add(list, i)
    end
    local s = measures.summary(list)
    assert.are.equal(300, s.n)
    assert.are.equal(250.5, s.avg)
  end)
end)

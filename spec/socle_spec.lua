describe("🧪 test runner", function()
  it("🧪 runs under the engine the Makefile asked for", function()
    local expected = os.getenv("BLOBATTLE_LUA")
    assert.is_not_nil(expected)
    if expected == "luajit" then
      assert.is_not_nil(jit)
    else
      assert.are.equal("lua5.1", expected)
      assert.is_nil(jit)
      assert.are.equal("Lua 5.1", _VERSION)
    end
  end)
end)

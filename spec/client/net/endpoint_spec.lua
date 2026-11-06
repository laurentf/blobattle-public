local endpoint = require("net.endpoint")

describe("🌐 where the online client finds Nakama and its rooms (§7.1, §7.2)", function()
  it(
    "🌐 on the local network, talks to Nakama at the page's host, on the configured port",
    function()
      assert.are.same(
        { host = "192.168.0.21", port = 7550, ssl = false },
        endpoint.resolve({
          hostname = "192.168.0.21",
          protocol = "http:",
          page_port = "5373",
          port = 7550,
        })
      )
    end
  )

  it("🌐 through the tunnel, talks to Nakama at the page's own origin, over TLS", function()
    assert.are.same(
      { host = "blobattle.npc.fm", port = 443, ssl = true },
      endpoint.resolve({
        hostname = "blobattle.npc.fm",
        protocol = "https:",
        page_port = "",
        port = 7550,
      })
    )
    assert.are.same(
      { host = "blob.example", port = 8443, ssl = true },
      endpoint.resolve({
        hostname = "blob.example",
        protocol = "https:",
        page_port = "8443",
        port = 7550,
      })
    )
  end)

  it("🌐 falls back to the configured host outside a web page", function()
    assert.are.same(
      { host = "127.0.0.1", port = 7550, ssl = false },
      endpoint.resolve({ host = "127.0.0.1", port = 7550 })
    )
    assert.are.same(
      { host = "10.0.0.2", port = 7550, ssl = false },
      endpoint.resolve({ hostname = "", host = "10.0.0.2", port = 7550 })
    )
  end)

  it("🌐 reads a valid room code from the page's query, in capitals", function()
    assert.are.equal("ABCDE", endpoint.room_param("?room=ABCDE"))
    assert.are.equal("KMNPQ", endpoint.room_param("?test=1&room=kmnpq&seed=4"))
    for _, search in ipairs({
      "",
      "?test=1",
      "?room=ABCD",
      "?room=ABCDI",
      "?room=AB1DE",
      "?rooms=ABCDE",
    }) do
      assert.is_nil(endpoint.room_param(search), search)
    end
  end)

  it("🌐 builds the link to share, without the page's other parameters", function()
    assert.are.equal(
      "http://192.168.0.21:5373/?room=ABCDE",
      endpoint.room_link({ origin = "http://192.168.0.21:5373", pathname = "/", code = "ABCDE" })
    )
  end)
end)

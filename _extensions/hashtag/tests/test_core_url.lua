-- tests/test_core_url.lua
require("tests.bootstrap")

local lu = require("luaunit")
local core = require("_hashtag.core")

TestCoreURL = {}

------------------------------------------------------------
-- url_encode
------------------------------------------------------------

function TestCoreURL:test_url_encode_ascii()
  lu.assertEquals(core.url_encode("test"), "test")
  lu.assertEquals(core.url_encode("test123"), "test123")
end

function TestCoreURL:test_url_encode_space()
  lu.assertEquals(core.url_encode("hello world"), "hello%20world")
end

function TestCoreURL:test_url_encode_utf8()
  -- Maß → M%C3%A4%C3%9F
  lu.assertEquals(
    core.url_encode("Maß"),
    "Ma%C3%9F"
  )
end

function TestCoreURL:test_url_encode_emoji()
  -- 🔥 = F0 9F 94 A5
  lu.assertEquals(
    core.url_encode("🔥"),
    "%F0%9F%94%A5"
  )
end

------------------------------------------------------------
-- build_url
------------------------------------------------------------

function TestCoreURL:test_build_url_basic()
  local cfg = {
    providers = {
      x = {
        url = "https://example.com/%23{tag}"
      }
    }
  }

  local url = core.build_url(cfg, "x", "test")
  lu.assertEquals(url, "https://example.com/%23test")
end

function TestCoreURL:test_build_url_encoded()
  local cfg = {
    providers = {
      x = {
        url = "https://example.com/%23{tag}"
      }
    }
  }

  local url = core.build_url(cfg, "x", "Maß")
  lu.assertEquals(url, "https://example.com/%23Ma%C3%9F")
end

function TestCoreURL:test_build_url_missing_provider()
  local cfg = {
    providers = {}
  }

  lu.assertNil(core.build_url(cfg, "x", "test"))
end

function TestCoreURL:test_build_url_missing_url()
  local cfg = {
    providers = {
      x = {}
    }
  }

  lu.assertNil(core.build_url(cfg, "x", "test"))
end

------------------------------------------------------------

os.exit(lu.LuaUnit.run())

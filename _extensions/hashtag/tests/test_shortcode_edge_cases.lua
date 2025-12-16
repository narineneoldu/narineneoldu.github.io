-- tests/test_shortcode_edge_cases.lua
-- Shortcode edge cases: unknown provider, missing URL, linkify=false behavior.

require("tests.bootstrap")

local lu = require("luaunit")
local H = require("tests.helpers")

local function reload_shortcode()
  -- core/config/shortcode cache’lerini kır
  H.reload({ "_hashtag.core", "shortcode" })
end

TestShortcodeEdgeCases = {}

function TestShortcodeEdgeCases:setUp()
  -- Her testte temiz sayım / temiz stub
  self.called = 0

  -- Stub config: tests öncelikli config
  package.loaded["_hashtag.config"] = {
    read_config = function(_meta)
      self.called = self.called + 1
      return {
        linkify = true,
        default_provider = "x",
        target = "_blank",
        title = false,
        rel = nil,
        hashtag_numbers = 0,
        providers = {
          x = { name = "X", url = "https://x.example/search?q=%23{tag}" },
          -- deliberately minimal
        }
      }
    end
  }

  reload_shortcode()
end

function TestShortcodeEdgeCases:test_unknown_provider_falls_back_to_plain_text()
  -- unknown provider explicit
  local out = htag({ "unknown-provider", "Tag" }, {}, {})

  lu.assertTrue(self.called > 0)
  lu.assertEquals(out.t, "Str")
  lu.assertEquals(out.text, "#Tag")
end

function TestShortcodeEdgeCases:test_provider_missing_url_falls_back_to_plain_text()
  -- providers.x exists but url missing -> build_url returns nil -> Str fallback
  package.loaded["_hashtag.config"].read_config = function(_meta)
    self.called = self.called + 1
    return {
      linkify = true,
      default_provider = "x",
      title = false,
      hashtag_numbers = 0,
      providers = { x = { name = "X" } } -- url intentionally missing
    }
  end

  reload_shortcode()

  local out = htag({ "Tag" }, {}, {})

  lu.assertTrue(self.called > 0)
  lu.assertEquals(out.t, "Str")
  lu.assertEquals(out.text, "#Tag")
end

function TestShortcodeEdgeCases:test_linkify_false_ignores_missing_url_and_returns_span()
  -- linkify=false: URL gerekmez, Span basmak normal (tasarımın böyle)
  package.loaded["_hashtag.config"].read_config = function(_meta)
    self.called = self.called + 1
    return {
      linkify = false,
      default_provider = "x",
      title = false,
      hashtag_numbers = 0,
      providers = { x = { name = "X" } } -- url missing, but shouldn't matter
    }
  end

  reload_shortcode()

  local out = htag({ "Tag" }, {}, {})

  lu.assertTrue(self.called > 0)
  lu.assertEquals(out.t, "Span")
  lu.assertEquals(H.inline_text(out), "#Tag")
end

os.exit(lu.LuaUnit.run())

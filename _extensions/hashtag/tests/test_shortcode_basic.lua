-- tests/test_shortcode_basic.lua
-- Shortcodes: linkify/span, default-provider, explicit provider.

require("tests.bootstrap")
local lu = require("luaunit")
local H = require("tests.helpers")

local called = 0

TestShortcodeBasic = {}

function TestShortcodeBasic:setUp()
  called = 0

  -- Default stub config for most tests
  package.loaded["_hashtag.config"] = {
    read_config = function(_meta)
      called = called + 1
      return {
        linkify = true,
        default_provider = "x",
        target = "_blank",
        title = false,
        rel = nil,
        hashtag_numbers = 0,
        providers = {
          x = { name = "X", url = "https://x.example/search?q=%23{tag}" },
          mastodon = { name = "Mastodon", url = "https://m.example/tags/{tag}" },
        }
      }
    end
  }

  H.reload({ "_hashtag.core", "shortcode" })
end

function TestShortcodeBasic.test_htag_one_arg_uses_default_provider()
  local out = htag({ "Test" }, {}, {})
  lu.assertTrue(called > 0)
  lu.assertEquals(out.t, "Link")
  lu.assertEquals(H.inline_text(out), "#Test")
  lu.assertStrContains(out.target, "%23Test")
end

function TestShortcodeBasic.test_htag_two_args_explicit_provider()
  local out = htag({ "mastodon", "Test" }, {}, {})
  lu.assertTrue(called > 0)
  lu.assertEquals(out.t, "Link")
  lu.assertStrContains(out.target, "/tags/Test")
end

function TestShortcodeBasic.test_alias_provider()
  local out = mastodon({ "Hello" }, {}, {})
  lu.assertTrue(called > 0)
  lu.assertEquals(out.t, "Link")
  lu.assertStrContains(out.target, "/tags/Hello")
end

function TestShortcodeBasic.test_linkify_false_returns_span()
  -- Override stub config for this test
  package.loaded["_hashtag.config"].read_config = function(_meta)
    called = called + 1
    return {
      linkify = false,
      default_provider = "x",
      title = false,
      hashtag_numbers = 0,
      providers = { x = { name = "X", url = "https://x.example/{tag}" } }
    }
  end

  -- Reload so shortcode/core observe the new config behavior
  H.reload({ "_hashtag.core", "shortcode" })

  local out = htag({ "Test" }, {}, {})
  lu.assertTrue(called > 0)
  lu.assertEquals(out.t, "Span")
  lu.assertEquals(H.inline_text(out), "#Test")
end

function TestShortcodeBasic.test_default_provider_empty_falls_back_to_plain_text()
  -- Override stub config for this test
  package.loaded["_hashtag.config"].read_config = function(_meta)
    called = called + 1
    return {
      linkify = true,
      default_provider = "",
      title = false,
      hashtag_numbers = 0,
      providers = {}
    }
  end

  -- Reload so shortcode/core observe the new config behavior
  H.reload({ "_hashtag.core", "shortcode" })

  local out = htag({ "Test" }, {}, {})
  lu.assertTrue(called > 0)
  lu.assertEquals(out.t, "Str")
  lu.assertEquals(out.text, "#Test")
end

os.exit(lu.LuaUnit.run())

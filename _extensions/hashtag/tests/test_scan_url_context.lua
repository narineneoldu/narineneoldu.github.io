-- tests/test_scan_url_context.lua
-- Ensure URL context heuristic prevents hashtag conversion inside URLs.

require("tests.bootstrap")

local lu = require("luaunit")
local Hs = require("tests.helpers_scan")

Hs.monkeypatch_core_for_scan()
local scan = require("_hashtag.scan")

TestScanURLContext = {}

function TestScanURLContext.test_url_hash_same_str_not_converted()
  local cfg = Hs.cfg_span_only()
  local inlines = { pandoc.Str("https://example.com/#section") }
  local out = scan.process_inlines(inlines, cfg, {}, false)

  lu.assertFalse(Hs.any_converted(out))
  lu.assertEquals(Hs.flatten_text(out), "https://example.com/#section")
end

function TestScanURLContext.test_url_hash_cross_str_not_converted()
  local cfg = Hs.cfg_span_only()
  local inlines = { pandoc.Str("https://example.com/"), pandoc.Str("#section") }
  local out = scan.process_inlines(inlines, cfg, {}, false)

  lu.assertFalse(Hs.any_converted(out))
  lu.assertEquals(Hs.flatten_text(out), "https://example.com/#section")
end

function TestScanURLContext.test_non_url_context_converts()
  local cfg = Hs.cfg_span_only()
  local inlines = { pandoc.Str("see (#tag) now") }
  local out = scan.process_inlines(inlines, cfg, {}, false)

  lu.assertTrue(Hs.any_converted(out))
end

function TestScanURLContext.test_www_context_not_converted()
  local cfg = Hs.cfg_span_only()
  local inlines = { pandoc.Str("www.example.com/#foo") }
  local out = scan.process_inlines(inlines, cfg, {}, false)

  lu.assertFalse(Hs.any_converted(out))
  lu.assertEquals(Hs.flatten_text(out), "www.example.com/#foo")
end

os.exit(lu.LuaUnit.run())

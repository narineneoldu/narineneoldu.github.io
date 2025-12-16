-- tests/test_scan_cross_str.lua
-- Cross-Str boundary behavior (previous inline influences whether '#tag' starts).

require("tests.bootstrap")

local lu = require("luaunit")
local Hs = require("tests.helpers_scan")

Hs.monkeypatch_core_for_scan()
local scan = require("_hashtag.scan")

local function skipset()
  return {}
end

TestScanCrossStr = {}

function TestScanCrossStr.test_prev_str_boundary_allows_after_paren()
  local cfg = Hs.cfg_span_only()
  local inlines = { pandoc.Str("("), pandoc.Str("#test") }
  local out = scan.process_inlines(inlines, cfg, skipset(), false)

  lu.assertEquals(Hs.flatten_text(out), "(#test")
  lu.assertEquals(out[2].t, "Span")
end

function TestScanCrossStr.test_prev_str_boundary_blocks_after_letter()
  local cfg = Hs.cfg_span_only()
  local inlines = { pandoc.Str("a"), pandoc.Str("#test") }
  local out = scan.process_inlines(inlines, cfg, skipset(), false)

  lu.assertEquals(Hs.flatten_text(out), "a#test")
  -- Ensure it did not convert to Span/Link
  lu.assertEquals(out[2].t, "Str")
end

function TestScanCrossStr.test_prev_non_str_is_treated_as_boundary()
  local cfg = Hs.cfg_span_only()
  local inlines = { pandoc.Str("a"), pandoc.Space(), pandoc.Str("#test") }
  local out = scan.process_inlines(inlines, cfg, skipset(), false)

  lu.assertEquals(Hs.flatten_text(out), "a #test")
  lu.assertEquals(out[3].t, "Span")
end

function TestScanCrossStr.test_hash_at_start_of_inline_uses_previous_str_tail()
  local cfg = Hs.cfg_span_only()
  local inlines = { pandoc.Str("x("), pandoc.Str("#test") }
  local out = scan.process_inlines(inlines, cfg, skipset(), false)

  lu.assertEquals(Hs.flatten_text(out), "x(#test")
  lu.assertEquals(out[2].t, "Span")
end

os.exit(lu.LuaUnit.run())

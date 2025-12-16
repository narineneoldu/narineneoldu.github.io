-- tests/test_scan_basic.lua
-- Basic scan tests (uses tests/bootstrap.lua stubs)

require("tests.bootstrap")

local lu = require("luaunit")
local Hs = require("tests.helpers_scan")

Hs.monkeypatch_core_for_scan()
local scan = require("_hashtag.scan")

TestScanBasic = {}

function TestScanBasic:test_simple_hashtag_to_link()
  local cfg = Hs.cfg_default()
  local out = scan.process_inlines({ Hs.Str("Hello #World!") }, cfg, {}, false)

  lu.assertEquals(out[2].t, "Link")
  lu.assertEquals(out[2].content[1].text, "#World")
  lu.assertEquals(out[2].target, "https://example.test/x/World")
  lu.assertEquals(Hs.texts(out), "Hello #World!")
end

function TestScanBasic:test_stop_char_curly_apostrophe_stops_body()
  local cfg = Hs.cfg_default()
  local out = scan.process_inlines({ Hs.Str("#Maßnahmenpaket’nin test") }, cfg, {}, false)

  -- Expect: Link for "#Maßnahmenpaket" then Str "’nin test"
  lu.assertEquals(out[1].t, "Link")
  lu.assertEquals(out[1].content[1].text, "#Maßnahmenpaket")
  lu.assertEquals(out[2].t, "Str")
  lu.assertEquals(out[2].text, "’nin test")
end

function TestScanBasic:test_start_boundary_blocks_midword()
  local cfg = Hs.cfg_default()
  local out = scan.process_inlines({ Hs.Str("abc#Tag def") }, cfg, {}, false)

  -- Should not turn into a hashtag because prev is 'c' (not boundary)
  lu.assertEquals(Hs.texts(out), "abc#Tag def")
  lu.assertEquals(out[1].t, "Str")
end

function TestScanBasic:test_url_context_blocks()
  local cfg = Hs.cfg_default()
  local out = scan.process_inlines({ Hs.Str("See https://x.com/#Tag now") }, cfg, {}, false)

  -- Should not convert #Tag inside URL-like context
  lu.assertEquals(Hs.texts(out), "See https://x.com/#Tag now")
end

function TestScanBasic:test_numeric_policy_blocks_short_numbers()
  local cfg = Hs.cfg_default()
  cfg.hashtag_numbers = 3

  local out = scan.process_inlines({ Hs.Str("#12 and #123") }, cfg, {}, false)

  -- Expect: "#12" stays plain, "#123" becomes Link, with " and " preserved.
  lu.assertEquals(out[1].t, "Str")
  lu.assertEquals(out[1].text, "#12")

  lu.assertEquals(out[2].t, "Str")
  lu.assertEquals(out[2].text, " and ")

  lu.assertEquals(out[3].t, "Link")
  lu.assertEquals(out[3].content[1].text, "#123")
end

function TestScanBasic:test_skip_classes_in_span_inherits_parent_skip()
  local cfg = Hs.cfg_default()
  local skip_set = { ["no-hashtag"] = true }

  -- Parent skip=true should block everything under it
  local out = scan.process_inlines({ Hs.Str("A #X") }, cfg, skip_set, true)
  lu.assertEquals(Hs.texts(out), "A #X")
end

function TestScanBasic:test_span_child_skip_is_or_with_parent_skip()
  local cfg = Hs.cfg_default()
  local skip_set = { ["no-hashtag"] = true }

  -- Parent skip=false but span has skip class => skip inside span only (outer still processed)
  local inlines = {
    Hs.Str("A "),
    Hs.Span({ Hs.Str("#X") }, { "no-hashtag" }),
    Hs.Str(" B #Y"),
  }

  local out = scan.process_inlines(inlines, cfg, skip_set, false)

  -- "#X" should remain as text inside span
  lu.assertEquals(out[2].t, "Span")
  lu.assertEquals(out[2].content[1].t, "Str")
  lu.assertEquals(out[2].content[1].text, "#X")

  -- "#Y" should convert
  lu.assertEquals(out[#out].t, "Link")
  lu.assertEquals(out[#out].content[1].text, "#Y")
end

os.exit(lu.LuaUnit.run())

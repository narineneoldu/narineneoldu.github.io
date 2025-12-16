-- tests/test_scan_skip_classes.lua
-- Skip regions: span/div classes and parent skip propagation.

require("proxy")
local lu = require("luaunit")

local Hs = require("helpers_scan")

Hs.monkeypatch_core_for_scan()
local scan = require("_hashtag.scan")

local function set_of(...)
  local s = {}
  for i = 1, select("#", ...) do
    s[select(i, ...)] = true
  end
  return s
end

TestScanSkipClasses = {}

function TestScanSkipClasses.test_span_with_skip_class_blocks_inside_only()
  local cfg = Hs.cfg_span_only()
  local skip_set = set_of("no-hashtag")

  local inlines = {
    pandoc.Span({ pandoc.Str("#a") }, { classes = { "no-hashtag" } }),
    pandoc.Space(),
    pandoc.Str("#b"),
  }

  local out = scan.process_inlines(inlines, cfg, skip_set, false)

  -- First element should remain a Span, but inner should stay Str (no conversion)
  lu.assertEquals(out[1].t, "Span")
  lu.assertEquals(out[1].content[1].t, "Str")
  lu.assertEquals(out[1].content[1].text, "#a")

  -- Second hashtag should convert
  lu.assertEquals(out[3].t, "Span")
end

function TestScanSkipClasses.test_parent_skip_true_disables_everything()
  local cfg = Hs.cfg_span_only()
  local skip_set = set_of("no-hashtag")

  local inlines = {
    pandoc.Str("#a"),
    pandoc.Space(),
    pandoc.Span({ pandoc.Str("#b") }, { classes = {} }),
  }

  local out = scan.process_inlines(inlines, cfg, skip_set, true)

  -- Parent skip=true => dönüşüm yok, ama mevcut Span korunur.
  lu.assertEquals(out[1].t, "Str")
  lu.assertEquals(out[1].text, "#a")

  lu.assertEquals(out[3].t, "Span")
  lu.assertEquals(out[3].content[1].t, "Str")
  lu.assertEquals(out[3].content[1].text, "#b")

  -- Link kesinlikle üretilmemeli
  for _, el in ipairs(out) do
    lu.assertNotEquals(el.t, "Link")
  end
end

function TestScanSkipClasses.test_nested_skip_inherited()
  local cfg = Hs.cfg_span_only()
  local skip_set = set_of("no-hashtag")

  local inlines = {
    pandoc.Span({
      pandoc.Emph({ pandoc.Str("#a") })
    }, { classes = { "no-hashtag" } }),
  }

  local out = scan.process_inlines(inlines, cfg, skip_set, false)

  lu.assertEquals(out[1].t, "Span")
  lu.assertEquals(out[1].content[1].t, "Emph")
  lu.assertEquals(out[1].content[1].content[1].t, "Str")
  lu.assertEquals(out[1].content[1].content[1].text, "#a")
end

os.exit(lu.LuaUnit.run())

-- tests/test_golden_paragraph.lua
-- Golden regression: one big paragraph with mixed cases.

require("proxy")
local lu = require("luaunit")

local Hs = require("helpers_scan")

Hs.monkeypatch_core_for_scan()
local scan = require("_hashtag.scan")

TestGoldenParagraph = {}

function TestGoldenParagraph:test_big_paragraph_regression()
  local cfg = Hs.cfg_span_only()
  cfg.hashtag_numbers = 3

  local inlines = {
    pandoc.Str("Hello "),
    pandoc.Str("#World, "),
    pandoc.Str("this is "),
    pandoc.Emph({ pandoc.Str("an "), pandoc.Str("#EmphTag") }),
    pandoc.Str(". "),
    pandoc.Str("URL: https://example.com/"),
    pandoc.Str("#frag "),
    pandoc.Str("and mailto:test@example.com"),
    pandoc.Str("#nope "),
    pandoc.Str("and href=\"#x"),
    pandoc.Str("#nope2\" "),
    pandoc.Str("numbers: "),
    pandoc.Str("#12 "),
    pandoc.Str("and "),
    pandoc.Str("#123 "),
    pandoc.Str("end. "),
    pandoc.Str("Punct: "),
    pandoc.Str("(#A) "),
    pandoc.Str("[#B] "),
    pandoc.Str("{#C} "),
    pandoc.Str("#D; "),
    pandoc.Str("#E: "),
    pandoc.Str("#F| "),
    pandoc.Str("done"),
  }

  local out = scan.process_inlines(inlines, cfg, { ["no-hashtag"]=true }, false)

  -- Text must remain identical (conversion changes structure, not text)
  lu.assertEquals(Hs.flatten_text(out),
    "Hello #World, this is an #EmphTag. URL: https://example.com/#frag and mailto:test@example.com#nope and href=\"#x#nope2\" numbers: #12 and #123 end. Punct: (#A) [#B] {#C} #D; #E: #F| done"
  )

  -- Conversion count: pick a stable expectation
  -- Converted (cfg_span_only): #World, #EmphTag, #123, #A, #B, #C, #D, #E, #F
  -- Not converted: #frag (URL), #nope (mailto), #nope2 (href=), #12 (numeric threshold)
  lu.assertEquals(Hs.count_converted(out), 9)
end

os.exit(lu.LuaUnit.run())

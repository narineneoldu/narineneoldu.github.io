-- tests/test_scan_nested_containers.lua
-- Nested containers: ensure recursion works and skip regions propagate correctly.

require("tests.bootstrap")

local lu = require("luaunit")
local Hs = require("tests.helpers_scan")

Hs.monkeypatch_core_for_scan()
local scan = require("_hashtag.scan")

local function Emph(content) return pandoc.Emph(content) end
local function Strong(content) return pandoc.Strong(content) end
local function Quoted(content) return pandoc.Quoted("DoubleQuote", content) end

local function CodeSpan(txt) return { t = "CodeSpan", text = txt } end
local function Code(txt) return { t = "Code", text = txt } end
local function Link(content, target)
  return pandoc.Link(content, target or "https://example.test", "", pandoc.Attr("", {}, {}))
end

TestScanNestedContainers = {}

function TestScanNestedContainers:test_nested_emph_strong_quoted_converts()
  local cfg = Hs.cfg_span_only()
  local inlines = {
    Emph({
      Strong({
        Quoted({
          Hs.Str("Hello #World!")
        })
      })
    })
  }

  local out = scan.process_inlines(inlines, cfg, {}, false)
  lu.assertTrue(Hs.any_converted(out))
  lu.assertEquals(Hs.flatten_text(out), "Hello #World!")
end

function TestScanNestedContainers:test_span_skip_class_blocks_only_inside_span()
  local cfg = Hs.cfg_span_only()
  local skip_set = { ["no-hashtag"] = true }

  local inlines = {
    Hs.Str("A "),
    Hs.Span({ Hs.Str("#X") }, { "no-hashtag" }),
    Hs.Str(" B "),
    Emph({ Hs.Str("#Y") }),
  }

  local out = scan.process_inlines(inlines, cfg, skip_set, false)

  -- #X should remain literal inside skip span
  -- #Y should convert (Span)
  lu.assertEquals(Hs.flatten_text(out), "A #X B #Y")

  -- Validate #X still Str within that span
  lu.assertEquals(out[2].t, "Span")
  lu.assertEquals(out[2].content[1].t, "Str")
  lu.assertEquals(out[2].content[1].text, "#X")

  -- Somewhere later should be a converted Span for #Y
  local foundY = false
  local function walk(el)
    if not el then return end
    if el.t == "Span"
      and el.attr and el.attr.classes
      and el.content and el.content[1] and el.content[1].t == "Str"
    then
      local is_hashtag = false
      for _, c in ipairs(el.attr.classes) do
        if c == "hashtag" then is_hashtag = true break end
      end
      if is_hashtag and el.content[1].text == "#Y" then
        foundY = true
      end
    end
    for _, c in ipairs(el.content or {}) do walk(c) end
  end
  for _, el in ipairs(out) do walk(el) end
  lu.assertTrue(foundY)
end

function TestScanNestedContainers:test_parent_skip_true_blocks_everything_recursively()
  local cfg = Hs.cfg_span_only()
  local skip_set = { ["no-hashtag"] = true }

  local inlines = {
    Emph({ Hs.Str("A #X") }),
    Hs.Span({ Strong({ Hs.Str(" B #Y") }) }, { "no-hashtag" }),
  }

  local out = scan.process_inlines(inlines, cfg, skip_set, true)
  lu.assertFalse(Hs.any_converted(out))
  lu.assertEquals(Hs.flatten_text(out), "A #X B #Y")
end

function TestScanNestedContainers:test_does_not_touch_existing_link_or_code()
  local cfg = Hs.cfg_span_only()

  local inlines = {
    Hs.Str("A "),
    Link({ Hs.Str("#InLink") }, "https://example.test/#InLink"),
    Hs.Str(" "),
    CodeSpan("#InCodeSpan"),
    Hs.Str(" "),
    Code("#InCode"),
    Hs.Str(" "),
    Hs.Str("#Outside"),
  }

  local out = scan.process_inlines(inlines, cfg, {}, false)

  -- Should convert only #Outside
  lu.assertEquals(Hs.flatten_text(out), "A #InLink #InCodeSpan #InCode #Outside")

  -- Ensure Link remains Link
  lu.assertEquals(out[2].t, "Link")

  -- Ensure last hashtag converted to Span (cfg_span_only)
  local last = out[#out]
  lu.assertEquals(last.t, "Span")
  lu.assertEquals(last.content[1].text, "#Outside")
end

os.exit(lu.LuaUnit.run())

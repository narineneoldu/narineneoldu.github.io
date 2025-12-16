-- tests/test_property_micro.lua
-- Small invariants to catch broad regressions.

require("proxy")
local lu = require("luaunit")

local Hs = require("helpers_scan")

Hs.monkeypatch_core_for_scan()
local scan = require("_hashtag.scan")

local function count_empty_str(out)
  local n = 0
  local function walk(el)
    if not el then return end
    if el.t == "Str" and (el.text == "") then n = n + 1 end
    for _, c in ipairs(el.content or {}) do walk(c) end
  end
  for _, el in ipairs(out or {}) do walk(el) end
  return n
end

TestPropertyMicro = {}

function TestPropertyMicro:test_text_preservation()
  local cfg = Hs.cfg_span_only()
  local inlines = {
    pandoc.Str("A "),
    pandoc.Str("#X, "),
    pandoc.Emph({ pandoc.Str("B "), pandoc.Str("#Y") }),
    pandoc.Str(" url "),
    pandoc.Str("https://t.co/"),
    pandoc.Str("#Z"),
  }

  local out = scan.process_inlines(inlines, cfg, {}, false)
  lu.assertEquals(Hs.flatten_text(out), Hs.flatten_text(inlines))
end

function TestPropertyMicro:test_idempotent_on_output_shape_metrics()
  local cfg = Hs.cfg_span_only()
  local inlines = {
    pandoc.Str("A #X "),
    pandoc.Str("B (#Y) "),
    pandoc.Str("C"),
  }

  local out1 = scan.process_inlines(inlines, cfg, {}, false)
  local out2 = scan.process_inlines(out1, cfg, {}, false)

  -- Same visible text
  lu.assertEquals(Hs.flatten_text(out1), Hs.flatten_text(out2))

  -- Same conversion count (avoid double-wrapping regressions)
  lu.assertEquals(Hs.count_converted(out1), Hs.count_converted(out2))
end

function TestPropertyMicro:test_no_empty_str_nodes()
  local cfg = Hs.cfg_span_only()
  local inlines = {
    pandoc.Str("#X"),
    pandoc.Str(" "),
    pandoc.Str("#Y!"),
  }

  local out = scan.process_inlines(inlines, cfg, {}, false)
  lu.assertEquals(count_empty_str(out), 0)
end

os.exit(lu.LuaUnit.run())

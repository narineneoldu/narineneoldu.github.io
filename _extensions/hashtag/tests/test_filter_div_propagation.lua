-- tests/test_filter_div_propagation.lua
-- filter.lua: Div recursion + skip-class propagation for block-level processing.

require("proxy")
local lu = require("luaunit")
local H = require("helpers")

TestFilterDivPropagation = {}

function TestFilterDivPropagation:setUp()
  self.scan_calls = 0

  -- Stub _hashtag.core.read_config: filter gate’lerini aç
  package.loaded["_hashtag.core"] = {
    read_config = function(_meta)
      return {
        auto_scan = true,
        linkify = false,
        default_provider = "x",
        skip_classes = { "no-hashtag" },
        hashtag_numbers = 0,
      }
    end
  }

  -- Stub _hashtag.scan.process_inlines: sadece çağrıldığını say
  package.loaded["_hashtag.scan"] = {
    process_inlines = function(inlines, _cfg, _skip_set, skip)
      -- Count only "effective" scans. skip=true should be a no-op path.
      if not skip then
        self.scan_calls = self.scan_calls + 1
      end
      return inlines
    end
  }

  -- filter modülünü yeniden yükle (stub’ları görsün)
  H.reload({ "filter" })
end

local function mk_doc(blocks)
  -- doc.blocks pandoc.List olmalı (filter doc.blocks:walk kullanıyor)
  local lst = pandoc.List:new()
  for _, b in ipairs(blocks or {}) do lst:insert(b) end
  return { meta = {}, blocks = lst }
end

local function Div(classes, blocks)
  return pandoc.Div(blocks, { classes = classes or {} })
end

TestFilterDivPropagation = TestFilterDivPropagation

function TestFilterDivPropagation:test_scans_para_and_plain_outside_div()
  local doc = mk_doc({
    pandoc.Para({ pandoc.Str("A #X") }),
    pandoc.Plain({ pandoc.Str("B #Y") }),
  })

  -- filter.lua, modül return’ünde { { Pandoc = Pandoc } } döndürüyor
  local f = require("filter")
  local out = f[1].Pandoc(doc)

  lu.assertNotNil(out)
  lu.assertEquals(self.scan_calls, 2) -- Para + Plain
end

function TestFilterDivPropagation:test_skip_class_div_disables_children()
  local doc = mk_doc({
    Div({ "no-hashtag" }, {
      pandoc.Para({ pandoc.Str("A #X") }),
      pandoc.Plain({ pandoc.Str("B #Y") }),
    }),
    pandoc.Para({ pandoc.Str("C #Z") }), -- outside -> should scan
  })

  local f = require("filter")
  f[1].Pandoc(doc)

  -- İçteki 2 block skiplenir, dıştaki Para taranır
  lu.assertEquals(self.scan_calls, 1)
end

function TestFilterDivPropagation:test_nested_div_propagation()
  local doc = mk_doc({
    Div({}, {
      pandoc.Para({ pandoc.Str("A #X") }), -- scanned
      Div({ "no-hashtag" }, {
        pandoc.Para({ pandoc.Str("B #Y") }), -- skipped
      }),
      pandoc.Plain({ pandoc.Str("C #Z") }), -- scanned
    })
  })

  local f = require("filter")
  f[1].Pandoc(doc)

  lu.assertEquals(self.scan_calls, 2) -- A ve C
end

os.exit(lu.LuaUnit.run())

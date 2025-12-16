-- tests/test_integration_smoke.lua
-- Smoke test: filter + scan + core together on a tiny doc.

require("proxy")
local lu = require("luaunit")

-- Stub config BEFORE requiring filter/core
package.loaded["_hashtag.config"] = {
  read_config = function(_meta)
    return {
      auto_scan = true,
      linkify = false, -- span mode keeps stubs minimal
      default_provider = "x",
      title = false,
      hashtag_numbers = 0,
      skip_classes = {},
      providers = { x = { name = "X", url = "https://x.example/{tag}" } }
    }
  end
}

local filter_mod = require("filter") -- returns { { Pandoc = Pandoc } }

local function find_first_span(inlines)
  for _, el in ipairs(inlines or {}) do
    if el.t == "Span" then return el end
  end
  return nil
end

TestIntegrationSmoke = {}

function TestIntegrationSmoke.test_para_converts_hashtag()
  local doc = {
    meta = {},
    blocks = pandoc.List:new()
  }
  doc.blocks:insert(pandoc.Para({ pandoc.Str("Hello #World") }))

  local PandocFn = filter_mod[1].Pandoc
  local out = PandocFn(doc)

  lu.assertEquals(out.blocks[1].t, "Para")
  local span = find_first_span(out.blocks[1].content)
  lu.assertNotNil(span)
end

os.exit(lu.LuaUnit.run())

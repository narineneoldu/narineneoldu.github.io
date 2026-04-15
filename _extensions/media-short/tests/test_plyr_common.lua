-- tests/test_plyr_common.lua
-- Unit tests for _media_short.plyr_common pure helpers.
--
-- These helpers underpin every attribute and style string emitted by the
-- audio/video shortcodes. A regression here silently breaks player config
-- for every embedded media element on the site.

require("proxy")
local lu = require("luaunit")

-- Stub deps module before requiring plyr_common, in case of indirect require chains.
package.preload["_media_short.deps_core"] = function()
  return { ensure_plyr = function() end }
end

local plyr_common = require("_media_short.plyr_common")

------------------------------------------------------------
-- normalize_string
------------------------------------------------------------

TestNormalizeString = {}

function TestNormalizeString:test_nil_returns_nil()
  lu.assertNil(plyr_common.normalize_string(nil))
end

function TestNormalizeString:test_empty_string_returns_nil()
  lu.assertNil(plyr_common.normalize_string(""))
end

function TestNormalizeString:test_literal_false_returns_nil()
  -- Explicit sentinel: the string "false" is treated as "unset".
  lu.assertNil(plyr_common.normalize_string("false"))
end

function TestNormalizeString:test_plain_string_passthrough()
  lu.assertEquals(plyr_common.normalize_string("320px"), "320px")
end

function TestNormalizeString:test_literal_true_passthrough()
  -- "true" is a normal string here; only normalize_bool interprets it.
  lu.assertEquals(plyr_common.normalize_string("true"), "true")
end

------------------------------------------------------------
-- normalize_bool
------------------------------------------------------------

TestNormalizeBool = {}

function TestNormalizeBool:test_nil_returns_nil()
  lu.assertNil(plyr_common.normalize_bool(nil))
end

function TestNormalizeBool:test_empty_string_returns_nil()
  lu.assertNil(plyr_common.normalize_bool(""))
end

function TestNormalizeBool:test_true_variants()
  lu.assertEquals(plyr_common.normalize_bool("true"), true)
  lu.assertEquals(plyr_common.normalize_bool("1"),    true)
end

function TestNormalizeBool:test_false_variants()
  lu.assertEquals(plyr_common.normalize_bool("false"), false)
  lu.assertEquals(plyr_common.normalize_bool("0"),     false)
end

function TestNormalizeBool:test_invalid_returns_nil()
  -- "yes"/"no" etc. are NOT recognized — caller should feed true/false/0/1.
  lu.assertNil(plyr_common.normalize_bool("yes"))
  lu.assertNil(plyr_common.normalize_bool("no"))
  lu.assertNil(plyr_common.normalize_bool("42"))
end

------------------------------------------------------------
-- kw / kw_bool
------------------------------------------------------------

TestKw = {}

function TestKw:test_string_present()
  local kwargs = { width = "320px" }
  lu.assertEquals(plyr_common.kw(kwargs, "width"), "320px")
end

function TestKw:test_string_missing()
  lu.assertNil(plyr_common.kw({}, "width"))
end

function TestKw:test_bool_present()
  local kwargs = { fullscreen = "false" }
  lu.assertEquals(plyr_common.kw_bool(kwargs, "fullscreen"), false)
end

function TestKw:test_bool_missing()
  lu.assertNil(plyr_common.kw_bool({}, "fullscreen"))
end

------------------------------------------------------------
-- build_attr
------------------------------------------------------------

TestBuildAttr = {}

function TestBuildAttr:test_empty_table()
  lu.assertEquals(plyr_common.build_attr({}), "")
end

function TestBuildAttr:test_single_attr()
  lu.assertEquals(
    plyr_common.build_attr({ id = "foo" }),
    ' id="foo"'
  )
end

function TestBuildAttr:test_multiple_attrs_sorted_alphabetically()
  -- Deterministic output is critical for golden-file snapshot tests.
  local out = plyr_common.build_attr({
    id            = "player-1",
    ["data-time"] = "00:45",
    class         = "js-player",
  })
  lu.assertEquals(out, ' class="js-player" data-time="00:45" id="player-1"')
end

function TestBuildAttr:test_nil_values_skipped()
  local out = plyr_common.build_attr({ id = "foo", class = nil })
  lu.assertEquals(out, ' id="foo"')
end

------------------------------------------------------------
-- build_style
------------------------------------------------------------

TestBuildStyle = {}

function TestBuildStyle:test_empty_table_returns_empty_string()
  lu.assertEquals(plyr_common.build_style({}), "")
end

function TestBuildStyle:test_all_nil_values_returns_empty_string()
  lu.assertEquals(plyr_common.build_style({ width = nil, height = nil }), "")
end

function TestBuildStyle:test_single_property()
  lu.assertEquals(
    plyr_common.build_style({ ["max-width"] = "320px" }),
    ' style="max-width:320px;"'
  )
end

function TestBuildStyle:test_multiple_properties_sorted()
  local out = plyr_common.build_style({
    ["max-width"] = "320px",
    width         = "100%",
    ["aspect-ratio"] = "16/9",
  })
  lu.assertEquals(
    out,
    ' style="aspect-ratio:16/9; max-width:320px; width:100%;"'
  )
end

function TestBuildStyle:test_nil_values_skipped()
  local out = plyr_common.build_style({
    width  = "320px",
    height = nil,
  })
  lu.assertEquals(out, ' style="width:320px;"')
end

os.exit(lu.LuaUnit.run())

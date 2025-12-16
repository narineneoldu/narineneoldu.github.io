-- tests/test_core_numeric.lua
require("tests.bootstrap")
local lu = require("luaunit")
local core = require("_hashtag.core")

TestCoreNumeric = {}

------------------------------------------------------------
-- is_numeric_tag
------------------------------------------------------------

function TestCoreNumeric:test_is_numeric_tag_true()
  lu.assertTrue(core.is_numeric_tag("123"))
  lu.assertTrue(core.is_numeric_tag("0"))
end

function TestCoreNumeric:test_is_numeric_tag_false()
  lu.assertFalse(core.is_numeric_tag("123a"))
  lu.assertFalse(core.is_numeric_tag("a123"))
  lu.assertFalse(core.is_numeric_tag("12_3"))
  lu.assertFalse(core.is_numeric_tag(""))
  lu.assertFalse(core.is_numeric_tag(nil))
end

------------------------------------------------------------
-- should_link_numeric
------------------------------------------------------------

function TestCoreNumeric:test_should_link_numeric_disabled()
  local cfg = { hashtag_numbers = 0 }
  lu.assertFalse(core.should_link_numeric("123", cfg))
end

function TestCoreNumeric:test_should_link_numeric_threshold()
  local cfg = { hashtag_numbers = 3 }

  lu.assertFalse(core.should_link_numeric("12", cfg))
  lu.assertTrue(core.should_link_numeric("123", cfg))
  lu.assertTrue(core.should_link_numeric("1234", cfg))
end

function TestCoreNumeric:test_should_link_numeric_non_numeric()
  local cfg = { hashtag_numbers = 3 }

  lu.assertFalse(core.should_link_numeric("abc", cfg))
  lu.assertFalse(core.should_link_numeric("12a", cfg))
end

function TestCoreNumeric:test_should_link_numeric_nil_cfg()
  lu.assertFalse(core.should_link_numeric("123", nil))
end

------------------------------------------------------------

os.exit(lu.LuaUnit.run())

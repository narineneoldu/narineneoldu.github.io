-- tests/test_utf8.lua
require("proxy")
local lu = require("luaunit")

local utf8 = require("_hashtag.utf8")

TestUtf8 = {}

------------------------------------------------------------
-- next_char
------------------------------------------------------------

function TestUtf8:test_next_char_ascii()
  local ch, nexti = utf8.next_char("abc", 1)
  lu.assertEquals(ch, "a")
  lu.assertEquals(nexti, 2)
end

function TestUtf8:test_next_char_utf8()
  local ch, nexti = utf8.next_char("çğ", 1)
  lu.assertEquals(ch, "ç")
  lu.assertEquals(nexti, 3) -- ç = 2 bytes
end

------------------------------------------------------------
-- last_char
------------------------------------------------------------

function TestUtf8:test_last_char_ascii()
  lu.assertEquals(utf8.last_char("abc"), "c")
end

function TestUtf8:test_last_char_utf8()
  lu.assertEquals(utf8.last_char("Straße"), "e")
  lu.assertEquals(utf8.last_char("çğ"), "ğ")
end

function TestUtf8:test_last_char_empty()
  lu.assertEquals(utf8.last_char(""), nil)
end

------------------------------------------------------------
-- char_before_byte
------------------------------------------------------------

function TestUtf8:test_char_before_byte_ascii()
  local s = "abc"
  lu.assertEquals(utf8.char_before_byte(s, 2), "b")
end

function TestUtf8:test_char_before_byte_utf8()
  local s = "çğ"
  -- ç occupies bytes 1–2
  lu.assertEquals(utf8.char_before_byte(s, 2), "ç")
  -- ğ occupies bytes 3–4
  lu.assertEquals(utf8.char_before_byte(s, 4), "ğ")
end

function TestUtf8:test_char_before_byte_misaligned()
  local s = "ç"
  -- byte 1 is a continuation? → should return nil
  lu.assertEquals(utf8.char_before_byte(s, 1), nil)
end

------------------------------------------------------------

os.exit(lu.LuaUnit.run())

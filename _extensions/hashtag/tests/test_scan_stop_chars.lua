-- tests/test_scan_stop_chars.lua
-- Verify STOP_CHAR behavior: hashtag body must stop at punctuation / brackets / operators.

require("proxy")
local lu = require("luaunit")

local Hs = require("helpers_scan")

Hs.monkeypatch_core_for_scan()
local scan = require("_hashtag.scan")

local function assert_stops_at(input, expected_full_text, expected_kind, expected_tag_text)
  local cfg = Hs.cfg_span_only() -- linkify=false => Span expected when converted
  local out = scan.process_inlines({ Hs.Str(input) }, cfg, {}, false)

  lu.assertEquals(Hs.flatten_text(out), expected_full_text)

  if expected_kind == "Span" then
    -- Find first Span
    local found = nil
    for _, el in ipairs(out) do
      if el.t == "Span" then found = el break end
    end
    lu.assertNotNil(found)
    lu.assertEquals(found.content[1].t, "Str")
    lu.assertEquals(found.content[1].text, expected_tag_text)
  elseif expected_kind == "None" then
    -- Ensure nothing converted
    for _, el in ipairs(out) do
      lu.assertNotEquals(el.t, "Span")
      lu.assertNotEquals(el.t, "Link")
    end
  else
    error("Unknown expected_kind: " .. tostring(expected_kind))
  end
end

TestScanStopChars = {}

function TestScanStopChars:test_stops_at_period()
  assert_stops_at("#tag.", "#tag.", "Span", "#tag")
end

function TestScanStopChars:test_stops_at_comma()
  assert_stops_at("#tag, next", "#tag, next", "Span", "#tag")
end

function TestScanStopChars:test_stops_at_semicolon()
  assert_stops_at("#tag; next", "#tag; next", "Span", "#tag")
end

function TestScanStopChars:test_stops_at_colon()
  assert_stops_at("#tag: next", "#tag: next", "Span", "#tag")
end

function TestScanStopChars:test_stops_at_question_mark()
  assert_stops_at("#tag? ok", "#tag? ok", "Span", "#tag")
end

function TestScanStopChars:test_stops_at_exclamation()
  assert_stops_at("#tag! ok", "#tag! ok", "Span", "#tag")
end

function TestScanStopChars:test_stops_at_paren_close()
  assert_stops_at("(#tag) now", "(#tag) now", "Span", "#tag")
end

function TestScanStopChars:test_stops_at_bracket_close()
  assert_stops_at("[#tag] now", "[#tag] now", "Span", "#tag")
end

function TestScanStopChars:test_stops_at_brace_close()
  assert_stops_at("{#tag} now", "{#tag} now", "Span", "#tag")
end

function TestScanStopChars:test_stops_at_angle_brackets()
  assert_stops_at("#tag<rest", "#tag<rest", "Span", "#tag")
  assert_stops_at("#tag>rest", "#tag>rest", "Span", "#tag")
end

function TestScanStopChars:test_stops_at_pipe()
  assert_stops_at("#tag|rest", "#tag|rest", "Span", "#tag")
end

function TestScanStopChars:test_stops_at_slash_and_backslash()
  assert_stops_at("#tag/rest", "#tag/rest", "Span", "#tag")
  assert_stops_at("#tag\\rest", "#tag\\rest", "Span", "#tag")
end

function TestScanStopChars:test_stops_at_math_ops()
  assert_stops_at("#tag+rest", "#tag+rest", "Span", "#tag")
  assert_stops_at("#tag=rest", "#tag=rest", "Span", "#tag")
  assert_stops_at("#tag*rest", "#tag*rest", "Span", "#tag")
end

function TestScanStopChars:test_dash_is_a_stop_char_in_body()
  -- Because '-' is included in COMMON_BOUNDARIES/STOP_CHAR, body stops at '-'
  assert_stops_at("#tag-rest", "#tag-rest", "Span", "#tag")
end

function TestScanStopChars:test_does_not_convert_when_midword_before_hash()
  -- Start boundary check should block conversion: 'a#tag' => no conversion
  assert_stops_at("a#tag.", "a#tag.", "None")
end

os.exit(lu.LuaUnit.run())

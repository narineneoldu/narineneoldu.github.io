-- tests/test_slugify.lua
-- Regression tests for header-slug.lua behavior across multiple languages.
-- These tests validate the current behavior (folding + separators + "unknown Unicode kept").

require("proxy")
local lu = require("luaunit")

-- Require the filter module under test.
-- Assumes header-slug.lua is on package.path (bootstrap typically adds project root).
local slug_filter = require("header_slug")

local function mk_header(text)
  -- Minimal Header object compatible with the filter's expectations.
  return {
    t = "Header",
    level = 1,
    content = { pandoc.Str(text) },
    identifier = "",
    attr = pandoc.Attr("", {}, {})
  }
end

local function run_header(text)
  -- Reset per-document state for determinism
  if slug_filter.Pandoc then slug_filter.Pandoc({}) end
  local h = mk_header(text)
  local out = slug_filter.Header(h) or h
  return out.identifier
end

local function run_headers(texts)
  if slug_filter.Pandoc then slug_filter.Pandoc({}) end
  local ids = {}
  for i, t in ipairs(texts) do
    local h = mk_header(t)
    local out = slug_filter.Header(h) or h
    ids[i] = out.identifier
  end
  return ids
end

TestSlugify = {}

function TestSlugify:test_turkish_i_variants()
  -- Includes İ / I / ı plus apostrophe removal + Turkish diacritics
  local id = run_header("İstanbul'da Işık ve ıhlamur")
  lu.assertEquals(id, "istanbulda-isik-ve-ihlamur")
end

function TestSlugify:test_german_sharp_s()
  -- ß => ss, ä => a
  local id = run_header("Fußgängerstraße")
  lu.assertEquals(id, "fussgangerstrasse")
end

function TestSlugify:test_french_accents_and_apostrophe()
  -- É => e, é => e, ç => c, apostrophe removed, ':' => separator '-'
  local id = run_header("École d'été: façade")
  lu.assertEquals(id, "ecole-dete-facade")
end

function TestSlugify:test_russian_basic_cyrillic_translit()
  -- Cyrillic folded via map: "Привет мир" => "privet-mir"
  local id = run_header("Привет мир")
  lu.assertEquals(id, "privet-mir")
end

function TestSlugify:test_greek_basic_translit()
  -- Note: this uses the *current* simplistic mapping (υ => y),
  -- so "σου" becomes "soy" (not "sou").
  local id = run_header("Γεια σου Κοσμε")
  lu.assertEquals(id, "geia-soy-kosme")
end

function TestSlugify:test_chinese_kept_as_is_with_separators()
  -- Unknown Unicode is preserved, whitespace collapses to '-'
  local id = run_header("中文 标题")
  lu.assertEquals(id, "中文-标题")
end

function TestSlugify:test_japanese_kept_as_is()
  -- Unknown Unicode preserved; no spaces => unchanged slug
  local id = run_header("日本語の見出し")
  lu.assertEquals(id, "日本語の見出し")
end

function TestSlugify:test_arabic_kept_as_is_with_separators()
  -- Unknown Unicode preserved; whitespace => '-'
  local id = run_header("عنوان عربي")
  lu.assertEquals(id, "عنوان-عربي")
end

function TestSlugify:test_unique_id_suffixing()
  -- Same base slug should get "-2", "-3", ...
  local ids = run_headers({
    "École d'été: façade",
    "École d'été: façade",
    "École d'été: façade",
  })
  lu.assertEquals(ids[1], "ecole-dete-facade")
  lu.assertEquals(ids[2], "ecole-dete-facade-2")
  lu.assertEquals(ids[3], "ecole-dete-facade-3")
end

os.exit(lu.LuaUnit.run())

-- test_span_duration.lua
-- UTF-8: Türkçe/İngilizce süre kalıpları için yalın test kiti

local function normalize_diacritics(s)
  -- NFD -> NFC benzeri: u + U+0308  => ü / Ü
  s = s:gsub("u\204\136", "ü"):gsub("U\204\136", "Ü")
  -- İhtiyaten i + dotless gibi başka harfleri eklemek istersen buraya
  return s
end

-- Boşluk ayıracı: normal whitespace + NBSP (U+00A0) + NNBSP (U+202F)
local SEP = "[%s\194\160\226\128\175]+"

-- Sayı: 19, 4,5, 4.5
local NUM = "%d+[.,]?%d*"

-- Aralık: 3-6 / 3–6 / 3—6
local RANGE = "(" .. NUM .. ")%s*[-–—]%s*(" .. NUM .. ")"

-- Üniteler (TR): ü/ı varyantlarına hoşgörülü ve non-alfa sınırı
local UNITS_TR = {
  -- gün
  { patt = "gün%f[%A]", class = "day" },
  { patt = "Gun%f[%A]", class = "day" },
  { patt = "Gün%f[%A]", class = "day" },
  { patt = "gun%f[%A]", class = "day" },
  { patt = "GUN%f[%A]", class = "day" },

  -- ay
  { patt = "ay%f[%A]",  class = "month" },
  { patt = "Ay%f[%A]",  class = "month" },
  { patt = "AY%f[%A]",  class = "month" },

  -- yıl / yil
  { patt = "yıl%f[%A]", class = "year" },
  { patt = "Yıl%f[%A]", class = "year" },
  { patt = "YIL%f[%A]", class = "year" },
  { patt = "yil%f[%A]", class = "year" },
  { patt = "Yil%f[%A]", class = "year" },
  { patt = "YIL%f[%A]", class = "year" },

  -- saat
  { patt = "saat%f[%A]", class = "hour" },

  -- dakika
  { patt = "dakika%f[%A]", class = "minute" },
  { patt = "Dakika%f[%A]", class = "minute" },
  { patt = "DAKIKA%f[%A]", class = "minute" },
}

-- Üniteler (EN): tekil/çoğul ve non-alfa sınırı
local UNITS_EN = {
  { patt = "[Dd]ay[s]?%f[%A]",     label = "EN:day"    },
  { patt = "[Mm]onth[s]?%f[%A]",   label = "EN:month"  },
  { patt = "[Yy]ear[s]?%f[%A]",    label = "EN:year"   },
  { patt = "[Hh]our[s]?%f[%A]",    label = "EN:hour"   },
  { patt = "[Mm]inute[s]?%f[%A]",  label = "EN:minute" },
}

-- Tek sayı + ünite
local function patt_single(unit_patt)
  return "(" .. NUM .. ")" .. SEP .. unit_patt
end

-- Aralık + ünite
local function patt_range(unit_patt)
  return RANGE .. SEP .. unit_patt
end

local TESTS = {
  -- TR tek sayılar
  "Yaklaşık 17 gün (artı/eksi) değerlendirildi.",
  "Toplam 6 ay sürebilir.",
  "4,5 yıl sonra tekrar incelenecek.",
  "1.5 dakika bekleyin lütfen.",
  "2 saat içinde döneriz.",
  -- TR aralıklar
  "İyileşme 3-6 gün sürebilir.",
  "Süre 3–6 ay arası değişir.",
  "Cezası 1—3 yıl olabilir.",
  "Bu işlem 0,5–1,5 saat sürer.",
  -- NBSP örneği: 17 gün (U+00A0)
  ("NBSP örneği: 17" .. string.char(0xC2,0xA0) .. "gün sonra randevu."),
  -- NNBSP örneği: 3 – 6 ay (U+202F)
  ("NNBSP örneği: 3" .. string.char(0xE2,0x80,0xAF) .. "–" .. string.char(0xE2,0x80,0xAF) .. "6 ay kaldı."),
  -- Decomposed 'ü' (u + U+0308) ile "gün"
  ("Decomposed: 17 g" .. "u" .. string.char(0xCC,0x88) .. "n içinde sonuç."),
  -- EN tek sayılar
  "Approximately 17 days are needed.",
  "Project may take 6 months.",
  "After 4.5 years we review.",
  "Wait 1.5 minutes please.",
  "Back in 2 hours.",
  -- EN aralıklar
  "Recovery takes 3-6 days.",
  "It varies between 3–6 months.",
  "Penalty could be 1—3 years.",
  "This step lasts 0.5–1.5 hours.",
}

local function scan_line(line, units, lang_label)
  local s = normalize_diacritics(line)
  local hits = {}

  for _, u in ipairs(units) do
    -- 1) Range
    local pr = patt_range(u.patt)
    local i = 1
    while true do
      local a,b,n1,n2 = s:find(pr, i)
      if not a then break end
      table.insert(hits, {
        lang = lang_label,
        unit = u.label,
        kind = "range",
        s = a, e = b,
        n1 = n1, n2 = n2,
        match = s:sub(a,b)
      })
      i = b + 1
    end
    -- 2) Single
    local ps = patt_single(u.patt)
    i = 1
    while true do
      local a,b,n = s:find(ps, i)
      if not a then break end
      table.insert(hits, {
        lang = lang_label,
        unit = u.label,
        kind = "single",
        s = a, e = b,
        n1 = n, n2 = nil,
        match = s:sub(a,b)
      })
      i = b + 1
    end
  end

  table.sort(hits, function(A,B)
    if A.s ~= B.s then return A.s < B.s end
    return A.e < B.e
  end)

  return s, hits
end

local function dump_hits(original, normed, hits)
  if #hits == 0 then
    print("  (no match)")
    return
  end
  for _, h in ipairs(hits) do
    print(string.format("  [%s][%s][%s] %d-%d  «%s»  n1=%s n2=%s",
      h.lang, h.unit, h.kind, h.s, h.e, h.match, tostring(h.n1), tostring(h.n2)))
  end
end

-- ---- RUN ----
for idx, line in ipairs(TESTS) do
  print(string.rep("-", 72))
  print(string.format("Case %02d: %s", idx, line))
  local norm, hitsTR = scan_line(line, UNITS_TR, "TR")
  local _,    hitsEN = scan_line(line, UNITS_EN, "EN")

  -- Çakışmaları birleştirip yaz
  local all = {}
  for _,h in ipairs(hitsTR) do table.insert(all,h) end
  for _,h in ipairs(hitsEN) do table.insert(all,h) end
  table.sort(all, function(A,B)
    if A.s ~= B.s then return A.s < B.s end
    return A.e < B.e
  end)

  dump_hits(line, norm, all)
end

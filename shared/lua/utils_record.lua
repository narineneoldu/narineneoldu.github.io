-- ../shared/lua/utils_record_number.lua
-- Kayıt / karar / esas / madde numaralarını tespit eder.
-- Örnekler:
--   "1 ve 2. maddesi", "1. ve 2. maddesi"
--   "82/1-d-e maddesi", "2024-109 sayılı karar", "37. maddesi"
--
-- Public API:
--   M.find_record_numbers(text) -> { { s = i1, e = j1, kind = "record-number" }, ... }

local M = {}

-- space, NBSP (00A0), NNBSP (202F)
local SP = "[%s\194\160\226\128\175]+"

-- ---- yardımcılar ----

local function is_url_context(s, lpos)
  local from = math.max(1, lpos - 12)
  return s:sub(from, lpos):find("://") ~= nil
end

local KEYWORD_STEMS = {
  "numara",
  "sayili",
  "esas",
  "karar sayili",
  "madde",
  "fıkra",
}

local function ascii_fold(s)
  -- Türkçe temel katlama: ı/İ/I -> i
  s = s:gsub("İ", "i"):gsub("I", "i"):gsub("ı", "i")
  -- Gerekirse buraya başka aksan kaldırmaları da eklenebilir
  return s
end

local function has_following_keyword(text, rpos)
  -- sayının hemen sonrasını al
  local tail = text:sub(rpos)

  -- baştaki boşluk / NBSP / NNBSP / parantez-noktalama / çeşitli tireleri temizle
  tail = tail:gsub("^[%s\194\160\226\128\175%.,;:%(%)]*", "")
  tail = tail:gsub("^[%-\226\128\147\226\128\148\226\128\146\226\128\145\226\136\146]*", "")

  -- İlk kelime
  local w1 = tail:match("^([%a\128-\255]+)")
  if not w1 then return false end

  -- w1 sonrası ayırıcıları atıp ikinci kelimeyi de dene (opsiyonel)
  local after_w1 = tail:sub(#w1 + 1)
  after_w1 = after_w1:gsub("^[%s\194\160\226\128\175%-\226\128\147\226\128\148\226\128\146\226\128\145\226\136\146]+", "")
  local w2 = after_w1:match("^([%a\128-\255]+)")

  -- adaylar: tek kelime ve iki kelime birleştirilmiş
  local cand1 = (w1 or "")
  local cand2 = (w1 or "") .. " " .. (w2 or "")  -- "karar sayili" gibi

  cand1 = ascii_fold(cand1):lower()
  cand2 = ascii_fold(cand2):lower()

  for _, stem in ipairs(KEYWORD_STEMS) do
    local s = ascii_fold(stem)
    if s:find(" ", 1, true) then
      -- iki kelimelik kök ("karar sayili")
      if cand2:sub(1, #s) == s then return true end
    else
      -- tek kelimelik kök ("madde", "esas", "sayili" vs.)
      if cand1:sub(1, #s) == s then return true end
    end
  end

  return false
end

-- ---- ana dedektör ----

local function find_hits(text)
  local hits = {}

  -- 1) ÇİFT SAYI: "N[.] ve M[.]" + ardından anahtar
  --    Örn: "1 ve 2. maddesi", "1. ve 2. maddesi"
  --    Sadece sayıları span’liyoruz, nokta hariç.
  for lpos1, num1, lpos2, num2, rpos2 in
    text:gmatch("()(%d+)%.?" .. SP .. "[Vv][Ee]" .. SP .. "()(%d+)%.?()")
  do
    -- solda bitişik harf/rakam olmasın
    local prev_is_word =
      (lpos1 > 1)
      and text:sub(lpos1 - 1, lpos1 - 1):match("[%w]") ~= nil

    if not prev_is_word
       and not is_url_context(text, lpos1)
       and has_following_keyword(text, rpos2) then

      local e1 = lpos1 + #num1 - 1
      local e2 = lpos2 + #num2 - 1

      hits[#hits+1] = { s = lpos1, e = e1 }
      hits[#hits+1] = { s = lpos2, e = e2 }
    end
  end

  -- 2) TEK TOKEN: "82/1-d-e", "2024-109", "37." + ardından anahtar
  --    Token sonundaki opsiyonel noktayı hariç tutuyoruz.
  for lpos, tok, dot, rpos in
    text:gmatch("()%f[%d](%d[%w%-/⁄∕]*)(%.?)()")
  do
    local prev_is_word =
      (lpos > 1)
      and text:sub(lpos - 1, lpos - 1):match("[%w]") ~= nil

    if not prev_is_word
       and not is_url_context(text, lpos)
       and has_following_keyword(text, rpos) then

      local e_core = lpos + #tok - 1  -- son nokta hariç
      hits[#hits+1] = { s = lpos, e = e_core }
    end
  end

  -- Çakışmaları sadeleştir (erken eklenen çiftler kalsın)
  table.sort(hits, function(a, b)
    return a.s < b.s or (a.s == b.s and a.e < b.e)
  end)

  local out = {}
  for _, h in ipairs(hits) do
    local keep = true
    for _, k in ipairs(out) do
      if not (h.e < k.s or h.s > k.e) then
        keep = false
        break
      end
    end
    if keep then
      out[#out+1] = h
    end
  end

  return out
end

-- ---- Public API ----

function M.find(text)
  local raw = find_hits(text)
  local out = {}

  for _, h in ipairs(raw) do
    out[#out+1] = {
      s    = h.s,
      e    = h.e,
      kind = "record",
    }
  end

  return out
end

return M

-- ../shared/lua/utils_unit.lua
-- TR units: yıl/sene, ay, hafta, saat, dakika, saniye, metre/km, santimetre/cm
-- Supports: ranges (X–Y, X ile Y), "yarım + birim", suffixed forms
-- Guards:   HH:MM minutes & dd.mm.yyyy dates
--
-- Public API:
--   M.find_units(text) -> { { s = i1, e = j1, kind = "unit", class = "year" }, ... }

local M = {}

-- -------- patterns & guards ----------
local NBSP = "\194\160"  -- U+00A0, TL öncesinde kullanılabiliyor
local NUM    = "%d+[.,]?%d*"  -- 19 / 2,5 / 2.5
local DASHES = { "-", "\226\128\147", "\226\128\148", "\226\128\146", "\226\128\145", "\226\136\146", "x" }
local SP     = "[%s\194\160\226\128\175]+"  -- space, NBSP (00A0), NNBSP (202F)
local APOS   = "['\226\128\153\226\128\152\202\188]" -- ', ’, ‘, ʼ

-- HH:MM guard
local function is_after_HHMM(s, start_idx)
  local L = math.max(1, start_idx - 5)
  local left = s:sub(L, start_idx - 1)
  return left:match("%d%d?%s*:%s*$") ~= nil
end

-- dd.mm.yyyy guard
local function inside_date_ddmmyyyy(s, a, b)
  local L = math.max(1, a - 5)
  local p, q = s:find("%d%d?%.%d%d?%.%d%d%d%d", L)
  while p do
    if not (q < a or p > b) then return true end
    p, q = s:find("%d%d?%.%d%d?%.%d%d%d%d", q + 1)
  end
  return false
end

local function overlaps(a, b, r)
  return not (b < r.s or a > r.e)
end

-- suffix whitelist (ayrı'yı elememek için 'r' yok vs.)
-- l,d,t,n,m,s,c,ç,ğ,y + sesliler (a,e,ı,i,o,ö,u,ü)
local SUF_START = "[ealdtnmscyEALDTNMSCY\195\167\196\159yaei\196\177io\195\182u\195\188]"
local SUF       = SUF_START .. "[A-Za-z\128-\255]*"

-- TR unit patterns (ham tablo + money satırı)
local RAW_TR_UNITS = {
  { pats = { "[Yy]ıl", "[Ss]ene", "YIL", "SENE" },       class = "year"       },
  { pats = { "[Aa]y", "AY" },                            class = "month"      },
  { pats = { "[Hh]afta", "HAFTA" },                      class = "week"       },
  { pats = { "[Ss]aat", "SAAT" },                        class = "hour"       },
  { pats = { "[Dd]akika", "DAKİKA" },                    class = "minute"     },
  { pats = { "[Ss]aniye", "SANİYE" },                    class = "second"     },
  { pats = { "[Mm]etre", "[Kk]ilometre", "[Kk][Mm]",
             "METRE", "KİLOMETRE" },             class = "meter" },
  { pats = { "[Ss]antimetre", "[Cc][Mm]", "[Ss]antim",
             "SANTİMETRE", "SANTİM" },                   class = "centimeter" },
  { pats = { "[Aa]det", "[Pp]arça", "[Tt]aş",
             "ADET", "PARÇA", "TAŞ" },                   class = "item"       },
  { pats = { "[Tt][Ll]", "[Ll]ira", "LİRA" },            class = "money"      },
}

-- "yarım" variants
local HALF_TOKS = { "[Yy]arım", "YARIM" }

local TR_UNITS  = {}   -- sadece gerçek "unit"’ler (money hariç)
local HAS_MONEY = false
local MONEY_PATS = nil

for _, spec in ipairs(RAW_TR_UNITS) do
  if spec.class == "money" then
    HAS_MONEY  = true
    MONEY_PATS = spec.pats or {}
  else
    TR_UNITS[#TR_UNITS + 1] = spec
  end
end

-- ---------- core helpers ----------

local function push_hit(hits, s, i, j, class)
  if not inside_date_ddmmyyyy(s,i,j) and not is_after_HHMM(s,i) then
    -- DO NOT shift i to include left space: keep the space outside the span
    for _, r in ipairs(hits) do
      if not (j < r.s or i > r.e) then
        return
      end
    end
    hits[#hits+1] = { s = i, e = j, class = class }
  end
end

-- safe tail: whitespace / punct / NBSP / NNBSP / EOL
local function safe_tail(s, head, token, class, hits)
  local PUNCT = "[%s,%.;:!%?%-%(%)]"

  -- ASCII whitespace/punct
  for a, b in s:gmatch(head .. token .. "()" .. PUNCT) do
    push_hit(hits, s, a, b-1, class)
  end
  -- NBSP
  for a, b in s:gmatch(head .. token .. "()\194\160") do
    push_hit(hits, s, a, b-1, class)
  end
  -- NNBSP
  for a, b in s:gmatch(head .. token .. "()\226\128\175") do
    push_hit(hits, s, a, b-1, class)
  end
  -- end of line
  for a, t2 in s:gmatch(head .. token .. "()$") do
    push_hit(hits, s, a, t2-1, class)
  end
end

local function hits_with_token(s, token, class, hits)
  -- "yarım + unit"
  for _, H in ipairs(HALF_TOKS) do
    -- with apostrophe
    for a, b in s:gmatch("()"..H..SP..token.."()"..APOS) do
      push_hit(hits, s, a, b-1, class)
    end
    -- apostrophe-less -> safe tail
    safe_tail(s, "()"..H..SP, token, class, hits)
  end

  -- verbal range: NUM ile/ila NUM unit
  for _, CC in ipairs({ "ile", "ila", "İLE", "İLA" }) do
    -- apostrophe
    for a, b in s:gmatch("()"..NUM..SP..CC..SP..NUM..SP..token.."()"..APOS) do
      push_hit(hits, s, a, b-1, class)
    end
    -- no apostrophe -> safe tail
    safe_tail(s, "()"..NUM..SP..CC..SP..NUM..SP, token, class, hits)
  end

  -- dashed range: NUM – NUM unit
  for _, D in ipairs(DASHES) do
    -- apostrophe
    for a, b in s:gmatch("()"..NUM.."%s*"..D.."%s*"..NUM..SP..token.."()"..APOS) do
      push_hit(hits, s, a, b-1, class)
    end
    -- no apostrophe -> safe tail
    safe_tail(s, "()"..NUM.."%s*"..D.."%s*"..NUM..SP, token, class, hits)
  end

  -- single: NUM unit
  -- with apostrophe
  for a, b in s:gmatch("()"..NUM..SP..token.."()"..APOS) do
    push_hit(hits, s, a, b-1, class)
  end
  -- no apostrophe -> safe tail
  safe_tail(s, "()" .. NUM .. SP, token, class, hits)
end

local function has_trace(text)
  -- hiç rakam yoksa, sadece "yarım" izine bak
  if not text:find("%d") then
    for _, H in ipairs(HALF_TOKS) do
      if text:find(H) then
        return true
      end
    end
    return false
  end

  -- unit izleri (money yok, çünkü TR_UNITS filtrenmiş)
  for _, spec in ipairs(TR_UNITS) do
    for _, pat in ipairs(spec.pats) do
      if text:find(pat) then
        return true
      end
    end
  end

  -- para izleri: sadece money tanımı varsa bak
  if HAS_MONEY and MONEY_PATS then
    for _, pat in ipairs(MONEY_PATS) do
      if text:find(pat) then
        return true
      end
    end
  end

  return false
end

local function find_tr_money(text, hits)
  -- NBSP → normal boşluk (uzunluk değişmez, indexler aynı kalır)
  local s = text:gsub(NBSP, " ")

  -- "48.000,00 TL" veya "1.200,50 TL"
  local PAT_DEC = '(%f[%d]%d[%d%.]*,%d%d)%s*[Tt][Ll]'
  -- "1200 TL", "1.200 TL"
  local PAT_INT = '(%f[%d]%d[%d%.]*)%s*[Tt][Ll]'

  local i, n = 1, #s
  while i <= n do
    local a1, b1, num1 = s:find(PAT_DEC, i)
    local a2, b2, num2 = s:find(PAT_INT, i)

    local a, b, num

    if a1 and (not a2 or a1 <= a2) then
      a, b, num = a1, b1, num1
    elseif a2 then
      a, b, num = a2, b2, num2
      -- sonu noktayla biten tam sayı (örn. "1.200.") ise atla
      if num:sub(-1) == "." then
        i = a2 + 1
        goto continue_tl
      end
    else
      break
    end

    -- mevcut hit'lerle çakışmasın
    local keep = true
    for _, r in ipairs(hits) do
      if overlaps(a, b, r) then
        keep = false
        break
      end
    end
    if keep then
      hits[#hits+1] = { s = a, e = b, class = "money" }
    end

    i = b + 1
    ::continue_tl::
  end

  -- "500 lira" / "2.500 lira"
  i, n = 1, #s
  while true do
    local a, b, num = s:find("(%f[%d]%d[%d%.]*)%s*[Ll]ira%f[%A]", i)
    if not a then break end

    if num:sub(-1) == "." then
      i = a + 1
    else
      local keep = true
      for _, r in ipairs(hits) do
        if overlaps(a, b, r) then
          keep = false
          break
        end
      end
      if keep then
        hits[#hits+1] = { s = a, e = b, class = "money" }
      end
      i = b + 1
    end
  end
end

local function find_raw_hits(text)
  if not has_trace(text) then return {} end

  local hits = {}
  for _, spec in ipairs(TR_UNITS) do
    for _, pat in ipairs(spec.pats) do
      -- bare unit
      hits_with_token(text, pat, spec.class, hits)
      -- suffixed unit (pat + suffix)
      hits_with_token(text, pat .. SUF, spec.class, hits)
    end
  end

  -- 2) money: sadece HAS_MONEY true ise
  if HAS_MONEY then
    find_tr_money(text, hits)
  end

  -- de-overlap: keep longer ranges
  table.sort(hits, function(a, b)
    return a.s < b.s or (a.s == b.s and a.e < b.e)
  end)

  local out = {}
  for _, h in ipairs(hits) do
    local keep = true
    for _, k in ipairs(out) do
      if overlaps(h.s, h.e, k) then
        if (h.e - h.s) <= (k.e - k.s) then
          keep = false
        end
      end
    end
    if keep then
      out[#out+1] = h
    end
  end

  return out
end

-- -------- PUBLIC API ----------
function M.find(text)
  local raw = find_raw_hits(text)
  local out = {}
  for _, h in ipairs(raw) do
    out[#out+1] = {
      s     = h.s,
      e     = h.e,
      kind  = "unit",   -- span_multi merge & priority
      class = h.class,  -- "year", "month", "meter", ...
    }
  end
  return out
end

return M

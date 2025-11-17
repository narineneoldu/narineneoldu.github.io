-- ../shared/lua/utils_unit_en.lua
-- EN units: day, month, year, hour, minute, second, meter, cm, kg, item...
-- Supports:
--   - ranges: X–Y, "X with Y", "X and Y"
--   - "half (+ a/an) + unit"
--   - hyphenated: "41-second", "19-day", "half-hour", "half-day"
-- Guards:
--   - HH:MM (minutes)
--   - dd.mm.yyyy dates
--
-- Public API:
--   M.find(text) -> { { s = i1, e = j1, kind = "unit", class = "year" }, ... }

local M = {}

-- -------- patterns & guards ----------
local NBSP   = "\194\160"      -- U+00A0
local NNBSP  = "\226\128\175"  -- U+202F
local NUM    = "%d+[.,]?%d*"
local DASHES = { "-", "\226\128\147", "\226\128\148", "\226\128\146", "\226\128\145", "\226\136\146", "x" }
local SP     = "[%s\194\160\226\128\175]+"   -- space, NBSP, NNBSP
local BND    = "%f[%A]"                     -- non-letter frontier
local APOS   = "['\226\128\153\226\128\152\202\188]" -- ', ’, ‘, ʼ

-- HH:MM guard (avoid treating the MM of HH:MM as minutes)
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
    if not (q < a or p > b) then
      return true
    end
    p, q = s:find("%d%d?%.%d%d?%.%d%d%d%d", q + 1)
  end
  return false
end

local function overlaps(a, b, r)
  return not (b < r.s or a > r.e)
end

-- English unit patterns (HAM tablo + money satırı)
local RAW_EN_UNITS = {
  { pats = { "[Dd]ay[s]?" },                                 class = "day"        },
  { pats = { "[Mm]onth[s]?" },                               class = "month"      },
  { pats = { "[Yy]ear%-old" },                               class = "year-old"   },
  { pats = { "[Yy]ear[s]?" },                                class = "year"       },
  { pats = { "[Hh]our[s]?" },                                class = "hour"       },
  { pats = { "[Mm]inute[s]?" },                              class = "minute"     },
  { pats = { "[Ss]econd[s]?" },                              class = "second"     },
  { pats = { "[Ww]eek[s]?" },                                class = "week"       },
  { pats = { "[Mm]eter[s]?", "[Kk]ilometer[s]?", "km" },     class = "meter"      },
  { pats = { "[Cc]entimeter[s]?", "cm" },                    class = "centimeter" },
  { pats = { "[Kk]ilogram[s]?", "kg" },                      class = "kilogram"   },
  { pats = { "[Ii]tem[s]?", "[Pp]iece[s]?", "[Pp]art[s]?" }, class = "item"       },
  { pats = { "[Ss]tone[s]?" },                               class = "stone"      },
  { pats = { "[Tt][Rr][Yy]", "[Ll]ira" },                    class = "money"      },
}

local HALF_TOKS = { "half", "Half" }

-- EN_UNITS: money hariç gerçek unit’ler
local EN_UNITS  = {}
local HAS_MONEY = false
local MONEY_PATS = nil

for _, spec in ipairs(RAW_EN_UNITS) do
  if spec.class == "money" then
    HAS_MONEY  = true
    MONEY_PATS = spec.pats or {}
  else
    EN_UNITS[#EN_UNITS + 1] = spec
  end
end

-- ---------- core helpers ----------

local function push_hit(hits, s, i, j, class)
  if inside_date_ddmmyyyy(s, i, j) or is_after_HHMM(s, i) then
    return
  end
  -- do NOT shift i to include left space: keep the space outside the span
  for _, r in ipairs(hits) do
    if overlaps(i, j, r) then
      return
    end
  end
  hits[#hits+1] = { s = i, e = j, class = class }
end

local function hits_with_token(s, token, class, hits)
  -- half + unit
  for _, H in ipairs(HALF_TOKS) do
    -- "half unit"
    for a, b in s:gmatch("()"..H..SP..token..BND.."()") do
      push_hit(hits, s, a, b-1, class)
    end
    -- "half a/an unit"
    for a, b in s:gmatch("()"..H..SP.."[Aa]n?"..SP..token..BND.."()") do
      push_hit(hits, s, a, b-1, class)
    end
    -- hyphenated: "half-unit" / "half–unit"
    for _, D in ipairs(DASHES) do
      for a, b in s:gmatch("()"..H.."%s*"..D.."%s*"..token..BND.."()") do
        push_hit(hits, s, a, b-1, class)
      end
    end
  end

  -- verbal range: "X with/and Y unit"
  for _, CC in ipairs({ "with", "and" }) do
    for a, b in s:gmatch("()"..NUM..SP..CC..SP..NUM..SP..token..BND.."()") do
      push_hit(hits, s, a, b-1, class)
    end
  end

  -- dashed range: "X–Y unit"
  for _, D in ipairs(DASHES) do
    for a, b in s:gmatch("()"..NUM.."%s*"..D.."%s*"..NUM..SP..token..BND.."()") do
      push_hit(hits, s, a, b-1, class)
    end
  end

  -- single: "NUM unit"
  for a, b in s:gmatch("()"..NUM..SP..token..BND.."()") do
    push_hit(hits, s, a, b-1, class)
  end

  -- hyphenated single: "NUM-unit" (e.g., 41-second, 19-day)
  for _, D in ipairs(DASHES) do
    for a, b in s:gmatch("()"..NUM.."%s*"..D.."%s*"..token..BND.."()") do
      push_hit(hits, s, a, b-1, class)
    end
  end
end

local function has_trace(text)
  -- no digit -> only check "half" variants
  if not text:find("%d") then
    for _, H in ipairs(HALF_TOKS) do
      if text:find(H) then
        return true
      end
    end
    return false
  end

  -- unit izleri (money hariç)
  for _, spec in ipairs(EN_UNITS) do
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

local function find_en_money(text, hits)
  if not HAS_MONEY then
    return
  end

  -- NBSP/NNBSP → space (uzunluk korunuyor)
  local s = text:gsub(NBSP, " "):gsub(NNBSP, " ")

  local SP_RE = SP

  -- "TRY 48,000.00"
  local PAT_DEC = '(%f[%a][Tt][Rr][Yy]' .. SP_RE .. '%d[%d,]*%.%d%d)'
  -- "TRY 1,200" / "TRY 1200"
  local PAT_INT = '(%f[%a][Tt][Rr][Yy]' .. SP_RE .. '%d[%d,]*)'

  local i, n = 1, #s
  while i <= n do
    local a1, b1, grp1 = s:find(PAT_DEC, i)
    local a2, b2, grp2 = s:find(PAT_INT, i)

    local a, b, grp

    if a1 and (not a2 or a1 <= a2) then
      a, b, grp = a1, b1, grp1
    elseif a2 then
      a, b, grp = a2, b2, grp2
      local num = grp:match("(%d[%d,]*)$") or ""
      if num:sub(-1) == "," then
        i = a2 + 1
        goto continue_try
      end
    else
      break
    end

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
    ::continue_try::
  end

  -- "500 lira" (Türkçe kelime ama İngilizce metinde de geçebilir)
  i, n = 1, #s
  while true do
    local a, b, num = s:find("(%f[%d]%d[%d,%.]*)%s*[Ll]ira%f[%A]", i)
    if not a then break end

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

local function find_raw_hits(text)
  if not has_trace(text) then
    return {}
  end

  local hits = {}

  -- 1) units (money hariç)
  for _, spec in ipairs(EN_UNITS) do
    for _, pat in ipairs(spec.pats) do
      hits_with_token(text, pat, spec.class, hits)
    end
  end

  -- 2) money (TRY / lira) — sadece HAS_MONEY true ise
  if HAS_MONEY then
    find_en_money(text, hits)
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
      kind  = "unit",      -- for span_multi merge & priority
      class = h.class,     -- "year", "month", "second", "money", ...
    }
  end
  return out
end

return M

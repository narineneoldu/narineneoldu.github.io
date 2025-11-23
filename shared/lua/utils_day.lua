-- ../shared/lua/utils_day.lua
-- "gün" ile ilgili süre ibarelerini tespit eder (TR).
-- Public API:
--   M.find_days(text) -> { { s = i1, e = j1, kind = "day" }, ... }

local M = {}

-- ---------- desenler / sabitler ----------
local NUM   = "%d+[.,]?%d*"
local DASHES = {
  "-",        -- ASCII
  "\226\128\147", -- – en dash
  "\226\128\148", -- — em dash
  "\226\128\146", -- ‘
  "\226\128\145", -- ‘ (farklı tırnak varyantları)
  "\226\136\146", -- ‒ figure dash vb.
}
local SP   = "[%s\194\160\226\128\175]+"  -- space, NBSP, NNBSP
local APOS = "['\226\128\153\226\128\152\202\188]" -- ' ’ ‚ vb.

-- "gün" kökleri
local base = "gün"
local suffixes = { "", "e", "den", "dür", "lük", "lüğüne" }

local ROOTS_DAY = {}
for _, suf in ipairs(suffixes) do
  ROOTS_DAY[#ROOTS_DAY + 1] = base .. suf
end

local HALF_TOKS = { "yar\196\177m" } -- "yarım"

-- ---------- yardımcılar ----------

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

local function is_after_HHMM(s, start_idx)
  local L = math.max(1, start_idx - 5)
  return s:sub(L, start_idx - 1):match("%d%d?%s*:%s*$") ~= nil
end

local function include_left_space(s, i)
  if i > 1 and s:sub(i - 1, i - 1):match("[%s\194\160\226\128\175]") then
    return i - 1
  end
  return i
end

local function push_hit(hits, s, a, b, class)
  if not inside_date_ddmmyyyy(s, a, b) and not is_after_HHMM(s, a) then
    a = include_left_space(s, a)
    hits[#hits + 1] = { s = a, e = b, class = class }
  end
end

-- --- Türkçe büyük harf & capitalize ---
local function tr_upper(str)
  return (str
    :gsub("ü","Ü"):gsub("ö","Ö"):gsub("ç","Ç"):gsub("ş","Ş"):gsub("ğ","Ğ")
    :gsub("ı","I"):gsub("i","İ")
    :upper())
end

local function tr_capitalize(str)
  if str == "" then return str end
  local first = str:sub(1,1)
  local rest  = str:sub(2)
  return tr_upper(first) .. rest
end

local function is_flat_array(t)
  local n = 0
  for k, _ in pairs(t) do
    if type(k) ~= "number" then return false end
    if k > n then n = k end
  end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

local function expand_list(lst)
  local out, seen = {}, {}
  local function add(x)
    if not seen[x] then
      seen[x] = true
      out[#out + 1] = x
    end
  end
  for _, root in ipairs(lst) do
    add(root)
    add(tr_capitalize(root))
    add(tr_upper(root))
  end
  return out
end

local function expand_case_forms(roots)
  if is_flat_array(roots) then
    return expand_list(roots)
  else
    local out = {}
    for cls, lst in pairs(roots) do
      out[cls] = expand_list(lst)
    end
    return out
  end
end

ROOTS_DAY = expand_case_forms(ROOTS_DAY)
HALF_TOKS = expand_case_forms(HALF_TOKS)

local function safe_tail(s, head, token, class, hits)
  local PUNCT = "[%s,%.;:!%?%-%(%)]"

  for a, b in s:gmatch(head .. token .. "()" .. PUNCT) do
    if not inside_date_ddmmyyyy(s, a, b) and not is_after_HHMM(s, a) then
      a = include_left_space(s, a)
      hits[#hits + 1] = { s = a, e = b - 1, class = class }
    end
  end

  for a, b in s:gmatch(head .. token .. "()" .. "$") do
    a = include_left_space(s, a)
    hits[#hits + 1] = { s = a, e = b - 1, class = class }
  end
end

local function hits_with_token(s, token, class, hits)
  -- "yarım gün" varyantları
  for _, H in ipairs(HALF_TOKS) do
    -- Apostroflu: "yarım gün’"
    for a, b in s:gmatch("()" .. H .. SP .. token .. "()" .. APOS) do
      push_hit(hits, s, a, b - 1, class)
    end
    -- Apostrofsuz
    safe_tail(s, "()" .. H .. SP, token, class, hits)
  end

  -- "3 ile 5 gün"
  for _, CC in ipairs({"ile", "ila", "İLE", "İLA"}) do
    safe_tail(s, "()" .. NUM .. SP .. CC .. SP .. NUM .. SP, token, class, hits)
  end

  -- "3-5 gün", "3 – 5 gün" vs.
  for _, D in ipairs(DASHES) do
    safe_tail(s, "()" .. NUM .. "%s*" .. D .. "%s*" .. NUM .. SP, token, class, hits)
  end

  -- "3 gün"
  safe_tail(s, "()" .. NUM .. SP, token, class, hits)
end

local function dedupe_hits(hits)
  table.sort(hits, function(a, b)
    if a.s ~= b.s then return a.s < b.s end
    return (a.e - a.s) > (b.e - b.s)
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
    if keep then out[#out + 1] = h end
  end
  return out
end

local function has_trace(text)
  for _, variant in ipairs(ROOTS_DAY) do
    if text:find(variant, 1, true) then
      return true
    end
  end
  return false
end

local function find_hits(text)
  if not has_trace(text) then
    return {}
  end

  local hits = {}
  for _, root in ipairs(ROOTS_DAY) do
    hits_with_token(text, root, "day", hits)
  end
  return dedupe_hits(hits)
end

function M.find(text)
  local raw = find_hits(text)
  local out = {}
  for _, h in ipairs(raw) do
    out[#out + 1] = {
      s    = h.s,
      e    = h.e,
      kind = "day",
    }
  end
  return out
end

return M

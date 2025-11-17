-- ../shared/lua/utils_unit_en.lua
-- EN units: day, month, year, hour, minute, second (plural optional)
-- Supports:
--   - ranges: X–Y, "X with Y", "X and Y"
--   - "half (+ a/an) + unit"
--   - hyphenated: "41-second", "19-day", "half-hour", "half-day"
-- Guards:
--   - HH:MM (minutes)
--   - dd.mm.yyyy dates
--
-- Public API:
--   M.find_units(text) -> { { s = i1, e = j1, kind = "unit", class = "year" }, ... }

local M = {}

-- -------- patterns & guards ----------
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

-- English units (plural optional)
local EN_UNITS = {
  { pat = "[Dd]ay[s]?",        class = "day"        },
  { pat = "[Mm]onth[s]?",      class = "month"      },
  { pat = "[Yy]ear%-old",      class = "year-old"   },
  { pat = "[Yy]ear[s]?",       class = "year"       },
  { pat = "[Hh]our[s]?",       class = "hour"       },
  { pat = "[Mm]inute[s]?",     class = "minute"     },
  { pat = "[Ss]econd[s]?",     class = "second"     },
  { pat = "[Ww]eek[s]?",       class = "week"       },
  { pat = "[Mm]eter[s]?",      class = "meter"      },
  { pat = "[Kk]ilometer[s]?",  class = "meter"      },
  { pat = "km",                class = "meter"      },
  { pat = "[Cc]entimeter[s]?", class = "centimeter" },
  { pat = "cm",                class = "centimeter" },
  { pat = "[Kk]ilogram[s]?",   class = "kilogram"   },
  { pat = "kg",                class = "kilogram"   },
}

local HALF_TOKS = { "half", "Half" }

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

  -- scan unit patterns
  for _, spec in ipairs(EN_UNITS) do
    if text:find(spec.pat) then
      return true
    end
  end

  return false
end

local function find_raw_hits(text)
  if not has_trace(text) then
    return {}
  end

  local hits = {}

  for _, spec in ipairs(EN_UNITS) do
    hits_with_token(text, spec.pat, spec.class, hits)
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
      class = h.class,     -- "year", "month", "second", ...
    }
  end
  return out
end

return M

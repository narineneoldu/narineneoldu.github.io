-- ../shared/lua/utils_date_en.lua
-- English date detection utilities.
-- Returns hit ranges with kind = "date" for use by span_multi.lua.

local M = {}

-- English months (full + abbreviations)
local MONTHS_EN = {
  "January","Jan","February","Feb","March","Mar","April","Apr","May",
  "June","Jun","July","Jul","August","Aug","September","Sept","Sep",
  "October","Oct","November","Nov","December","Dec"
}

-- frontier-safe numeric EN patterns: MM/DD and MM/DD/YYYY
local PAT_MMDD     = '(%f[%d]%d%d?)/(%d%d?%f[%D])'
local PAT_MMDDYYYY = '(%f[%d]%d%d?)/(%d%d?)/(%d%d%d%d%f[%D])'

local function valid_mmdd(m, d)
  local mm, dd = tonumber(m), tonumber(d)
  if not mm or not dd then return false end
  if mm < 1 or mm > 12 then return false end
  if dd < 1 or dd > 31 then return false end
  return true
end

-- Case-insensitive pattern builder for ASCII letters
local function ci_pat(s)
  return (s:gsub("%a", function(c)
    local lo, up = string.lower(c), string.upper(c)
    if lo == up then return c end
    return "[" .. lo .. up .. "]"
  end))
end

-- ---- EN date finder:
--   Numeric: "08/21/2024", "8/3/2024", "08/21"
--   Textual: "August 21, 2024", "August 21 2024", "21 August 2024", "August 21"
local function find_en_dates(text)
  local hits = {}

  -- 1) Numeric date: "08/21/2024"
  do
    local pos = 1
    while true do
      local a, b, m, d, y = text:find(PAT_MMDDYYYY, pos)
      if not a then break end
      if valid_mmdd(m, d) then
        table.insert(hits, { s = a, e = b })
      end
      pos = b + 1
    end
  end

  -- 1b) Numeric date without year: "08/21"
  do
    local p = 1
    while true do
      local a, b, m, d = text:find(PAT_MMDD, p)
      if not a then break end
      if valid_mmdd(m, d) then
        -- If immediately followed by "/YYYY", it is part of MM/DD/YYYY; skip.
        local tail = text:sub(b + 1, b + 5)
        if not tail:match("^/%d%d%d%d") then
          table.insert(hits, { s = a, e = b })
        end
      end
      p = b + 1
    end
  end

  -- 2) Textual English dates
  for _, mon in ipairs(MONTHS_EN) do
    local mon_pat = "%f[%a]" .. ci_pat(mon) .. "%f[%A]"

    -- A) "Month D, YYYY" or "Month D YYYY"
    do
      local p = 1
      while true do
        local a, b = text:find(mon_pat .. "%s+(%d%d?)%s*,?%s*(%d%d%d%d)", p)
        if not a then break end
        table.insert(hits, { s = a, e = b })
        p = b + 1
      end
    end

    -- A2) Day range before month: "27-31 August 2024" / "27–31 August 2024"
    do
      local p = 1
      while true do
        local a, b = text:find("(%d%d?)%s*[-–]%s*(%d%d?)%s+" .. mon_pat .. "%s+(%d%d%d%d)", p)
        if not a then break end
        table.insert(hits, { s = a, e = b })
        p = b + 1
      end
    end

    -- A3) Day range with 'and': "27 and 31 August 2024"
    do
      local p = 1
      while true do
        local a, b = text:find("(%d%d?)%s+[Aa][Nn][Dd]%s+(%d%d?)%s+" .. mon_pat .. "%s+(%d%d%d%d)", p)
        if not a then break end
        table.insert(hits, { s = a, e = b })
        p = b + 1
      end
    end

    -- B) "D Month YYYY"
    do
      local p = 1
      while true do
        local a, b = text:find("(%d?%d)%s+" .. mon_pat .. "%s+(%d%d%d%d)", p)
        if not a then break end
        table.insert(hits, { s = a, e = b })
        p = b + 1
      end
    end

    -- C) "Month D" (no year)
    do
      local p = 1
      while true do
        local a, b = text:find(mon_pat .. "%s+(%d?%d)%f[%D]", p)
        if not a then break end
        table.insert(hits, { s = a, e = b })
        p = b + 1
      end
    end
  end

  return hits
end

-- ---- Overlap dedupe (same strategy as TR) ----
local function dedupe(hits)
  table.sort(hits, function(a, b)
    if a.s ~= b.s then return a.s < b.s end
    if a.e ~= b.e then return a.e > b.e end
    return false
  end)

  local out = {}
  for _, h in ipairs(hits) do
    local overlap = false
    for _, k in ipairs(out) do
      if not (h.e < k.s or h.s > k.e) then
        overlap = true
        break
      end
    end
    if not overlap then
      table.insert(out, h)
    end
  end
  return out
end

-- Public API: return list of {s=..., e=..., kind="date"}
function M.find(text)
  local en = find_en_dates(text)
  local merged = {}

  for _, h in ipairs(en) do
    merged[#merged + 1] = { s = h.s, e = h.e, kind = "date" }
  end

  return dedupe(merged)
end

return M

-- ../shared/lua/utils_date.lua
-- Date detection utilities for TR dates.
-- Returns hit ranges with kind = "date" for use by span_multi.lua.

local M = {}

-- ---- TR months ----
local MONTHS_TR = {
  "Ocak","Şubat","Subat","Mart","Nisan","Mayıs","Mayis","Haziran","Temmuz",
  "Ağustos","Agustos","Eylül","Eylul","Ekim","Kasım","Kasim","Aralık","Aralik"
}

-- frontier-safe numeric TR patterns
local PAT_DDMM     = '(%f[%d]%d%d?)%.(%d%d%f[%D])'
local PAT_DDMMYYYY = '(%f[%d]%d%d)%.(%d%d)%.(%d%d%d%d%f[%D])'

local function valid_ddmm(g, m)
  local gd, md = tonumber(g), tonumber(m)
  if not gd or not md then return false end
  if md < 1 or md > 12 then return false end
  if gd < 1 or gd > 31 then return false end
  return true
end

-- ---- TR date finder: "dd.mm.yyyy", "dd.mm", "d ve d Ay yyyy", "d Ay yyyy", "d Ay" ----
local function find_tr_dates(text)
  local hits = {}

  -- 1) Numeric date: "21.08.2024"
  local pos = 1
  while true do
    local a, b, g, m, y = text:find(PAT_DDMMYYYY, pos)
    if not a then break end
    g = g and g:match('%d%d')
    m = m and m:match('%d%d')
    if g and m and valid_ddmm(g, m) then
      table.insert(hits, { s = a, e = b })
    end
    pos = b + 1
  end

  -- 1b) Numeric date without year: "21.08"
  local p = 1
  while true do
    local a, b, g, m = text:find(PAT_DDMM, p)
    if not a then break end
    if valid_ddmm(g, m) then
      -- If immediately followed by ".YYYY", it is part of dd.mm.yyyy; skip.
      local tail = text:sub(b + 1, b + 5)
      if not tail:match("^%.%d%d%d%d") then
        table.insert(hits, { s = a, e = b })
      end
    end
    p = b + 1
  end

  -- 2) Day range: "29 ve 30 Ağustos 2024" / "29-30 Ağustos 2024"
  for _, mon in ipairs(MONTHS_TR) do
    local p2 = 1
    while true do
      local a, b = text:find("(%d%d?)%s*[%-–]?%s*[Vv]e?%s*(%d%d?)%s+" .. mon .. "%s+(%d%d%d%d)", p2)
      if not a then break end
      table.insert(hits, { s = a, e = b })
      p2 = b + 1
    end
  end

  -- 2b) Day range without year: "28-29 Ağustos" / "28 ve 29 Ağustos"
  for _, mon in ipairs(MONTHS_TR) do
    local p2 = 1
    while true do
      -- Capture start and end around the whole "dd-dd Ay" chunk.
      local a, b, sCap, _, _, eCap =
        text:find("()(%d%d?)%s*[%-–]%s*(%d%d?)%s+" .. mon .. "()", p2)
      if not a then break end
      -- We want the span to end at the last character of the month name.
      table.insert(hits, { s = sCap, e = eCap - 1 })
      -- Continue scanning after the month name.
      p2 = eCap + 1
    end
  end

  -- 2c) Day range without year using a connector:
  --     "28 ve 29 Ağustos", "28 ile 29 Ağustos", "28 ila 29 Ağustos"
  local function add_range_without_year(connector)
    for _, mon in ipairs(MONTHS_TR) do
      local p2 = 1
      while true do
        -- captures: ()  dd1  dd2  ()
        local pattern = "()" ..
                        "(%d%d?)%s+" .. connector .. "%s+" ..
                        "(%d%d?)%s+" .. mon .. "()"

        local a, b, sCap, d1, d2, eCap = text:find(pattern, p2)
        if not a then break end

        -- we span only "29 ve 30 Eylül" / "29 ile 30 Eylül" / "29 ila 30 Eylül"
        table.insert(hits, { s = sCap, e = eCap - 1 })
        p2 = eCap + 1
      end
    end
  end

  -- connectors we want:
  add_range_without_year("ve")
  add_range_without_year("ile")
  add_range_without_year("ila")

  -- 3) Single date with year: "3 Eylül 2024"
  for _, mon in ipairs(MONTHS_TR) do
    local p2 = 1
    while true do
      local a, b = text:find("(%d?%d)%s+" .. mon .. "%s+(%d%d%d%d)", p2)
      if not a then break end
      table.insert(hits, { s = a, e = b })
      p2 = b + 1
    end
  end

  -- 4) Day + month only: "21 Ağustos" / "5 Ekim"
  for _, mon in ipairs(MONTHS_TR) do
    local p2 = 1
    while true do
      local a, b, sCap, _, eCap = text:find("()" .. "(%d?%d)%s+" .. mon .. "()", p2)
      if not a then break end
      table.insert(hits, { s = sCap, e = eCap - 1 })
      p2 = eCap + 1
    end
  end

  return hits
end

-- ---- Overlap dedupe (keep longer matches first when same start) ----
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
  local tr = find_tr_dates(text)
  local merged = {}

  for _, h in ipairs(tr) do
    merged[#merged + 1] = { s = h.s, e = h.e, kind = "date" }
  end

  return dedupe(merged)
end

return M

-- ../shared/lua/span_date.lua
-- TR + EN tarihleri <span class="date">...</span> ile sarar
-- Örnekler:
--  TR: "3 Eylül 2024", "29 ve 30 Ağustos 2024", "21 Ağustos", "5 Ekim", "21.08.2024", "21.08.2024-30.08.2024"
--  EN: "August 21, 2024", "September 8 2024", "21 August 2024", "August 21"

local M = {}
local List = require 'pandoc.List'

local MONTHS_TR = {
  "Ocak","Şubat","Subat","Mart","Nisan","Mayıs","Mayis","Haziran","Temmuz",
  "Ağustos","Agustos","Eylül","Eylul","Ekim","Kasım","Kasim","Aralık","Aralik"
}

-- İngilizce aylar (tam + kısaltmalar)
local MONTHS_EN = {
  "January","Jan",
  "February","Feb",
  "March","Mar",
  "April","Apr",
  "May",
  "June","Jun",
  "July","Jul",
  "August","Aug",
  "September","Sept","Sep",
  "October","Oct",
  "November","Nov",
  "December","Dec"
}

-- Case-insensitive pattern üret (yalnızca ASCII harfler için)
local function ci_pat(s)
  return (s:gsub("%a", function(c)
    local lo, up = string.lower(c), string.upper(c)
    if lo == up then return c end
    return "[" .. lo .. up .. "]"
  end))
end

-- frontier-safe (yılsız TR tarih: dd.mm)
local PAT_DDMM = '(%f[%d]%d%d?)%.(%d%d%f[%D])'

-- frontier-safe desen (sayısal TR tarih: dd.mm.yyyy)
local PAT_DDMMYYYY = '(%f[%d]%d%d)%.(%d%d)%.(%d%d%d%d%f[%D])'

-- gün ve ay doğrulama (sayısal TR tarih için)
local function valid_ddmm(g, m)
  local gd, md = tonumber(g), tonumber(m)
  if not gd or not md then return false end
  if md < 1 or md > 12 then return false end
  if gd < 1 or gd > 31 then return false end
  return true
end

-- ---- Koşu (run) lineerleştirme: sadece Str/Space/SoftBreak ----
local function run_linearize(run)
  local buf, map = {}, {}
  local pos = 0
  for idx, el in ipairs(run) do
    if el.t == "Str" then
      local s = el.text
      for i = 1, #s do
        pos = pos + 1
        buf[pos] = s:sub(i,i)
        map[pos] = {ix = idx, off = i}
      end
    elseif el.t == "Space" or el.t == "SoftBreak" then
      pos = pos + 1
      buf[pos] = " "
      map[pos] = {ix = idx, off = 0}
    end
  end
  return table.concat(buf), map
end

-- ---- TR tarih arayıcı: "dd.mm.yyyy", "d ve d Ay yyyy", "d Ay yyyy", "d Ay" ----
local function find_tr_dates_in_text(text)
  local hits = {}

  -- 1) Sayısal tarih: "21.08.2024"
  local pos = 1
  while true do
    local a,b,g,m,y = text:find(PAT_DDMMYYYY, pos)
    if not a then break end
    g = g and g:match('%d%d') or nil
    m = m and m:match('%d%d') or nil
    if g and m and valid_ddmm(g, m) then
      table.insert(hits, {s=a, e=b})
    end
    pos = b and (b + 1) or (pos + 1)
  end

  -- 1b) Sayısal tarih (yılsız): "21.08"
  do
    local p = 1
    while true do
      local a, b, g, m = text:find(PAT_DDMM, p)
      if not a then break end
      if valid_ddmm(g, m) then
        -- Eğer hemen ardından ".YYYY" varsa, bu zaten "dd.mm.yyyy" bütününün parçası; ekleme
        local tail = text:sub(b+1, b+5)  -- ".2024" gibi 5 karakter
        if not tail:match("^%.%d%d%d%d") then
          table.insert(hits, { s = a, e = b })
        end
      end
      p = b + 1
    end
  end

  -- 2) Gün aralığı: "29 ve 30 Ağustos 2024" / "29-30 Ağustos 2024"
  for _, mon in ipairs(MONTHS_TR) do
    local p = 1
    while true do
      local a,b = text:find("(%d%d?)%s*[%-–]?%s*[Vv]e?%s*(%d%d?)%s+" .. mon .. "%s+(%d%d%d%d)", p)
      if not a then break end
      table.insert(hits, {s=a, e=b}); p = b + 1
    end
  end

  -- 3) Tek tarih (yıllı): "3 Eylül 2024"
  for _, mon in ipairs(MONTHS_TR) do
    local p = 1
    while true do
      local a,b = text:find("(%d?%d)%s+" .. mon .. "%s+(%d%d%d%d)", p)
      if not a then break end
      table.insert(hits, {s=a, e=b}); p = b + 1
    end
  end

  -- 4) Yılsız: "21 Ağustos" / "5 Ekim"  (sadece "gün + Ay" sarılır)
  for _, mon in ipairs(MONTHS_TR) do
    local p = 1
    while true do
      -- sCap: eşleşmenin BAŞI, eCap: AY adının SONRASI
      -- Not: (%d?%d) sadece gün için; pozisyon hesapta kullanılmıyor.
      local a, b, sCap, _, eCap = text:find("()" .. "(%d?%d)%s+" .. mon .. "()", p)
      if not a then break end
      table.insert(hits, { s = sCap, e = eCap - 1 })
      p = eCap + 1
    end
  end

  return hits
end

-- ---- EN tarih arayıcı: "August 21, 2024" | "August 21 2024" | "21 August 2024" | "August 21"
local function find_en_dates_in_text(text)
  local hits = {}

  for _, mon in ipairs(MONTHS_EN) do
    local mon_pat = "%f[%a]" .. ci_pat(mon) .. "%f[%A]"

    -- A) "Month D, YYYY" veya "Month D YYYY"
    do
      local p = 1
      while true do
        local a,b = text:find(mon_pat .. "%s+(%d%d?)%s*,?%s*(%d%d%d%d)", p)
        if not a then break end
        table.insert(hits, {s=a, e=b}); p = b + 1
      end
    end

    -- B) "D Month YYYY"
    do
      local p = 1
      while true do
        local a,b = text:find("(%d?%d)%s+" .. mon_pat .. "%s+(%d%d%d%d)", p)
        if not a then break end
        table.insert(hits, {s=a, e=b}); p = b + 1
      end
    end

    -- C) "Month D" (yılsız)
    do
      local p = 1
      while true do
        local a,b = text:find(mon_pat .. "%s+(%d?%d)%f[%D]", p)
        if not a then break end
        table.insert(hits, {s=a, e=b}); p = b + 1
      end
    end
  end

  return hits
end

-- ---- Çakışmaları temizle ----
local function dedupe_hits(hits)
  table.sort(hits, function(x,y)
    if x.s ~= y.s then return x.s < y.s end
    if x.e ~= y.e then return x.e > y.e end  -- uzun olan önce
    return false
  end)
  local filtered = {}
  for _, h in ipairs(hits) do
    local overlap = false
    for _, k in ipairs(filtered) do
      if not (h.e < k.s or h.s > k.e) then overlap = true; break end
    end
    if not overlap then table.insert(filtered, h) end
  end
  return filtered
end

-- ---- Run içi geri projeksiyon: sadece Str/Space/SoftBreak'ten yeni run çıkar ----
local function rebuild_run_from_hits(run, text, map, hits)
  if #hits == 0 then return run end

  local out = List:new()
  local pos = 1
  local function emit_plain(p1, p2)
    if p2 < p1 then return end
    local i = p1
    while i <= p2 do
      local m = map[i]
      if not m then
        i = i + 1
      elseif m.off == 0 then
        out:insert(pandoc.Space()); i = i + 1
      else
        local ix, start_off = m.ix, m.off
        local j, end_off = i, start_off
        while j+1 <= p2 and map[j+1] and map[j+1].ix == ix and map[j+1].off == end_off + 1 do
          j = j + 1; end_off = end_off + 1
        end
        local el = run[ix]
        out:insert(pandoc.Str(el.text:sub(start_off, end_off)))
        i = j + 1
      end
    end
  end

  local hix = 1
  while pos <= #text and hix <= #hits do
    local h = hits[hix]
    if pos < h.s then emit_plain(pos, h.s - 1); pos = h.s end

    -- hit dilimini topla
    local parts = {}
    local i = h.s
    while i <= h.e do
      local m = map[i]
      if m and m.off == 0 then
        table.insert(parts, " "); i = i + 1
      elseif m then
        local ix, start_off = m.ix, m.off
        local j, end_off = i, start_off
        while j+1 <= h.e and map[j+1] and map[j+1].ix == ix and map[j+1].off == end_off + 1 do
          j = j + 1; end_off = end_off + 1
        end
        local el = run[ix]
        table.insert(parts, el.text:sub(start_off, end_off))
        i = j + 1
      else
        i = i + 1
      end
    end
    local tok = table.concat(parts)
    out:insert(pandoc.Span({ pandoc.Str(tok) }, pandoc.Attr('', {'date'})))
    pos = h.e + 1
    hix = hix + 1
  end
  if pos <= #text then emit_plain(pos, #text) end
  return out
end

-- ---- Inlines processor: metin koşularına uygula, kapsayıcılara rekürsif gir ----
local function process_inlines(inlines)
  local out = List:new()
  local i, n = 1, #inlines

  local function is_textlike(el)
    return el.t == "Str" or el.t == "Space" or el.t == "SoftBreak"
  end

  while i <= n do
    if is_textlike(inlines[i]) then
      -- bir koşu topla
      local run = List:new()
      local j = i
      while j <= n and is_textlike(inlines[j]) do
        run:insert(inlines[j]); j = j + 1
      end
      local text, map = run_linearize(run)

      -- TR + EN bul, birleştir, çakışma gider
      local hits_tr = find_tr_dates_in_text(text)
      local hits_en = find_en_dates_in_text(text)
      local hits = {}
      for _,h in ipairs(hits_tr) do hits[#hits+1] = h end
      for _,h in ipairs(hits_en) do hits[#hits+1] = h end
      hits = dedupe_hits(hits)

      local rebuilt = rebuild_run_from_hits(run, text, map, hits)
      out:extend(rebuilt)
      i = j
    else
      -- Kapsayıcıların içine rekürsif gir
      local el = inlines[i]
      if el.content and type(el.content) == "table" then
        el.content = process_inlines(el.content)
      end
      out:insert(el)
      i = i + 1
    end
  end
  return out
end

function M.Inlines(inl)
  return process_inlines(inl)
end

return M

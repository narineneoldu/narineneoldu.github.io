-- ../shared/lua/span_date_en.lua
-- EN (US) tarihlerini <span class="date">...</span> ile sarar
-- Destek:
--   1) Sayısal: MM/DD/YYYY
--   2) Ay adı + gün: "August 22", "Aug 22", isteğe bağlı yıl: "August 22, 2024"

local M = {}
local List = require 'pandoc.List'

-- ---- Ay adları (tam + kısaltmalar) ----
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

-- ASCII-case-insensitive pattern üret
local function ci_pat(s)
  return (s:gsub("%a", function(c)
    local lo, up = string.lower(c), string.upper(c)
    if lo == up then return c end
    return "[" .. lo .. up .. "]"
  end))
end

-- ---- run -> düz metin + harita ----
local function run_linearize(run)
  local buf, map, pos = {}, {}, 0
  for i, el in ipairs(run) do
    if el.t == "Str" then
      local s = el.text
      for k=1,#s do pos=pos+1; buf[pos]=s:sub(k,k); map[pos]={ix=i, off=k} end
    elseif el.t=="Space" or el.t=="SoftBreak" then
      pos=pos+1; buf[pos]=" "; map[pos]={ix=i, off=0}
    end
  end
  return table.concat(buf), map
end

-- ---- doğrulamalar ----
local function valid_mmdd(mm, dd)
  local m = tonumber(mm); local d = tonumber(dd)
  if not m or not d then return false end
  if m < 1 or m > 12 then return false end
  if d < 1 or d > 31 then return false end
  return true
end

-- ---- EN tarih arayıcı ----
local function find_en_dates_in_text(text)
  local hits = {}

  -- 1) Sayısal: MM/DD/YYYY
  do
    local p = 1
    while true do
      local a,b,mm,dd,yyyy = text:find("(%f[%d]%d%d?)%/(%d%d?)%/(%d%d%d%d%f[%D])", p)
      if not a then break end
      if valid_mmdd(mm, dd) then
        hits[#hits+1] = { s = a, e = b }
      end
      p = b + 1
    end
  end

  -- 2) Ay adı + gün (+ opsiyonel yıl): Month D[, ]YYYY?
  for _, mon in ipairs(MONTHS_EN) do
    local mon_pat = "%f[%a]" .. ci_pat(mon) .. "%f[%A]"

    -- 2A) "Month D, YYYY" veya "Month D YYYY"
    do
      local p = 1
      while true do
        local a,b = text:find(mon_pat .. "%s+(%d%d?)%s*,?%s+(%d%d%d%d)", p)
        if not a then break end
        hits[#hits+1] = { s = a, e = b }
        p = b + 1
      end
    end

    -- 2B) "Month D" (yılsız)
    do
      local p = 1
      while true do
        -- gün sonrası rakam olmayan sınır (saat/dakika iki nokta vb. hariç)
        local a,b = text:find(mon_pat .. "%s+(%d%d?)%f[%D]", p)
        if not a then break end
        hits[#hits+1] = { s = a, e = b }
        p = b + 1
      end
    end
  end

  return hits
end

-- ---- çakışma temizliği ----
local function dedupe_hits(hits)
  table.sort(hits, function(x,y)
    if x.s ~= y.s then return x.s < y.s end
    if x.e ~= y.e then return x.e > y.e end -- uzun olan önce
    return false
  end)
  local out = {}
  for _,h in ipairs(hits) do
    local ok = true
    for _,k in ipairs(out) do
      if not (h.e < k.s or h.s > k.e) then ok = false; break end
    end
    if ok then out[#out+1] = h end
  end
  return out
end

-- ---- geri projeksiyon ----
local function rebuild_run_from_hits(run, text, map, hits)
  if #hits == 0 then return run end
  hits = dedupe_hits(hits)

  local out, pos = List:new(), 1
  local function emit_plain(a,b)
    if b<a then return end
    local i=a
    while i<=b do
      local m=map[i]
      if not m then i=i+1
      elseif m.off==0 then out:insert(pandoc.Space()); i=i+1
      else
        local ix,soff=m.ix,m.off; local j=i; local eoff=soff
        while j+1<=b and map[j+1] and map[j+1].ix==ix and map[j+1].off==eoff+1 do
          j=j+1; eoff=eoff+1
        end
        out:insert(pandoc.Str(run[ix].text:sub(soff,eoff))); i=j+1
      end
    end
  end

  for _,h in ipairs(hits) do
    if pos<h.s then emit_plain(pos, h.s-1) end
    local parts, i = {}, h.s
    while i<=h.e do
      local m=map[i]
      if m and m.off==0 then parts[#parts+1]=" "; i=i+1
      elseif m then
        local ix,soff=m.ix,m.off; local j=i; local eoff=soff
        while j+1<=h.e and map[j+1] and map[j+1].ix==ix and map[j+1].off==eoff+1 do
          j=j+1; eoff=eoff+1
        end
        parts[#parts+1] = run[ix].text:sub(soff,eoff); i=j+1
      else i=i+1 end
    end
    out:insert(pandoc.Span({ pandoc.Str(table.concat(parts)) }, pandoc.Attr('', {'date'})))
    pos = h.e + 1
  end
  if pos<=#text then emit_plain(pos, #text) end
  return out
end

-- ---- Inlines ----
local function process_inlines(inlines)
  local out, i, n = List:new(), 1, #inlines
  local function is_textlike(el) return el.t=="Str" or el.t=="Space" or el.t=="SoftBreak" end
  while i<=n do
    if is_textlike(inlines[i]) then
      local run, j = List:new(), i
      while j<=n and is_textlike(inlines[j]) do run:insert(inlines[j]); j=j+1 end
      local text, map = run_linearize(run)
      local hits = find_en_dates_in_text(text)
      out:extend(rebuild_run_from_hits(run, text, map, hits))
      i = j
    else
      local el = inlines[i]
      if el.content and type(el.content)=="table" then el.content = process_inlines(el.content) end
      out:insert(el); i=i+1
    end
  end
  return out
end

M.Inlines = process_inlines
return M

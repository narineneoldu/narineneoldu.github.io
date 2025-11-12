-- ../shared/lua/span_amount_en.lua
-- TRY <amount> kalıplarını <span class="amount">...</span> ile sarar.
-- Örn: TRY 48,000.00 | TRY 1,200 | TRY 1200

local M = {}
local List = require 'pandoc.List'

local NBSP = "\194\160"            -- U+00A0
local NNBSP = "\226\128\175"       -- U+202F
local SP = "[%s\194\160\226\128\175]+"  -- space/NBSP/NNBSP

-- Mevcut amount span'larına dokunma
local function is_amount_span(el)
  if el.t ~= "Span" then return false end
  local cls = el.attr and el.attr.classes or {}
  for _, c in ipairs(cls) do if c == "amount" then return true end end
  return false
end

-- Str/Space/SoftBreak koşusunu tek satıra indir (NBSP/NNBSP -> " ")
local function run_linearize(run)
  local buf, map, pos = {}, {}, 0
  for idx, el in ipairs(run) do
    if el.t == "Str" then
      local s = (el.text or ""):gsub(NBSP, " "):gsub(NNBSP, " ")
      for i=1,#s do
        pos = pos + 1
        buf[pos] = s:sub(i,i)
        map[pos] = {ix=idx, off=i, kind="Str", raw=el.text}
      end
    elseif el.t=="Space" or el.t=="SoftBreak" then
      pos = pos + 1
      buf[pos] = " "
      map[pos] = {ix=idx, off=0, kind=el.t}
    end
  end
  return table.concat(buf), map
end

-- TRY + amount eşleşmelerini bul (İngilizce sayı: binlik virgül, ondalık nokta)
-- TRY + amount eşleşmelerini bul (İngilizce sayı: binlik virgül, ondalık nokta)
local function find_amount_hits(text)
  local hits, i, n = {}, 1, #text

  -- Tüm kalıbı tek capture olarak alıyoruz; a,b zaten tam aralığı veriyor.
  local PAT_DEC = '(%f[%a][Tt][Rr][Yy]' .. SP .. '%d[%d,]*%.%d%d)' -- ondalıklı
  local PAT_INT = '(%f[%a][Tt][Rr][Yy]' .. SP .. '%d[%d,]*)'       -- tam sayı

  while i <= n do
    local a1, b1, grp1 = text:find(PAT_DEC, i)
    local a2, b2, grp2 = text:find(PAT_INT, i)

    local a, b, grp, is_dec

    if a1 and (not a2 or a1 <= a2) then
      a, b, grp, is_dec = a1, b1, grp1, true
    elseif a2 then
      -- INT varyantında sayı kısmını ayırıp sonu virgül mü diye kontrol et
      local num = grp2:match('(%d[%d,]*)$') or ""
      if num:sub(-1) == ',' then
        i = a2 + 1
        goto continue
      end
      a, b, grp, is_dec = a2, b2, grp2, false
    else
      break
    end

    hits[#hits+1] = { s = a, e = b }
    i = b + 1
    ::continue::
  end

  return hits
end
-- Koşuyu hits'e göre yeniden inşa et (span.amount ekleyerek)
local function rebuild_run_from_hits(run, text, map, hits)
  if #hits == 0 then return run end
  local out, pos = List:new(), 1

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
        local raw = run[ix].text
        out:insert(pandoc.Str(raw:sub(start_off, end_off)))
        i = j + 1
      end
    end
  end

  for _, h in ipairs(hits) do
    if pos < h.s then emit_plain(pos, h.s - 1) end
    -- eşleşmeyi parçala (orijinal Str'lardan toparla)
    local parts, i = {}, h.s
    while i <= h.e do
      local m = map[i]
      if m and m.off == 0 then
        parts[#parts+1] = " "; i = i + 1
      elseif m then
        local ix, start_off = m.ix, m.off
        local j, end_off = i, start_off
        while j+1 <= h.e and map[j+1] and map[j+1].ix == ix and map[j+1].off == end_off + 1 do
          j = j + 1; end_off = end_off + 1
        end
        local raw = run[ix].text
        parts[#parts+1] = raw:sub(start_off, end_off)
        i = j + 1
      else
        i = i + 1
      end
    end
    out:insert(pandoc.Span({ pandoc.Str(table.concat(parts)) }, pandoc.Attr('', {'amount'})))
    pos = h.e + 1
  end
  if pos <= #text then emit_plain(pos, #text) end
  return out
end

-- Rekürsif inline işlemcisi
local function process_inlines(inlines)
  local out, i, n = List:new(), 1, #inlines

  local function is_textlike(el)
    return el.t == "Str" or el.t == "Space" or el.t == "SoftBreak"
  end

  while i <= n do
    local el = inlines[i]

    if is_amount_span(el) then
      out:insert(el); i = i + 1

    elseif is_textlike(el) then
      local run, j = List:new(), i
      while j <= n and is_textlike(inlines[j]) do run:insert(inlines[j]); j = j + 1 end
      local text, map = run_linearize(run)
      local hits = find_amount_hits(text)
      out:extend(rebuild_run_from_hits(run, text, map, hits))
      i = j

    else
      if el.content and type(el.content) == "table" then
        el.content = process_inlines(el.content)
      end
      out:insert(el); i = i + 1
    end
  end

  return out
end

function M.Inlines(inl)
  return process_inlines(inl)
end

return M

-- ../shared/lua/span_amount.lua
-- — Türk Lirası tutarlarını <span class="amount">...</span> ile sarar.
-- Örnekler: 48.000,00 TL | 1200 TL | 1.200 TL | 45.673,84 TL | 45.673,84 TL’den
-- Str/Space/SoftBreak koşuları üzerinde çalışır; NBSP ve satır sonlarını da yakalar.

local M = {}
local List = require 'pandoc.List'

-- NBSP (U+00A0) — bazı metinlerde TL öncesinde kullanılabiliyor
local NBSP = "\194\160"

-- “amount” sınıfı olan span’lara dokunmayalım (idempotent)
local function is_amount_span(el)
  if el.t ~= "Span" then return false end
  local cls = el.attr and el.attr.classes or {}
  for _, c in ipairs(cls) do if c == "amount" then return true end end
  return false
end

-- Sadece Str / Space / SoftBreak’ten oluşan bir “koşu”yu tek satıra indir (map ile)
local function run_linearize(run)
  local buf, map = {}, {}
  local pos = 0
  for idx, el in ipairs(run) do
    if el.t == "Str" then
      -- Str içindeki NBSP’leri normal boşluğa çevirip eşleşmeyi kolaylaştıralım
      local s = (el.text or ""):gsub(NBSP, " ")
      for i = 1, #s do
        pos = pos + 1
        buf[pos] = s:sub(i,i)
        map[pos] = {ix = idx, off = i, kind = "Str", raw = el.text}
      end
    elseif el.t == "Space" or el.t == "SoftBreak" then
      pos = pos + 1
      buf[pos] = " "
      map[pos] = {ix = idx, off = 0, kind = el.t}
    end
  end
  return table.concat(buf), map
end

-- Metin içinde tüm “MİKTAR + (boşluklar) + TL” eşleşmelerini bul
-- Miktar desenleri:
--  - ondalıklı: 1.234,56   (en az bir rakam, opsiyonel binlik . , ardından virgül+2 hane)
--  - tam sayı : 1.234  veya 1200  (rakam ve noktalar; sonda nokta olmasın)
local function find_amount_hits(text)
  local hits = {}
  local i = 1
  local n = #text

  -- iki ayrı desen: ondalıklı ve ondalıksız
  -- \n: Lua’da frontier kullanıyoruz ki sayının baş/sonu başka rakama yapışmasın
  local PAT_DEC  = '(%f[%d]%d[%d%.]*,%d%d)%s*TL'  -- ondalıklı
  local PAT_INT  = '(%f[%d]%d[%d%.]*)%s*TL'      -- ondalıksız (sonda nokta kalmasın -> kontrolle)
  while i <= n do
    local a1,b1,num1 = text:find(PAT_DEC, i)
    local a2,b2,num2 = text:find(PAT_INT, i)

    -- en erken eşleşmeyi seç
    local a,b,num,is_dec
    if a1 and (not a2 or a1 <= a2) then
      a,b,num,is_dec = a1,b1,num1,true
    elseif a2 then
      a,b,num,is_dec = a2,b2,num2,false
      -- ondalıksız olanın sonu nokta ile bitmesin (örn. "1.200." gibi)
      if num:sub(-1) == '.' then
        -- bu eşleşmeyi atlayıp biraz ileriden tekrar ara
        i = a + 1
        goto continue
      end
    else
      break
    end

    -- “1.234.567” gibi binlik noktalarda kabaca validasyon (isteğe bağlı: sıkılaştırılabilir)
    -- Burada gevşek bırakıyoruz; “TL” zorunluluğu zaten yanlış pozitifleri azaltıyor.

    table.insert(hits, { s = a, e = b })
    i = b + 1
    ::continue::
  end

  return hits
end

-- Koşudaki “hits” aralıklarını, orijinal inline’lara geri projekte ederek yeniden inşa et
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
        -- Önemli: Str’ı yazarken ORİJİNAL (NBSP’li) metinden al
        local raw = run[ix].text
        out:insert(pandoc.Str(raw:sub(start_off, end_off)))
        i = j + 1
      end
    end
  end

  local hix = 1
  while pos <= #text and hix <= #hits do
    local h = hits[hix]
    if pos < h.s then emit_plain(pos, h.s - 1) end

    -- eşleşmeyi topla
    local parts = {}
    local i = h.s
    while i <= h.e do
      local m = map[i]
      if m and m.off == 0 then
        table.insert(parts, " ")
        i = i + 1
      elseif m then
        local ix, start_off = m.ix, m.off
        local j, end_off = i, start_off
        while j+1 <= h.e and map[j+1] and map[j+1].ix == ix and map[j+1].off == end_off + 1 do
          j = j + 1; end_off = end_off + 1
        end
        local raw = run[ix].text
        table.insert(parts, raw:sub(start_off, end_off))
        i = j + 1
      else
        i = i + 1
      end
    end

    local tok = table.concat(parts)     -- örn: "45.673,84 TL"
    out:insert(pandoc.Span({ pandoc.Str(tok) }, pandoc.Attr('', {'amount'})))
    pos = h.e + 1
    hix = hix + 1
  end
  if pos <= #text then emit_plain(pos, #text) end
  return out
end

-- Inlines işlemcisi: text koşularını yakala, kapsayıcılara rekürsif gir, amount span’larını atla
local function process_inlines(inlines)
  local out = List:new()
  local i, n = 1, #inlines

  local function is_textlike(el)
    return el.t == "Str" or el.t == "Space" or el.t == "SoftBreak"
  end

  while i <= n do
    local el = inlines[i]

    -- Zaten amount ise aynen bırak
    if is_amount_span(el) then
      out:insert(el); i = i + 1

    -- Text koşusu
    elseif is_textlike(el) then
      local run = List:new()
      local j = i
      while j <= n and is_textlike(inlines[j]) do
        run:insert(inlines[j]); j = j + 1
      end
      local text, map = run_linearize(run)
      local hits = find_amount_hits(text)
      local rebuilt = rebuild_run_from_hits(run, text, map, hits)
      out:extend(rebuilt)
      i = j

    else
      -- Kapsayıcılara (Emph, Strong, Span, Link vb.) rekürsif gir
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

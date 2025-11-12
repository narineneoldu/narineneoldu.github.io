-- ../shared/lua/span_record_number.lua
-- Sayı / sayı aralıklarını SADECE ardından "numara/sayılı/esas/karar/madde" (ekli halleri) geliyorsa sarar.

local M = {}
local List = require 'pandoc.List'

local skip = {
  Code = true, CodeBlock = true, Math = true, Link = true, Image = true,
  RawInline = true, RawBlock = true
}

-- ---- yardımcılar ----
local function has_class(attr, name)
  if not attr or not attr.classes then return false end
  for _, c in ipairs(attr.classes) do if c == name then return true end end
  return false
end

local function is_url_context(s, lpos)
  local from = math.max(1, lpos - 12)
  return s:sub(from, lpos):find("://") ~= nil
end

-- ---- run lineerleştirme / geri projeksiyon ----
local function is_textlike(el) return el.t=="Str" or el.t=="Space" or el.t=="SoftBreak" end

local function linearize(run)
  local buf, map, pos = {}, {}, 0
  for i, el in ipairs(run) do
    if el.t == "Str" then
      local s = el.text
      for k=1,#s do pos=pos+1; buf[pos]=s:sub(k,k); map[pos]={ix=i, off=k} end
    else
      pos=pos+1; buf[pos]=" "; map[pos]={ix=i, off=0}
    end
  end
  return table.concat(buf), map
end

local function rebuild(run, text, map, hits)
  if #hits == 0 then return run end
  table.sort(hits, function(a,b) return a.s<b.s or (a.s==b.s and a.e<b.e) end)
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
        while j+1<=b and map[j+1] and map[j+1].ix==ix and map[j+1].off==eoff+1 do j=j+1; eoff=eoff+1 end
        out:insert(pandoc.Str(run[ix].text:sub(soff,eoff))); i=j+1
      end
    end
  end

  for _,h in ipairs(hits) do
    if pos<h.s then emit_plain(pos, h.s-1) end
    local parts, i={}, h.s
    while i<=h.e do
      local m=map[i]
      if m and m.off==0 then table.insert(parts," "); i=i+1
      elseif m then
        local ix,soff=m.ix,m.off; local j=i; local eoff=soff
        while j+1<=h.e and map[j+1] and map[j+1].ix==ix and map[j+1].off==eoff+1 do j=j+1; eoff=eoff+1 end
        table.insert(parts, run[ix].text:sub(soff,eoff)); i=j+1
      else i=i+1 end
    end
    local tok=table.concat(parts)
    out:insert(pandoc.Span({ pandoc.Str(tok) }, pandoc.Attr("", { "record-number" })))
    pos=h.e+1
  end
  if pos<=#text then emit_plain(pos, #text) end
  return out
end

-- ---- aday kontrolü: patern + ardından anahtar kelime kökü ----
local KEYWORD_STEMS = { "numara", "sayili", "esas", "karar sayili", "madde", "fıkra" }

local function ascii_fold(s)
  -- Türkçe temel katlama: ı/İ/I -> i, ayrıca İ -> i
  s = s:gsub("İ", "i"):gsub("I", "i"):gsub("ı", "i")
  -- İstersen buraya diğer aksan kaldırmaları da ekleyebilirsin
  return s
end

local function has_following_keyword(text, rpos)
  -- sayının hemen sonrasını al
  local tail = text:sub(rpos)

  -- baştaki boşluk / NBSP / NNBSP / parantez-noktalama / çeşitli tireleri temizle
  tail = tail:gsub("^[%s\194\160\226\128\175%.,;:%(%)]*", "")
  tail = tail:gsub("^[%-\226\128\147\226\128\148\226\128\146\226\128\145\226\136\146]*", "")

  -- İlk kelime
  local w1 = tail:match("^([%a\128-\255]+)")
  if not w1 then return false end

  -- w1 sonrası ayırıcıları atıp ikinci kelimeyi de dene (opsiyonel)
  local after_w1 = tail:sub(#w1 + 1)
  after_w1 = after_w1:gsub("^[%s\194\160\226\128\175%-\226\128\147\226\128\148\226\128\146\226\128\145\226\136\146]+", "")
  local w2 = after_w1:match("^([%a\128-\255]+)")

  -- adaylar: tek kelime ve iki kelime birleştirilmiş
  local cand1 = (w1 or "")
  local cand2 = (w1 or "") .. " " .. (w2 or "")  -- "karar sayili" gibi

  cand1 = ascii_fold(cand1):lower()
  cand2 = ascii_fold(cand2):lower()

  for _, stem in ipairs(KEYWORD_STEMS) do
    local s = ascii_fold(stem)  -- "sayılı" → "sayili"
    -- stem tek kelimeyse cand1 ile, iki kelimeyse cand2 ile eşleşir
    if s:find(" ", 1, true) then
      if cand2:sub(1, #s) == s then return true end
    else
      if cand1:sub(1, #s) == s then return true end
    end
  end

  return false
end

-- önce dosyanın başında zaten var diyorsun ama net olsun:
local SP = "[%s\194\160\226\128\175]+"  -- space, NBSP (00A0), NNBSP (202F)

local function find_hits(text)
  local hits = {}

  -- ---------- 1) ÇİFT SAYI: "N[.] ve M[.]" + ardından anahtar ----------
  -- Sadece sayıları span’le (noktayı hariç tut). "1 ve 2. maddesi" / "1. ve 2. maddesi" ikisini de yakalar.
  for lpos1, num1, lpos2, num2, rpos2 in text:gmatch("()(%d+)%.?" .. SP .. "[Vv][Ee]" .. SP .. "()(%d+)%.?()") do
    -- solda bitişik harf/rakam olmasın
    local prev_is_word = (lpos1 > 1) and text:sub(lpos1 - 1, lpos1 - 1):match("[%w]") ~= nil
    if not prev_is_word and not is_url_context(text, lpos1) and has_following_keyword(text, rpos2) then
      local e1 = lpos1 + #num1 - 1
      local e2 = lpos2 + #num2 - 1
      hits[#hits+1] = { s = lpos1, e = e1 }
      hits[#hits+1] = { s = lpos2, e = e2 }
    end
  end

  -- ---------- 2) TEK TOKEN: "82/1-d-e", "2024-109", "37." + ardından anahtar ----------
  -- Burada token’ın sonundaki opsiyonel noktayı hariç tutuyoruz.
  for lpos, tok, dot, rpos in text:gmatch("()%f[%d](%d[%w%-/⁄∕]*)(%.?)()") do
    -- "37." gibi durumlarda 'tok' = "37", 'dot' = "."
    local prev_is_word = (lpos > 1) and text:sub(lpos - 1, lpos - 1):match("[%w]") ~= nil
    if not prev_is_word and not is_url_context(text, lpos) and has_following_keyword(text, rpos) then
      local e_core = lpos + #tok - 1  -- nokta hariç
      hits[#hits+1] = { s = lpos, e = e_core }
    end
  end

  -- Çakışmaları sadeleştir (erken eklenen çiftler kalsın)
  table.sort(hits, function(a,b) return a.s<b.s or (a.s==b.s and a.e<b.e) end)
  local out = {}
  for _,h in ipairs(hits) do
    local keep = true
    for _,k in ipairs(out) do
      if not (h.e < k.s or h.s > k.e) then keep = false; break end
    end
    if keep then out[#out+1] = h end
  end
  return out
end

-- ---- Inlines işlemcisi: run bazında ----
local function process_inlines(inlines)
  local out = List:new()
  local i, n = 1, #inlines

  while i <= n do
    local el = inlines[i]

    if is_textlike(el) then
      -- bir run topla
      local run = List:new()
      local j = i
      while j <= n and is_textlike(inlines[j]) do
        run:insert(inlines[j]); j = j + 1
      end

      local text, map = linearize(run)
      -- hız için: rakam ve anahtar kök yoksa hiç arama yapma
      if text:find("%d") then
        local hits = find_hits(text)
        out:extend(rebuild(run, text, map, hits))
      else
        out:extend(run)
      end

      i = j

    else
      -- zaten sarılmış veya skip olmayan kapsayıcıların içine gir
      if el.content and not skip[el.t] and not (el.t=="Span" and has_class(el.attr, "record-number")) then
        el.content = process_inlines(el.content)
      end
      out:insert(el)
      i = i + 1
    end
  end

  return out
end

M.Inlines = process_inlines
return M

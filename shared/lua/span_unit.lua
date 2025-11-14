-- ../shared/lua/span_unit.lua
-- Yalnız TR süre birimleri: gün, yıl/sene, ay, saat, dakika, saniye (+ ekli biçimler)
-- Aralıklar (X–Y, X ile Y), "yarım + birim", apostrof, tarih (dd.mm.yyyy) ve HH:MM korumaları

local M = {}

local List = require 'pandoc.List'

-- -------- run -> düz metin + harita ----------
local function linearize(run)
  local buf, map, pos = {}, {}, 0
  for i, el in ipairs(run) do
    if el.t == "Str" then
      local s = el.text
      for k=1,#s do
        pos = pos + 1
        buf[pos] = s:sub(k,k)
        map[pos] = {ix=i, off=k}
      end
    elseif el.t=="Space" or el.t=="SoftBreak" then
      pos = pos + 1; buf[pos] = " "; map[pos] = {ix=i, off=0}
    end
  end
  return table.concat(buf), map
end

-- -------- yeniden projeksiyon ----------
local function rebuild(run, text, map, hits)
  if #hits == 0 then return run end
  table.sort(hits, function(a,b) return a.s<b.s or (a.s==b.s and a.e<b.e) end)
  local out, pos = List:new(), 1

  local function emit_plain(a,b)
    if b<a then return end
    local i=a
    while i<=b do
      local m=map[i]
      if not m then
        i=i+1
      elseif m.off==0 then
        out:insert(pandoc.Space()); i=i+1
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
      if m and m.off==0 then
        table.insert(parts," "); i=i+1
      elseif m then
        local ix,soff=m.ix,m.off; local j=i; local eoff=soff
        while j+1<=h.e and map[j+1] and map[j+1].ix==ix and map[j+1].off==eoff+1 do
          j=j+1; eoff=eoff+1
        end
        table.insert(parts, run[ix].text:sub(soff,eoff)); i=j+1
      else
        i=i+1
      end
    end
    local tok = table.concat(parts)
    out:insert(pandoc.Span({pandoc.Str(tok)}, pandoc.Attr("", {h.class})))
    pos = h.e+1
  end
  if pos<=#text then emit_plain(pos, #text) end
  return out
end

-- -------- desenler ----------
local NUM    = "%d+[.,]?%d*"  -- 19 / 2,5 / 2.5
local DASHES = { "-", "\226\128\147", "\226\128\148", "\226\128\146", "\226\128\145", "\226\136\146", "x" }
local SP     = "[%s\194\160\226\128\175]+"  -- space, NBSP (00A0), NNBSP (202F)
local APOS   = "['\226\128\153\226\128\152\202\188]" -- ', ’, ‘, ʼ
local BND    = "%f[%A]"       -- ASCII harf-dışı sınır

-- HH:MM koruması
local function is_after_HHMM(s, start_idx)
  local L = math.max(1, start_idx - 5)
  local left = s:sub(L, start_idx - 1)
  return left:match("%d%d?%s*:%s*$") ~= nil
end

-- dd.mm.yyyy komşuluğu koruması
local function inside_date_ddmmyyyy(s, a, b)
  local L = math.max(1, a - 5)
  local p, q = s:find("%d%d?%.%d%d?%.%d%d%d%d", L)
  while p do
    if not (q < a or p > b) then return true end
    p, q = s:find("%d%d?%.%d%d?%.%d%d%d%d", q + 1)
  end
  return false
end

-- soldaki boşluğu da kapsa (görsel yapışma)
local function include_left_space(s, i)
  if i > 1 then
    local prev = s:sub(i-1, i-1)
    if prev:match("[%s\194\160\226\128\175]") then
      return i - 1
    end
  end
  return i
end

local function overlaps(a,b,r) return not (b<r.s or a>r.e) end

-- EK BAŞLANGICI whitelist (ayrı'yı elemek için 'r' yok!)
-- l,d,t,n,m,s,c,ç,ğ,y + sesliler (a,e,ı,i,o,ö,u,ü)
local SUF_START = "[ldtnmscy\195\167\196\159yaei\196\177io\195\182u\195\188]"
local SUF = SUF_START .. "[A-Za-z\128-\255]*"

-- TR kökleri (NFC/NFD “gün” için iki ayrı literal)
local ROOTS = {
  year   = { "yıl", "sene" },
  month  = { "ay" },
  week   = { "hafta" },
  hour   = { "saat" },
  minute = { "dakika" },
  second = { "saniye" },
  meter  = { "metre", "kilometre", "km" },
  centimeter = { "santimetre", "cm" },
}

-- "yarım" varyantları (sadece TR)
local HALF_TOKS = { "yar\196\177m", "Yar\196\177m" }

-- --- Türkçe büyük harf ve Baş Harf fonksiyonları ---
local function tr_upper(s)
  return (s
    :gsub("ü","Ü"):gsub("ö","Ö"):gsub("ç","Ç"):gsub("ş","Ş"):gsub("ğ","Ğ")
    :gsub("ı","I"):gsub("i","İ")
    :upper())
end

local function tr_capitalize(s)
  if s == "" then return s end
  local first = s:sub(1,1)
  local rest  = s:sub(2)
  return tr_upper(first) .. rest
end

-- --- tek bir listeyi ({"gün","günlük",...}) genişlet ---
local function expand_list(lst)
  local out, seen = {}, {}
  local function add(x)
    if not seen[x] then seen[x] = true; out[#out+1] = x end
  end
  for _, root in ipairs(lst) do
    add(root)                 -- orijinal
    add(tr_capitalize(root))  -- İlk harf büyük
    add(tr_upper(root))       -- TAM BÜYÜK
  end
  return out
end

-- --- tablo mu liste mi ayırt et ---
local function is_flat_array(t)
  local n = 0
  for k, _ in pairs(t) do
    if type(k) ~= "number" then return false end
    if k > n then n = k end
  end
  -- 1..n aralığı dışı numarik anahtar yoksa dizi sayalım
  for i=1,n do if t[i] == nil then return false end end
  return true
end

-- --- GENİŞLETİCİ: hem liste hem sınıf->liste yapısını destekler ---
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

ROOTS = expand_case_forms(ROOTS)
HALF_TOKS = expand_case_forms(HALF_TOKS)

-- ---------- eşleştiriciler ----------
local function push_hit(hits, s, i, j, class)
  if not inside_date_ddmmyyyy(s,i,j) and not is_after_HHMM(s,i) then
    i = include_left_space(s,i)
    for _,r in ipairs(hits) do
      if not (j<r.s or i>r.e) then return end
    end
    hits[#hits+1] = { s=i, e=j, class=class }
  end
end

-- Güvenli bitiş: boşluk/noktalama/NBSP/NNBSP veya satır sonu
local function safe_tail(s, head, token, class, hits)
  local PUNCT = "[%s,%.;:!%?%-%(%)]"

  -- ASCII boşluk/noktalama
  for a, b in s:gmatch(head .. token .. "()" .. PUNCT) do
    push_hit(hits, s, a, b-1, class)
  end
  -- NBSP
  for a, b in s:gmatch(head .. token .. "()\194\160") do
    push_hit(hits, s, a, b-1, class)
  end
  -- NNBSP
  for a, b in s:gmatch(head .. token .. "()\226\128\175") do
    push_hit(hits, s, a, b-1, class)
  end
  -- satır sonu
  for a, t2 in s:gmatch(head .. token .. "()$") do
    push_hit(hits, s, a, t2-1, class)
  end
end

local function hits_with_token(s, token, class, hits)
  -- yarım + birim
  for _, H in ipairs(HALF_TOKS) do
    -- Apostroflu
    for a,b in s:gmatch("()"..H..SP..token.."()"..APOS) do
      push_hit(hits, s, a, b-1, class)
    end
    -- Apostrofsuz -> güvenli kuyruk
    safe_tail(s, "()"..H..SP, token, class, hits)
  end

  -- sözlü aralık: NUM ile NUM
  for _, CC in ipairs({"ile","ila"}) do
    -- Apostroflu
    for a,b in s:gmatch("()"..NUM..SP..CC..SP..NUM..SP..token.."()"..APOS) do
      push_hit(hits, s, a, b-1, class)
    end
    -- Apostrofsuz -> güvenli kuyruk
    safe_tail(s, "()"..NUM..SP..CC..SP..NUM..SP, token, class, hits)
  end

  -- tireli aralık: NUM – NUM
  for _, D in ipairs(DASHES) do
    -- Apostroflu
    for a,b in s:gmatch("()"..NUM.."%s*"..D.."%s*"..NUM..SP..token.."()"..APOS) do
      push_hit(hits, s, a, b-1, class)
    end
    -- Apostrofsuz -> güvenli kuyruk
    safe_tail(s, "()"..NUM.."%s*"..D.."%s*"..NUM..SP, token, class, hits)
  end

  -- tekil: NUM + birim
  -- Apostroflu
  for a,b in s:gmatch("()"..NUM..SP..token.."()"..APOS) do
    push_hit(hits, s, a, b-1, class)
  end
  -- Apostrofsuz -> güvenli kuyruk
  safe_tail(s, "()" .. NUM .. SP, token, class, hits)
end

local function hits_for_TR(s, roots, class)
  local hits = {}
  for _,root in ipairs(roots) do
    hits_with_token(s, root,        class, hits)
    hits_with_token(s, root .. SUF, class, hits)
  end
  return hits
end

local function has_trace(text)
  local forms = expand_case_forms(
    {"yıl", "sene", "hafta", "ay", "saat", "dakika", "saniye",
     "metre", "kilometre", "km", "santimetre", "cm"})

  for _, variant in ipairs(forms) do
    if text:find(variant, 1, true) then
      return true
    end
  end
  return false
end

local function find_hits(text)
  if not has_trace(text) then return {} end
  local hits = {}

  for cls, roots in pairs({
    year   = ROOTS.year,
    month  = ROOTS.month,
    day    = ROOTS.day,
    week   = ROOTS.week,
    hour   = ROOTS.hour,
    minute = ROOTS.minute,
    second = ROOTS.second,
    meter  = ROOTS.meter,
    centimeter = ROOTS.centimeter,
  }) do
    local h = hits_for_TR(text, roots, cls)
    for _,x in ipairs(h) do hits[#hits+1]=x end
  end

  -- çakışma temizliği: uzun (range) kalsın
  table.sort(hits, function(a,b) return a.s<b.s or (a.s==b.s and a.e<b.e) end)
  local out={}
  for _,h in ipairs(hits) do
    local keep=true
    for _,k in ipairs(out) do
      if overlaps(h.s,h.e,k) then
        if (h.e-h.s) <= (k.e-k.s) then keep=false end
      end
    end
    if keep then out[#out+1]=h end
  end
  return out
end
-- -------- Inlines ----------
local function is_textlike(el) return el.t=="Str" or el.t=="Space" or el.t=="SoftBreak" end
local function Inlines(inlines)
  local out, i, n = List:new(), 1, #inlines
  while i<=n do
    if is_textlike(inlines[i]) then
      local run, j = List:new(), i
      while j<=n and is_textlike(inlines[j]) do run:insert(inlines[j]); j=j+1 end
      local text, map = linearize(run)
      local hits = find_hits(text)
      out:extend(rebuild(run, text, map, hits))
      i=j
    else
      local el=inlines[i]
      if el.content and type(el.content)=="table" then el.content=Inlines(el.content) end
      out:insert(el); i=i+1
    end
  end
  return out
end

M.Inlines = Inlines
return M

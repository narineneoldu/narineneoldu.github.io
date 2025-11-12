-- ../shared/lua/span_day.lua
-- Sadece TR: "gün" ile ilgili süre ibarelerini <span class="day">...</span> içine alır.

local M = {}
local List = require 'pandoc.List'

-- ---------- ortak yardımcılar ----------
local function linearize(run)
  local buf, map, pos = {}, {}, 0
  for i, el in ipairs(run) do
    if el.t == "Str" then
      local s = el.text
      for k=1,#s do pos=pos+1; buf[pos]=s:sub(k,k); map[pos]={ix=i,off=k} end
    elseif el.t=="Space" or el.t=="SoftBreak" then
      pos=pos+1; buf[pos]=" "; map[pos]={ix=i,off=0}
    end
  end
  return table.concat(buf), map
end

local function rebuild(run, text, map, hits)
  if #hits==0 then return run end
  table.sort(hits,function(a,b) return a.s<b.s or (a.s==b.s and a.e<b.e) end)
  local out,pos=List:new(),1
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
    if pos<h.s then emit_plain(pos,h.s-1) end
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
    out:insert(pandoc.Span({pandoc.Str(tok)}, pandoc.Attr("", {"day"})))
    pos=h.e+1
  end
  if pos<=#text then emit_plain(pos,#text) end
  return out
end

-- ---------- desenler ----------
local NUM="%d+[.,]?%d*"
local DASHES={"-","\226\128\147","\226\128\148","\226\128\146","\226\128\145","\226\136\146"}
local SP="[%s\194\160\226\128\175]+"
local APOS="['\226\128\153\226\128\152\202\188]"
local BND="%f[%A]"

local function inside_date_ddmmyyyy(s,a,b)
  local L=math.max(1,a-5)
  local p,q=s:find("%d%d?%.%d%d?%.%d%d%d%d",L)
  while p do
    if not (q<a or p>b) then return true end
    p,q=s:find("%d%d?%.%d%d?%.%d%d%d%d",q+1)
  end
  return false
end
local function is_after_HHMM(s,start_idx)
  local L=math.max(1,start_idx-5)
  return s:sub(L,start_idx-1):match("%d%d?%s*:%s*$")~=nil
end
local function include_left_space(s,i)
  if i>1 and s:sub(i-1,i-1):match("[%s\194\160\226\128\175]") then return i-1 end
  return i
end
local function overlaps(a,b,r) return not(b<r.s or a>r.e) end

-- kök kelime
local base = "gün"

-- eklenecek ekler (boş olan, yalnızca kökü verir)
local suffixes = { "", "den", "dür", "lük", "lüğüne" }

-- kök + ek birleşiminden ROOTS_DAY listesi oluştur
local ROOTS_DAY = {}
for _, suf in ipairs(suffixes) do
  table.insert(ROOTS_DAY, base .. suf)
end

local HALF_TOKS = { "yar\196\177m" }

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

ROOTS_DAY = expand_case_forms(ROOTS_DAY)
HALF_TOKS = expand_case_forms(HALF_TOKS)

-- güvenli kuyruk
local function safe_tail(s,head,token,class,hits)
  local PUNCT="[%s,%.;:!%?%-%(%)]"
  for a,b in s:gmatch(head..token.."()"..PUNCT) do
    if not inside_date_ddmmyyyy(s,a,b) and not is_after_HHMM(s,a) then
      a=include_left_space(s,a); hits[#hits+1]={s=a,e=b-1,class=class}
    end
  end
  for a,b in s:gmatch(head..token.."()".."$") do
    a=include_left_space(s,a); hits[#hits+1]={s=a,e=b-1,class=class}
  end
end

local function hits_with_token(s,token,class,hits)
  -- yarım + birim
  for _, H in ipairs(HALF_TOKS) do
    -- Apostroflu
    for a,b in s:gmatch("()"..H..SP..token.."()"..APOS) do
      push_hit(hits, s, a, b-1, class)
    end
    -- Apostrofsuz -> güvenli kuyruk
    safe_tail(s, "()"..H..SP, token, class, hits)
  end

  for _,CC in ipairs({"ile","ila"}) do
    safe_tail(s,"()"..NUM..SP..CC..SP..NUM..SP,token,class,hits)
  end

  for _,D in ipairs(DASHES) do
    safe_tail(s,"()"..NUM.."%s*"..D.."%s*"..NUM..SP,token,class,hits)
  end

  safe_tail(s,"()"..NUM..SP,token,class,hits)
end

local function dedupe_hits(hits)
  -- önce başlangıca göre, eşitse daha UZUN olana göre sırala
  table.sort(hits, function(a,b)
    if a.s ~= b.s then return a.s < b.s end
    return (a.e - a.s) > (b.e - b.s)
  end)

  local out = {}
  for _, h in ipairs(hits) do
    local keep = true
    for _, k in ipairs(out) do
      -- overlap varsa kısa olanı at (out zaten uzunları öne aldı)
      if not (h.e < k.s or h.s > k.e) then
        keep = false
        break
      end
    end
    if keep then out[#out+1] = h end
  end
  return out
end

local function has_trace(text)
  local ROOTS_DAY = expand_case_forms({"gün"})
  for _, variant in ipairs(ROOTS_DAY) do
    if text:find(variant, 1, true) then
      return true
    end
  end
  return false
end

local function find_hits(text)
  if not has_trace(text) then return {} end
  local hits = {}
  for _, root in ipairs(ROOTS_DAY) do
    hits_with_token(text, root, "day", hits)
  end
  return dedupe_hits(hits)
end

-- ---------- Inlines ----------
local function is_textlike(el) return el.t=="Str" or el.t=="Space" or el.t=="SoftBreak" end
local function Inlines(inlines)
  local out,i,n=List:new(),1,#inlines
  while i<=n do
    if is_textlike(inlines[i]) then
      local run,j=List:new(),i
      while j<=n and is_textlike(inlines[j]) do run:insert(inlines[j]); j=j+1 end
      local text,map=linearize(run)
      local hits=find_hits(text)
      out:extend(rebuild(run,text,map,hits))
      i=j
    else
      local el=inlines[i]
      if el.content and type(el.content)=="table" then el.content=Inlines(el.content) end
      out:insert(el); i=i+1
    end
  end
  return out
end

M.Inlines=Inlines
return M

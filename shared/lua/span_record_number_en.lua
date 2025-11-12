-- ../shared/lua/span_record_number_en.lua
-- Wrap numeric tokens that FOLLOW English legal labels (No., Article, Art., Case No., Law No., etc.)
-- Only the numeric token is wrapped: <span class="record-number">...</span>

local M = {}
local List = require 'pandoc.List'

local skip = { Code=true, CodeBlock=true, Math=true, Link=true, Image=true, RawInline=true, RawBlock=true }

local function has_class(attr, name)
  if not attr or not attr.classes then return false end
  for _, c in ipairs(attr.classes) do if c == name then return true end end
  return false
end

local function is_url_context(s, lpos)
  local from = math.max(1, lpos - 12)
  return s:sub(from, lpos):find("://") ~= nil
end

local function is_textlike(el) return el.t=="Str" or el.t=="Space" or el.t=="SoftBreak" end

local function linearize(run)
  local buf, map, pos = {}, {}, 0
  for i, el in ipairs(run) do
    if el.t=="Str" then
      local s=el.text
      for k=1,#s do pos=pos+1; buf[pos]=s:sub(k,k); map[pos]={ix=i, off=k} end
    else
      pos=pos+1; buf[pos]=" "; map[pos]={ix=i, off=0}
    end
  end
  return table.concat(buf), map
end

local function rebuild(run, text, map, hits)
  if #hits==0 then return run end
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
    local parts, i = {}, h.s
    while i<=h.e do
      local m=map[i]
      if m and m.off==0 then table.insert(parts," "); i=i+1
      elseif m then
        local ix,soff=m.ix,m.off; local j=i; local eoff=soff
        while j+1<=h.e and map[j+1] and map[j+1].ix==ix and map[j+1].off==eoff+1 do j=j+1; eoff=eoff+1 end
        table.insert(parts, run[ix].text:sub(soff,eoff)); i=j+1
      else i=i+1 end
    end
    out:insert(pandoc.Span({ pandoc.Str(table.concat(parts)) }, pandoc.Attr("", {"record-number"})))
    pos=h.e+1
  end
  if pos<=#text then emit_plain(pos, #text) end
  return out
end

-- ---- matching ----
local SP = "[%s\194\160\226\128\175]+"  -- space / NBSP / NNBSP

-- Etiketler (lowercase karşılaştıracağız)
local LABELS = {
  "no", "no.", "number", "law no", "case no", "decision no",
  "article", "art", "art.", "section", "sec", "sec.", "subsection",
  "paragraph", "para", "para.", "clause", "numbered"
}

-- Solu sadeceleyip (boşluk, nokta, vb.), anahtar kelime ile bitiyor mu?
local function has_preceding_keyword(text, lpos)
  local head = text:sub(1, lpos-1)
  -- sondaki boşlukları (SP deseni) at
  head = head:gsub("("..SP..")$", "")
  -- sondaki noktalama: . , ; : ) ]
  head = head:gsub("[%.:,;%)%]]+$", "")
  -- tekrar olası boşluklar
  head = head:gsub("("..SP..")$", "")
  head = head:lower()
  for _, kw in ipairs(LABELS) do
    local pat = kw:gsub("%.", "%%.") .. "$"
    if head:find(pat) then return true end
  end
  return false
end

-- 1) Genel token: 81/1, 2024/9732, 12-3, 37  (sondaki . dahil edilmez)
-- 2) Parantezli durum için: Section 5(a) -> sadece "5" (parantez dışı)
local function find_hits(text)
  local hits = {}

  -- (a) gibi parantezler gelirse yalnızca ilk sayıyı alacak genel patern:
  for lpos, tok, dot, rpos in text:gmatch("()%f[%d](%d[%w%-/⁄∕]*)(%.?)()") do
    if not is_url_context(text, lpos) and has_preceding_keyword(text, lpos) then
      local e_core = lpos + #tok - 1
      hits[#hits+1] = { s = lpos, e = e_core }
    end
  end

  -- Özel: "Section 5(a)" gibi; parantez açılıyorsa sadece çıplak sayıyı al
  for lpos, num in text:gmatch("()%f[%d](%d+)%(") do
    if not is_url_context(text, lpos) and has_preceding_keyword(text, lpos) then
      local e_core = lpos + #num - 1
      hits[#hits+1] = { s = lpos, e = e_core }
    end
  end

  table.sort(hits, function(a,b) return a.s<b.s or (a.s==b.s and a.e<b.e) end)
  -- çakışma ayıkla
  local out={}
  for _,h in ipairs(hits) do
    local keep=true
    for _,k in ipairs(out) do
      if not (h.e<k.s or h.s>k.e) then keep=false; break end
    end
    if keep then out[#out+1]=h end
  end
  return out
end

-- ---- walker ----
local function process_inlines(inlines)
  local out = List:new()
  local i, n = 1, #inlines
  while i<=n do
    local el = inlines[i]
    if is_textlike(el) then
      local run, j = List:new(), i
      while j<=n and is_textlike(inlines[j]) do run:insert(inlines[j]); j=j+1 end
      local text, map = linearize(run)
      if text:find("%d") then
        local hits = find_hits(text)
        out:extend(rebuild(run, text, map, hits))
      else
        out:extend(run)
      end
      i=j
    else
      if el.content and not skip[el.t] and not (el.t=="Span" and has_class(el.attr, "record-number")) then
        el.content = process_inlines(el.content)
      end
      out:insert(el); i=i+1
    end
  end
  return out
end

M.Inlines = process_inlines
return M

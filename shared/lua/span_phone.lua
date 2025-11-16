-- ../shared/lua/span_phone.lua
-- 11 haneli 05... numaraları ve 05ddXXXdddd (X/x maskeli) kalıplarını
-- <span class="phone" data-title="...">…</span> ile sarar (title değil!).

local M = {}
local List  = require 'pandoc.List'
local PHONES = nil

-- ---- meta'dan sözlük yükle ----
local function load_phones_from_meta(meta)
  if not meta then return end
  local dict = meta.phones or (meta.metadata and meta.metadata.phones)
  if type(dict) ~= "table" then return end
  local t = {}
  for k, v in pairs(dict) do
    local key = pandoc.utils.stringify(k)
    local val = pandoc.utils.stringify(v)
    if key ~= "" and val ~= "" then
      -- normalize: trim, tek boşluk, X'leri büyük harfe çevir
      key = key:gsub("%s+", " "):match("^%s*(.-)%s*$")
      key = key:gsub("[Xx]", "X")
      t[key] = val
    end
  end
  if next(t) then PHONES = t end
end

-- ---- desenler ----
-- 1) Maskeli: 05ddXXXdddd  (X veya x kabul)
local PAT_MASK = '%f[%d](05%d%d[Xx][Xx][Xx]%d%d%d%d)%f[%D]'
-- 2) Tam sayı: 05 + 9 rakam (toplam 11 hane)
local PAT_NUM  = '%f[%d](05%d%d%d%d%d%d%d%d%d)%f[%D]'

local function find_next_phone(s, i)
  local a1, b1 = s:find(PAT_MASK, i)
  local a2, b2 = s:find(PAT_NUM,  i)
  if a1 and a2 then
    if a1 <= a2 then return a1, b1 else return a2, b2 end
  end
  return a1 and a1, a1 and b1 or a2, b2
end

-- ---- yardımcılar ----
local function tip_for(token)
  -- token'ı metadata anahtarı ile aynı normalize et
  local key = token:gsub("%s+", " "):match("^%s*(.-)%s*$")
  key = key:gsub("[Xx]", "X")
  return PHONES and PHONES[key] or nil
end

local function span_phone(token)
  local attrs = {}
  -- TODO: erişilebilirlik için tabindex ve aria-label ekle
  -- git-diff için attribute sırası dalaşması sorununu çözmen gerekiyor.
  -- attrs["tabindex"] = "0"            -- mobil/klavye için odaklanabilir
  -- attrs["aria-label"] = tip  -- ekran okuyucu için
  local tip = tip_for(token)
  if tip then attrs["data-title"] = tip end    -- native title KULLANMIYORUZ
  return pandoc.Span({ pandoc.Str(token) }, pandoc.Attr('', { 'phone' }, attrs))
end

-- ---- Str içini parçalayıp sar ----
local function wrap_phones_in_str(text)
  if not text:find("05", 1, true) then return nil end
  local out = List:new()
  local i, n = 1, #text
  while i <= n do
    local a, b = find_next_phone(text, i)
    if not a then out:insert(pandoc.Str(text:sub(i))); break end
    if a > i then out:insert(pandoc.Str(text:sub(i, a - 1))) end
    local tok = text:sub(a, b)
    -- io.stderr:write(string.format("[span-phone] hit: %s\n", tok))
    out:insert(span_phone(tok))
    i = b + 1
  end
  return (#out > 0) and out or nil
end

-- ---- HTML içinde de sar (idempotent) ----
local function html_wrap_all(s)
  if s:match('class="[^"]*phone') then return s end
  s = s:gsub(PAT_MASK, function(m)
    local tip = tip_for(m)
    local attr = tip and (' data-title="' .. m:gsub('"','&quot;'):gsub("&","&amp;") ..
                          '">') or '">'
    return '<span class="phone"' .. (tip and (' data-title="'..tip..'"') or '') .. '>' .. m .. '</span>'
  end)
  s = s:gsub(PAT_NUM, function(m)
    local tip = tip_for(m)
    return '<span class="phone"' .. (tip and (' data-title="'..tip..'"') or '') .. '>' .. m .. '</span>'
  end)
  return s
end

-- ---- skip list ----
local skip = {
  Code = true, CodeBlock = true, Math = true, Link = true, Image = true,
  RawInline = true, RawBlock = true
}

-- ---- Walker ----
local function process_inlines(inlines)
  local out = List:new()
  for _, el in ipairs(inlines) do
    if el.t == 'Str' then
      local repl = wrap_phones_in_str(el.text)
      if repl then out:extend(repl) else out:insert(el) end
    elseif el.t == 'Span' then
      if el.attr and el.attr.classes and el.attr.classes:includes('phone') then
        out:insert(el)
      else
        if el.content then el.content = process_inlines(el.content) end
        out:insert(el)
      end
    else
      if el.content and not skip[el.t] then
        el.content = process_inlines(el.content)
      end
      out:insert(el)
    end
  end
  return out
end

-- ---- Pandoc entrypoint (Meta sırası garantisi) ----
function M.Pandoc(doc)
  PHONES = nil
  load_phones_from_meta(doc.meta)
  return doc:walk({
    Inlines   = function(inl) return process_inlines(inl) end,
    RawInline = function(el)
      if el.format == 'html' then el.text = html_wrap_all(el.text); return el end
      return nil
    end,
    RawBlock  = function(el)
      if el.format == 'html' then el.text = html_wrap_all(el.text); return el end
      return nil
    end
  })
end

return M

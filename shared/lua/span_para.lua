-- ../shared/lua/span_para.lua
-- ( ... ) parantez içlerini <span class="paranthesis">...</span> ile sarar.
-- Sadece Para/Plain içinde çalışır; Header’a dokunmaz.
-- Zaten boyanmış bazı span’lere (quote-grey, time-badge, date-badge, paranthesis) dokunmaz.

local M = {}
local List = require 'pandoc.List'

local function has_class(attr, names)
  if not attr or not attr.classes then return false end
  for _, c in ipairs(attr.classes) do
    for __, n in ipairs(names) do
      if c == n then return true end
    end
  end
  return false
end

local SKIP_SPAN_CLASSES = { 'quote-grey', 'time-badge', 'date-badge', 'paranthesis' }

-- Inline’ları dolaş: açılan '(' ile kapanan ')' arasını buffer’la, kapatınca span’a sar
local function process_inlines(inlines)
  local out        = List:new()
  local buf        = List:new()
  local in_paren   = false

  local function flush_buffer(as_span)
    if #buf == 0 then return end
    if as_span then
      out:insert(pandoc.Span(buf, pandoc.Attr('', {'paranthesis'})))
    else
      for _, x in ipairs(buf) do out:insert(x) end
    end
    buf = List:new()
  end

  local function emit(el)
    if in_paren then buf:insert(el) else out:insert(el) end
  end

  for _, el in ipairs(inlines) do
    local t = el.t

    -- Header içindeki Strong/Emph/… gibi yapılara girmeye gerek yok; düz akış
    if t == 'Span' and has_class(el.attr, SKIP_SPAN_CLASSES) then
      -- Bu özel span’leri aynen geçir
      emit(el)

    elseif t == 'Span' then
      -- Kendi içeriğini de tarayalım (özel sınıf değilse)
      local new_content = process_inlines(el.content)
      emit(pandoc.Span(new_content, el.attr))

    elseif t == 'Link' then
      -- Link içinde de çalışsın isterseniz burayı process_inlines yapıyoruz
      local new_content = process_inlines(el.content)
      emit(pandoc.Link(new_content, el.target, el.title, el.attr))

    elseif t == 'Strong' or t == 'Emph' or t == 'Cite' then
      -- Stil düğümlerine girip içeriğini tarayalım
      local new_content = process_inlines(el.content)
      local ctor = pandoc[t]
      emit(ctor(new_content))

    elseif t == 'Str' then
      local s = el.text or ""
      -- Hızlı yol: hiç parantez yoksa direkt yaz
      if (not s:find("%(")) and (not s:find("%)")) then
        emit(el)
      else
        -- Karakter karakter ilerleyip '(' ve ')' durumlarını yöneteceğiz
        local i, n = 1, #s
        while i <= n do
          local next_open  = s:find("%(", i)
          local next_close = s:find("%)", i)

          if not next_open and not next_close then
            -- Kalanı dök
            local tail = s:sub(i)
            if #tail > 0 then emit(pandoc.Str(tail)) end
            break
          end

          -- Sıradaki token hangisi yakın?
          local pick, pos = nil, nil
          if next_open and next_close then
            if next_open < next_close then pick, pos = "open", next_open else pick, pos = "close", next_close end
          elseif next_open then
            pick, pos = "open", next_open
          else
            pick, pos = "close", next_close
          end

          -- Öncesini yaz
          if pos > i then
            emit(pandoc.Str(s:sub(i, pos - 1)))
          end

          -- Parantez token’ını yaz ve durumu güncelle
          if pick == "open" then
            in_paren = true
            emit(pandoc.Str("("))
          else -- "close"
            emit(pandoc.Str(")"))
            if in_paren then
              -- Kapanış: şimdiye kadar birikenleri tek <span> olarak çıkar
              in_paren = false
              flush_buffer(true)
            end
          end
          i = pos + 1
        end
      end

    else
      -- Code, Math, RawInline vs. olduğu gibi
      emit(el)
    end
  end

  -- Satır biter ve parantez kapanmadıysa: buffer’ı span yapmadan dök
  if in_paren then flush_buffer(false) end
  return out
end

-- ---- Block handlers ----
local function process_block(b)
  if b.t == 'Header' then return nil end
  if b.t == 'Para' or b.t == 'Plain' then
    return pandoc.Para(process_inlines(b.content))
  end
  return nil
end

M.Para  = process_block
M.Plain = process_block
return M

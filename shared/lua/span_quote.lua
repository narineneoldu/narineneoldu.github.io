-- ../shared/lua/span_quote.lua
-- Çift tırnak içi metni (tırnaklar DAHİL) <span class="quote">...</span> ile sarar.
-- Sadece Para/Plain içinde çalışır; Header/Strong/Emph içine girmez.
-- Zaten quote-grey/time-badge içindekilere dokunmaz. HTML'e dokunmaz.

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

-- Inline listesini dolaşırken, tırnaklar arası içeriği buffer'da biriktirip tek span'e saracağız.
local function process_inlines(inlines)
  local out       = List:new()
  local buf       = List:new()  -- tırnak içi birikim
  local in_quote  = false

  local function flush_buffer(as_span)
    if #buf == 0 then return end
    if as_span then
      out:insert(pandoc.Span(buf, pandoc.Attr('', {'quote'})))
    else
      for _, x in ipairs(buf) do out:insert(x) end
    end
    buf = List:new()
  end

  local function emit(el)
    if in_quote then buf:insert(el) else out:insert(el) end
  end

  for _, el in ipairs(inlines) do
    local t = el.t

    -- Bold/italik: içine GİRME
    if t == 'Strong' or t == 'Emph' then
      emit(el)

    -- Zaten boyanmış/ saat span'ı ise hiç dokunma
    elseif t == 'Span' and has_class(el.attr, {'quote', 'time'}) then
      emit(el)

    -- Akıllı tırnak (Quoted) geldi: komple gri/italik sar (tırnaklar dahil)
    elseif t == 'Quoted' then
      emit(pandoc.Span({ el }, pandoc.Attr('', {'quote'})))

    -- Span: içerisine RECURSE et (ama sınıfları koru)
    elseif t == 'Span' then
      local new_content = process_inlines(el.content)
      emit(pandoc.Span(new_content, el.attr))

    -- Link: içerisine RECURSE et, hedef/başlığı koru
    elseif t == 'Link' then
      local new_content = process_inlines(el.content)
      -- Pandoc 2.x: Link(content, target, title, attr)
      emit(pandoc.Link(new_content, el.target, el.title, el.attr))

    -- Diğer inline türleri: olduğu gibi, fakat Str için tırnak state yönetimi
    elseif t == 'Str' then
      local s = el.text or ""
      if s:find('"', 1, true) == nil then
        emit(el)
      else
        local i, n = 1, #s
        while i <= n do
          local qpos = s:find('"', i, true)
          if not qpos then
            local tail = s:sub(i)
            if #tail > 0 then emit(pandoc.Str(tail)) end
            break
          end
          -- önce tırnak öncesini yaz
          if qpos > i then emit(pandoc.Str(s:sub(i, qpos - 1))) end
          -- tırnak karakterini yaz
          emit(pandoc.Str('"'))
          -- state değiştir
          in_quote = not in_quote
          -- kapandıysa buffer'ı tek span olarak boşalt
          if not in_quote then
            flush_buffer(true)
          end
          i = qpos + 1
        end
      end

    else
      -- SmallCaps, Strikeout, Superscript, Subscript, Note, Cite vs: olduğu gibi bırak
      emit(el)
    end
  end

  -- Eşleşmeyen tırnakla biterse, span yapmadan dök
  if in_quote then flush_buffer(false) end
  return out
end

-- ---- Block handlers ----
local function process_block(b)
  if b.t == 'Header' then return nil end            -- başlıklara dokunma
  if b.t == 'Para' or b.t == 'Plain' then
    return pandoc.Para(process_inlines(b.content))  -- Plain de Para gibi döner, sorun değil
  end
  return nil
end

return {
  {
    Para  = process_block,
    Plain = process_block,
    -- Header yok: dokunmuyoruz
    -- RawInline/RawBlock yok: HTML'ye dokunmuyoruz
  }
}

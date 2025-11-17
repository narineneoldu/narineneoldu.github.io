-- ../shared/lua/inline_utils.lua
-- Ortak run linearize + rebuild araçları

local List = require 'pandoc.List'

local U = {}

-- Str / Space / SoftBreak mı?
function U.is_textlike(el)
  return el.t == "Str" or el.t == "Space" or el.t == "SoftBreak"
end

-- Koşu -> düz string + pozisyon haritası
-- map[pos] = { ix = run içindeki eleman index'i, off = Str içindeki offset veya 0 (space) }
function U.linearize_run(run)
  local buf, map = {}, {}
  local pos = 0

  for idx, el in ipairs(run) do
    if el.t == "Str" then
      local s = el.text
      for i = 1, #s do
        pos = pos + 1
        buf[pos] = s:sub(i, i)
        map[pos] = { ix = idx, off = i }
      end
    elseif el.t == "Space" or el.t == "SoftBreak" then
      pos = pos + 1
      buf[pos] = " "
      map[pos] = { ix = idx, off = 0 }
    end
  end

  return table.concat(buf), map
end

-- Non-overlap edilmiş hit listesi + builder ile koşuyu yeniden inşa et
-- hits: { {s= , e= , kind="...", ...}, ... }  (1-based, text index)
-- build_span(tok, hit) -> Inline (ör: Span) ya da nil
function U.rebuild_run(run, text, map, hits, build_span)
  if #hits == 0 then
    return run
  end

  local out = List:new()
  local pos = 1
  local text_len = #text

  -- text[p1..p2] aralığını plain olarak, map’e göre eski inlinelara bölerek üret
  local function emit_plain(p1, p2)
    if p2 < p1 then return end
    local i = p1
    while i <= p2 do
      local m = map[i]
      if not m then
        i = i + 1
      elseif m.off == 0 then
        out:insert(pandoc.Space())
        i = i + 1
      else
        local ix, start_off = m.ix, m.off
        local j, end_off = i, start_off

        while j + 1 <= p2 do
          local m2 = map[j + 1]
          if not (m2 and m2.ix == ix and m2.off == end_off + 1) then break end
          j = j + 1
          end_off = end_off + 1
        end

        local el = run[ix]
        out:insert(pandoc.Str(el.text:sub(start_off, end_off)))
        i = j + 1
      end
    end
  end

  local hix = 1
  while pos <= text_len and hix <= #hits do
    local h = hits[hix]

    -- hit başlamadan önceki kısmı plain bas
    if pos < h.s then
      emit_plain(pos, h.s - 1)
      pos = h.s
    end

    -- hit’in text karşılığını topla
    local parts = {}
    local i = h.s
    local seen_nonspace = false

    while i <= h.e do
      local m = map[i]
      if m and m.off == 0 then
        -- Leading spaces should stay OUTSIDE the span
        if not seen_nonspace then
          out:insert(pandoc.Space())
        else
          table.insert(parts, " ")
        end
        i = i + 1

      elseif m then
        seen_nonspace = true
        local ix, start_off = m.ix, m.off
        local j, end_off = i, start_off

        while j + 1 <= h.e do
          local m2 = map[j + 1]
          if not (m2 and m2.ix == ix and m2.off == end_off + 1) then break end
          j = j + 1
          end_off = end_off + 1
        end

        local el = run[ix]
        table.insert(parts, el.text:sub(start_off, end_off))
        i = j + 1

      else
        i = i + 1
      end
    end

    local tok = table.concat(parts)
    local span_inline = build_span(tok, h)

    if span_inline then
      out:insert(span_inline)
    else
      -- builder span dönmezse plain davran
      emit_plain(h.s, h.e)
    end

    pos = h.e + 1
    hix = hix + 1
  end

  -- kalan kuyruk
  if pos <= text_len then
    emit_plain(pos, text_len)
  end

  return out
end

return U

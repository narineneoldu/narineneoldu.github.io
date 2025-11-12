-- ../shared/lua/anchor_lines.lua
-- — satır sonu anchor; tablo caption {#… .…} bloğunu korur (anchor'ı önüne ekler)

-- --- guard: index.qmd'te filtreden çık ---
local input = (quarto and quarto.doc and quarto.doc.input_file) or ""
if type(input) == "string" and input ~= "" then
  -- Yalın dosya adını çek (slash veya backslash'tan sonraki parça)
  local fname = input:match("([^/\\]+)$") or input
  if fname == "index.qmd" then
    return {}  -- bu dosyada filtre tamamen devre dışı
  end
end
-- --- /guard ---

local n = 0

local function starts_with_bracket(block)
  if not block or not block.content then return false end
  for _, inline in ipairs(block.content) do
    local t = inline.t
    if t == 'Space' or t == 'SoftBreak' or t == 'LineBreak' then
      -- geç
    elseif t == 'Str' or t == 'Code' then
      return (inline.text or inline.c or ""):match("^%[") ~= nil
    elseif t == 'RawInline' then
      local s = inline.text or (inline.c and inline.c[2]) or ""
      return tostring(s):match("^%[") ~= nil
    else
      return false
    end
  end
  return false
end

local function empty_anchor(href, cls, label)
  local zwsp = pandoc.RawInline('html', '&#8203;')
  return pandoc.Link({ zwsp }, href, "", { class = cls, ["aria-label"] = label })
end

-- Satır sonuna anchor ekle (Para/Plain)
local function wrap_with_anchor(block, kind)
  if starts_with_bracket(block) then return block end
  n = n + 1
  local id = string.format("L%03d", n)
  local link = empty_anchor("#" .. id, "line-anchor", "Bu satıra bağlantı")

  local new_inlines = pandoc.List()
  for _, x in ipairs(block.content) do new_inlines:insert(x) end
  new_inlines:insert(link)

  local inner = (kind == "Para") and pandoc.Para(new_inlines) or pandoc.Plain(new_inlines)
  return pandoc.Div({ inner }, pandoc.Attr(id, {"anchored-line"}))
end

-- ---- Caption helpers ----
local function get_caption_blocks(tbl)
  if tbl.caption and tbl.caption.long then return tbl.caption.long end
  if type(tbl.caption) == "table" and tbl.caption.long then return tbl.caption.long end
  return nil
end
local function set_caption_blocks(tbl, blocks)
  if tbl.caption and tbl.caption.long then tbl.caption.long = blocks; return end
  if type(tbl.caption) == "table" and tbl.caption.long then tbl.caption.long = blocks; return end
end

-- Sondaki boşlukları kırp (kontrol için yardımcı)
local function is_space_like(el)
  return el and (el.t == "Space" or el.t == "SoftBreak" or el.t == "LineBreak")
end

-- Caption sonunda { ... } bloğunun Str + Space + Str ... dizisi olarak bulunup bulunmadığını saptar.
-- Varsa başlangıç ve bitiş indexlerini (i, j) döner; yoksa nil.
local function find_trailing_attr_range(inlines)
  local j = #inlines
  if j == 0 then return nil end

  -- Sondaki boşlukları görmezden gel
  while j >= 1 and is_space_like(inlines[j]) do j = j - 1 end
  if j < 1 then return nil end

  -- Sonda '}' ile biten bir Str olmalı
  local last = inlines[j]
  local txt = last and (last.c or last.text or "")
  if not (last and last.t == "Str" and tostring(txt):match("}$")) then
    return nil
  end

  -- '{' ile başlayan ilk Str'ye kadar geriye topla (aralarda sadece Space/Str olmalı)
  local i = j
  local saw_open = false
  while i >= 1 do
    local el = inlines[i]
    if el.t == "Str" then
      local s = el.c or el.text or ""
      if s:match("^%{") then
        saw_open = true
        break
      end
      i = i - 1
    elseif is_space_like(el) then
      i = i - 1
    else
      -- Başka bir tipe çarptık → yok say
      return nil
    end
  end

  if not saw_open then return nil end
  return i, j
end

-- ---- Recursive walker ----
local function visit_block(blk)
  if blk.t == "Para" then
    return wrap_with_anchor(blk, "Para")

  elseif blk.t == "Plain" then
    return wrap_with_anchor(blk, "Plain")

  elseif blk.t == "Table" then
    -- tabloya (yoksa) id ver
    blk.attr = blk.attr or pandoc.Attr()
    if not blk.attr.identifier or blk.attr.identifier == "" then
      n = n + 1
      blk.attr.identifier = string.format("L%03d", n)
    end

    -- caption’ın ilk bloğunu işle
    local cap = get_caption_blocks(blk)
    if cap and #cap > 0 then
      local first = cap[1]
      if first and (first.t == "Para" or first.t == "Plain") and first.content then
        -- Anchor'ı, varsa {#… .…} bloğunun hemen ÖNÜNE ekle; yoksa en sona ekle.
        local i, j = find_trailing_attr_range(first.content)
        local link = empty_anchor("#" .. blk.attr.identifier, "line-anchor", "Bu tabloya bağlantı")

        if i and j then
          -- { … } bloğu var: anchor'ı onun öncesine koy
          -- Gerekirse önce bir Space ekle (caption metninden ayrışsın)
          local needs_space = (#first.content > 0) and (not is_space_like(first.content[i-1]))
          local insert_at = i
          if needs_space then
            table.insert(first.content, insert_at, pandoc.Space()); insert_at = insert_at + 1
          end
          table.insert(first.content, insert_at, link)
        else
          -- yoksa en sona ekle (mevcut davranış)
          table.insert(first.content, link)
        end

        cap[1] = (first.t == "Para") and pandoc.Para(first.content) or pandoc.Plain(first.content)
        set_caption_blocks(blk, cap)
      end
    end
    return blk

  elseif blk.t == "Div" or blk.t == "BlockQuote" then
    local out = pandoc.List()
    for _, b in ipairs(blk.content) do out:insert(visit_block(b) or b) end
    blk.content = out
    return blk

  elseif blk.t == "BulletList" or blk.t == "OrderedList" then
    local items = pandoc.List()
    for _, item in ipairs(blk.content) do
      local newitem = pandoc.List()
      for _, b in ipairs(item) do newitem:insert(visit_block(b) or b) end
      items:insert(newitem)
    end
    blk.content = items
    return blk

  elseif blk.t == "DefinitionList" then
    local defs = pandoc.List()
    for _, def in ipairs(blk.content) do
      local term, lists = def[1], def[2]
      local newlists = pandoc.List()
      for _, lst in ipairs(lists) do
        local newlst = pandoc.List()
        for _, b in ipairs(lst) do newlst:insert(visit_block(b) or b) end
        newlists:insert(newlst)
      end
      defs:insert({term, newlists})
    end
    blk.content = defs
    return blk
  end
  return nil
end

function Pandoc(doc)
  local out = pandoc.List()
  for _, b in ipairs(doc.blocks) do out:insert(visit_block(b) or b) end
  doc.blocks = out
  return doc
end

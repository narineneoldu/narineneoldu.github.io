-- abbr.lua — metadata.abbr sözlüğündeki "key" dizilerini <abbr> ile sar
-- Not: Header (başlık) blokları hariç!

local M = {}
local ABBR = nil

-- -- Yardımcılar -------------------------------------------------------------

local function to_plain_map(meta_map)
  local t = {}
  for k, v in pairs(meta_map) do
    local key = pandoc.utils.stringify(k)
    local val = pandoc.utils.stringify(v)
    if key ~= "" and val ~= "" then t[key] = val end
  end
  return (next(t) and t) or nil
end

local function load_abbr_from_meta(meta)
  if not meta then return nil end
  local dict = meta.abbr or (meta.metadata and meta.metadata.abbr)
  if dict and dict.t == "MetaMap" then
    return to_plain_map(dict)
  elseif type(dict) == "table" then
    return to_plain_map(dict)
  end
  return nil
end

-- Kod / link / matematik vb. içine girmeyelim
local skip = {
  Code = true, CodeBlock = true, Math = true, Link = true, Image = true,
  RawInline = true, RawBlock = true
}

-- Tek bir Str içinde: en uzun anahtardan kısaya düz "plain find" ile sar
-- NOT: Tek başına parantez içindeki kısaltmayı (örn. "(ATK)") SARMAYIN.
local function wrap_keys_in_str(s)
  if not ABBR then return { pandoc.Str(s) } end

  -- anahtarları uzunluktan kısaya sırala
  local keys = {}
  for k, _ in pairs(ABBR) do table.insert(keys, k) end
  table.sort(keys, function(a, b) return #a > #b end)

  local out, i, n = {}, 1, #s
  while i <= n do
    local matched = false

    -- 0) (KEY) formu: olduğu gibi bırak
    if s:sub(i,i) == "(" then
      for _, key in ipairs(keys) do
        local klen = #key
        if (i + klen + 1) <= n
           and s:sub(i+1, i+klen) == key
           and s:sub(i+klen+1, i+klen+1) == ")"
        then
          table.insert(out, pandoc.Str(s:sub(i, i+klen+1)))  -- "(KEY)" aynen yaz
          i = i + klen + 2
          matched = true
          break
        end
      end
    end

    if not matched then
      -- 1) Düz KEY formu: sar
      for _, key in ipairs(keys) do
        local s1, e1 = s:find(key, i, true)  -- regex değil, düz arama
        if s1 == i then
          local title = ABBR[key]
          table.insert(out, pandoc.RawInline(
            "html",
            string.format(
              '<abbr data-title="%s" tabindex="0" role="note" aria-label="%s">%s</abbr>',
              title, title, key
            )
          ))
          i = e1 + 1
          matched = true
          break
        end
      end
    end

    if not matched then
      -- bir UTF-8 karakter ilerle
      local nxt = utf8.offset(s, 2, i)
      local j = nxt and (nxt - 1) or n
      table.insert(out, pandoc.Str(s:sub(i, j)))
      i = j + 1
    end
  end
  return out
end

local function process_inlines(inlines)
  if not ABBR then return inlines end
  local result = pandoc.List()
  for _, el in ipairs(inlines) do
    if el.t == "Str" then
      result:extend(wrap_keys_in_str(el.text))

    elseif el.t == "Span" then
      -- önceden etiketlediğin rozet/özel span’lere dokunma
      result:insert(el)

    else
      if el.content and not skip[el.t] then
        el.content = process_inlines(el.content)
      end
      result:insert(el)
    end
  end
  return result
end

-- -- Ana dönüştürme: Header'ları es geç -------------------------------------

local function transform_block(blk)
  if blk.t == "Header" then
    -- Başlıklarda abbr uygulanmasın
    return blk
  else
    -- Diğer bloklarda inline’ları işle
    return blk:walk({
      Inlines = function(inlines) return process_inlines(inlines) end
    })
  end
end

function M.Pandoc(doc)
  ABBR = load_abbr_from_meta(doc.meta)
  if not ABBR then return doc end

  for i, blk in ipairs(doc.blocks) do
    doc.blocks[i] = transform_block(blk)
  end
  return doc
end

return M

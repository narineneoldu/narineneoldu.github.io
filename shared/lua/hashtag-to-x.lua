-- hashtag-to-x.lua
-- Metin içinde #Hashtag geçen yerleri X (Twitter) arama linkine çevirir.
-- Türkçe karakterleri destekler, kod/link içindekilere dokunmaz.

local List = require 'pandoc.List'

-- X arama URL'sini üret
local function build_x_url(tagtext)
  local q = "%23" .. tagtext  -- URL encoded '#'
  return "https://x.com/search?q=" .. q .. "&src=typed_query&f=live"
end

-- Bir Str içindeki hashtag'leri Link node'larına parçalayarak dön
local function expand_hashtags_in_str(strtext)
  local out = List:new()

  -- Lua pattern açıklaması:
  -- (.-)           : hashtag'den önce gelen her şey (en kısa eşleşme)
  -- (#([...]+))    : hashtag'in tamamı (# ile birlikte)
  -- ()             : eşleşmenin bittiği index + 1 (Lua capture olarak)
  --
  -- Burada Türkçe karakterleri de dahil ediyoruz:
  --   %w  -> [A-Za-z0-9_]
  --   çğıİöşüÇĞİÖŞÜ  -> manuel ekledik
  local pattern = "(.-)(#([%wçğıİöşüÇĞİÖŞÜ_]+))()"

  local last_i = 1

  for prefix, fullhash, tagbody, next_i in string.gmatch(strtext, pattern) do
    -- prefix: hashtag'ten önceki düz metin
    if #prefix > 0 then
      out:insert(pandoc.Str(prefix))
    end

    -- fullhash: "#NarinveAilesiİçinAdalet"
    -- tagbody : "NarinveAilesiİçinAdalet"
    local url = build_x_url(tagbody)

    local link_node = pandoc.Link(
      { pandoc.Str(fullhash) },
      url,
      "",
      {
        target = "_blank",
        rel    = "noopener",
        class  = "hashtag-link"
      }
    )
    out:insert(link_node)

    -- next_i: Lua capture (string index + 1) ama string olarak geliyor.
    -- tonumber ile sayıya çeviriyoruz ki kalan kuyruğu doğru alalım.
    last_i = tonumber(next_i)
  end

  -- döngü bittikten sonra hashtag'ten sonra kalan kuyruk metni ekle
  if last_i <= #strtext then
    local tail = strtext:sub(last_i)
    if #tail > 0 then
      out:insert(pandoc.Str(tail))
    end
  end

  return out
end

-- Inline listesini dolaş
local function process_inlines(inlines)
  local out = List:new()

  for _, el in ipairs(inlines) do
    if el.t == "Link" or el.t == "Code" or el.t == "CodeSpan" then
      -- Zaten link / kod ise, olduğu gibi bırak
      out:insert(el)

    elseif el.t == "Str" then
      -- Bu Str içinde bir veya birden fazla hashtag olabilir
      local expanded = expand_hashtags_in_str(el.text or "")
      for _, sub in ipairs(expanded) do
        out:insert(sub)
      end

    elseif el.t == "Span" then
      -- Span içeriğini de işle (stilli metinlerde de hashtags çalışsın)
      local new_content = process_inlines(el.content)
      out:insert(pandoc.Span(new_content, el.attr))

    elseif el.t == "Quoted" then
      -- Alıntı içindeki inline'ları da işle
      local new_q = process_inlines(el.content)
      out:insert(pandoc.Quoted(el.quotetype, new_q))

    else
      -- Emph, Strong, Space, SoftBreak vs.
      out:insert(el)
    end
  end

  return out
end

-- Para ve Plain bloklarını dönüştür
local function handle_block(block)
  if block.t == "Para" then
    return pandoc.Para(process_inlines(block.content))
  elseif block.t == "Plain" then
    return pandoc.Plain(process_inlines(block.content))
  end
  return nil
end

return {
  {
    Para  = handle_block,
    Plain = handle_block
  }
}

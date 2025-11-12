-- ../shared/lua/hashtag_to_x.lua
-- Metin içinde #Hashtag geçen yerleri X (Twitter) arama linkine çevirir.
-- Türkçe karakterleri destekler, kod/link içindekilere dokunmaz.
-- NOT: "#2" gibi sayıyla başlayan ifadeleri linke çevirmez.

local M = {}

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
  -- (.-)              : hashtag'den önce gelen her şey (en kısa eşleşme)
  -- (#([%wçğıİöşüÇĞİÖŞÜ_]+)) : hashtag'in tamamı (# ile birlikte),
  --                            2. capture sadece '#' sonrası gövde
  -- ()                : eşleşmenin bittiği index + 1
  --
  -- %w -> [A-Za-z0-9_]
  -- Sonra Türkçe karakterleri manuel ekledik.
  local pattern = "(.-)(#([%wçğıİöşüÇĞİÖŞÜ_]+))()"

  local last_i = 1

  for prefix, fullhash, tagbody, next_i in string.gmatch(strtext, pattern) do
    -- prefix: hashtag'ten önceki düz metin
    if #prefix > 0 then
      out:insert(pandoc.Str(prefix))
    end

    -- Eğer tagbody sayı ile başlıyorsa (#2, #123, #2025vs), link yapma.
    if tagbody:match("^%d") then
      out:insert(pandoc.Str(fullhash))
    else
      -- normal hashtag -> link
      local url = build_x_url(tagbody)

      local attrs = pandoc.Attr(
        "",                              -- id yok
        { "hashtag-link" },              -- class listesi
        {                                -- key-value çiftleri (sıra korunur)
          { "target", "_blank" },
          { "rel", "noopener" }
        }
      )

      local link_node = pandoc.Link(
        { pandoc.Str(fullhash) },
        url,
        "",
        attrs
      )
      out:insert(link_node)
    end

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

M.Para  = handle_block
M.Plain = handle_block

return M

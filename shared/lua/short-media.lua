-- short-media.lua
-- Kullanım:
--   audio(audio/salim-1-16K.mp3)[Salim Güran’ın ses <a href="...">kaydı</a> <sup>[1]</sup>]

local BASE_PATH = "../../../../resources/"

-------------------------------------------------
-- Yardımcılar
-------------------------------------------------

-- baştaki/sondaki whitespace'i sil
local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Inline -> HTML string (bizim serializer)
local function render_inlines(inlines)
  local out = {}

  local function render_inline(inl)
    if inl.t == "Str" then
      table.insert(out, inl.text)

    elseif inl.t == "Space" then
      table.insert(out, " ")

    elseif inl.t == "SoftBreak" or inl.t == "LineBreak" then
      table.insert(out, " ")

    elseif inl.t == "RawInline" and inl.format == "html" then
      -- kullanıcının yazdığı ham HTML'i olduğu gibi koy
      table.insert(out, inl.text)

    elseif inl.t == "Superscript" then
      -- Superscript içerdiği inline'ları tekrar işleyelim
      table.insert(out, "<sup>")
      render_inlines(inl.c)  -- recursive çağrı
      table.insert(out, "</sup>")

    elseif inl.t == "Link" then
      -- Link'in içindeki metni al
      local linkTextInlines = inl.content
      local href = inl.target and inl.target[1] or "#"

      -- rel, target vb. korumak istersek buraya ekleyebiliriz.
      -- target="_blank" kullanıcı RawInline ile yazıyorsa zaten kalır,
      -- ama otomatik de ekleyebiliriz. Şimdilik ekleyelim.
      table.insert(out, '<a href="' .. href .. '" target="_blank">')
      render_inlines(linkTextInlines)
      table.insert(out, "</a>")

    else
      -- fallback: stringify et
      table.insert(out, pandoc.utils.stringify(inl))
    end
  end

  for i = 1, #inlines do
    render_inline(inlines[i])
  end

  return table.concat(out, "")
end

-- Bir paragrafın tüm inline'larını tek stringe ama HTML'i kaçırmadan çevir
local function para_inlines_to_html(inlines)
  return render_inlines(inlines)
end

-------------------------------------------------
-- Asıl filtre
-------------------------------------------------

function Para(el)
  -- Paragraf içeriğini (inline ağaç) "ham gibi" render et
  local raw_full = para_inlines_to_html(el.content)

  -- baş/son boşlukları at
  local raw = trim(raw_full)

  -- Şu pattern'i yakalıyoruz:
  --   audio(src)[caption]
  --   video(src)[caption]
  local media_type, media_src, caption_html =
    raw:match("^(%a+)%(([^%)]-)%)%[(.-)%]$")

  if not media_type then
    return nil
  end

  if media_type ~= "audio" and media_type ~= "video" then
    return nil
  end

  local full_src = BASE_PATH .. media_src

  local media_tag
  if media_type == "audio" then
    media_tag = string.format([[
<audio class="js-player" controls>
  <source src="%s" type="audio/mpeg">
</audio>]], full_src)
  else
    media_tag = string.format([[
<video class="js-player" controls playsinline>
  <source src="%s" type="video/mp4">
</video>]], full_src)
  end

  local final_html = string.format([[
<div class="audio-block">
  %s
  <p class="audio-caption">%s</p>
</div>]], media_tag, caption_html)

  return pandoc.RawBlock("html", final_html)
end

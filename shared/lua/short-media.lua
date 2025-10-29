-- short-media.lua
-- Kullanım .qmd içinde:
--   audio(audio/salim-1-16K.mp3)[Salim Güran’ın ses <a href="...">kaydı</a> <sup>[1]</sup>]
--   video(video/foo.mp4)[...]
--
-- Çıktı:
--   <div class="audio-block">
--     <audio class="js-player" controls data-caption-src="...vtt">
--       <source src="...mp3" type="audio/mpeg">
--       <track kind="captions" srclang="tr" label="Transcript" src="...vtt" default>
--     </audio>
--     <p class="audio-caption">...</p>
--   </div>

local BASE_PATH = "../../../../resources/"

-------------------------------------------------
-- Helpers
-------------------------------------------------

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- inline -> HTML string, HTML taglerini kaybetmeden
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
      table.insert(out, inl.text)

    elseif inl.t == "Superscript" then
      table.insert(out, "<sup>")
      -- recurse children of Superscript
      table.insert(out, render_inlines(inl.c))
      table.insert(out, "</sup>")

    elseif inl.t == "Link" then
      local href = inl.target and inl.target[1] or "#"
      table.insert(out, '<a href="' .. href .. '" target="_blank">')
      table.insert(out, render_inlines(inl.content))
      table.insert(out, "</a>")

    else
      -- fallback: stringify node
      table.insert(out, pandoc.utils.stringify(inl))
    end
  end

  for i = 1, #inlines do
    render_inline(inlines[i])
  end

  return table.concat(out, "")
end

local function para_inlines_to_html(inlines)
  return render_inlines(inlines)
end

-- site-lang'i _quarto.yml metadata'sından al
local function get_site_lang()
  local lang = "tr"
  if quarto
    and quarto.doc
    and quarto.doc.metadata
    and quarto.doc.metadata["site-lang"]
  then
    lang = pandoc.utils.stringify(quarto.doc.metadata["site-lang"])
  end
  if lang == nil or lang == "" then
    lang = "tr"
  end
  return lang
end

-- verilen "audio/salim-1-16K.mp3" için
--   base_full = "../../../../resources/audio/salim-1-16K.mp3"
--   captions_full = "../../../../resources/audio/salim-1-16K-<lang>.vtt"
local function build_paths(src_rel, site_lang)
  -- mp3/mp4 tam yolu (BASE_PATH + relative)
  local media_full = BASE_PATH .. src_rel

  -- dosya adı değiştirilmiş .vtt yolu
  -- sadece son .mp3 veya .mp4 uzantısını yakalayıp -<lang>.vtt ile değişiyoruz
  local vtt_rel = src_rel
    :gsub("%.mp3$", "-" .. site_lang .. ".vtt")
    :gsub("%.m4a$", "-" .. site_lang .. ".vtt")
    :gsub("%.wav$", "-" .. site_lang .. ".vtt")
    :gsub("%.ogg$", "-" .. site_lang .. ".vtt")
    :gsub("%.mp4$", "-" .. site_lang .. ".vtt")
    :gsub("%.m4v$", "-" .. site_lang .. ".vtt")
    :gsub("%.webm$", "-" .. site_lang .. ".vtt")

  local vtt_full = BASE_PATH .. vtt_rel

  return media_full, vtt_full
end

-------------------------------------------------
-- Filter
-------------------------------------------------

function Para(el)
  -- Paragraf içeriğini HTML-benzeri stringe çevir
  local raw_full = para_inlines_to_html(el.content)
  local raw = trim(raw_full)

  -- Şunu eşle:
  --   audio(path/to/file.mp3)[CAPTION...]
  --   video(path/to/file.mp4)[CAPTION...]
  local media_type, media_src, caption_html =
    raw:match("^(%a+)%(([^%)]-)%)%[(.+)%]$")

  if not media_type then
    return nil
  end

  media_type = trim(media_type)
  media_src = trim(media_src)
  caption_html = trim(caption_html)

  if media_type ~= "audio" and media_type ~= "video" then
    return nil
  end

  -- dil
  local site_lang = get_site_lang()

  -- tam yolları hazırla
  local media_full, vtt_full = build_paths(media_src, site_lang)

  local media_tag

  if media_type == "audio" then
    -- <audio> + <track> + data-caption-src
    media_tag = string.format([[
<audio class="js-player" controls data-caption-src="%s">
  <source src="%s" type="audio/mpeg">
  <track kind="captions"
         label="Transcript"
         srclang="%s"
         src="%s">
</audio>]], vtt_full, media_full, site_lang, vtt_full)

  else
    -- video tarafı (ilerisi için)
    media_tag = string.format([[
<video class="js-player" controls playsinline data-caption-src="%s">
  <source src="%s" type="video/mp4">
  <track kind="captions"
         label="Transcript"
         srclang="%s"
         src="%s">
</video>]], vtt_full, media_full, site_lang, vtt_full)

  end

  local final_html = string.format([[
<div class="audio-block">
  %s
  <p class="audio-caption">%s</p>
</div>]], media_tag, caption_html)

  return pandoc.RawBlock("html", final_html)
end

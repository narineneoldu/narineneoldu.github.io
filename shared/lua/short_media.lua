-- ../shared/lua/short_media.lua
-- Kullanım .qmd içinde:
--   audio(audio/salim-1-16K.mp3)[Salim Güran’ın ses <a href="...">kaydı</a> <sup>[1]</sup>]
--   video(video/foo.mp4)[...]
--   yt_video("LAe1zoOdF1c")[YouTube videosu açıklaması]
--
-- Üretilen HTML yapısı:
--   <div class="media-block">
--     <audio class="js-player" controls data-caption-src="...vtt" crossorigin="anonymous">
--       <source src="...mp3" type="audio/mpeg">
--       <track kind="subtitles"
--              srclang="tr"
--              label="Transcript"
--              src="...vtt"
--              crossorigin="anonymous">
--     </audio>
--     <p class="media-caption">...</p>
--   </div>
--
--   yt_video için:
--   <div class="media-block media-block-yt">
--     <div class="js-player"
--          data-plyr-provider="youtube"
--          data-plyr-embed-id="LAe1zoOdF1c"></div>
--     <p class="media-caption">...</p>
--   </div>

local M = {}

local BASE_PATH = "../../../../resources/"

-------------------------------------------------
-- Helpers
-------------------------------------------------

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- inline -> HTML string, inline HTML'i bozmadan
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
      table.insert(out, render_inlines(inl.c)) -- recurse
      table.insert(out, "</sup>")

    elseif inl.t == "Link" then
      local href = inl.target and inl.target[1] or "#"
      table.insert(out, '<a href="' .. href .. '" target="_blank">')
      table.insert(out, render_inlines(inl.content))
      table.insert(out, "</a>")

    else
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

-- _quarto.yml içinden site-lang çek
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

-- "audio/salim-1-16K.mp3" ->
--   media_full: "../../../../resources/audio/salim-1-16K.mp3"
--   vtt_full:   "../../../../resources/audio/salim-1-16K-<lang>.vtt"
local function build_paths(src_rel, site_lang)
  local media_full = BASE_PATH .. src_rel

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

function M.Para(el)
  local raw_full = para_inlines_to_html(el.content)
  local raw = trim(raw_full)

  -- pattern:
  --   audio(path/to/file.mp3)[CAPTION...]
  --   video(path/to/file.mp4)[CAPTION...]
  --   yt_video(ID)[CAPTION...]  -- CAPTION kısmı opsiyonel
  local media_type, media_src, caption_html =
    raw:match("^([%w_]+)%(([^%)]-)%)%[(.*)%]$")

  -- Eğer köşeli parantez yoksa: audio(path/to/file.mp3)
  if not media_type then
    media_type, media_src = raw:match("^([%w_]+)%(([^%)]-)%)$")
    caption_html = nil
  end

  if not media_type then
    return nil
  end

  media_type = trim(media_type)
  media_src  = trim(media_src)

  if caption_html ~= nil then
    caption_html = trim(caption_html)
    if caption_html == "" then
      caption_html = nil
    end
  end

  -- Strip optional "..." or '...' around source (useful for yt_video("ID"))
  media_src = media_src:gsub('^"(.-)"$', '%1')
  media_src = media_src:gsub("^'(.-)'$", "%1")

  if media_type ~= "audio" and media_type ~= "video" and media_type ~= "yt_video" then
    return nil
  end

  -- Special case: YouTube video via yt_video(ID)[caption]
  if media_type == "yt_video" then
    local embed_id = media_src

    local media_tag = string.format([[
<div class="js-player"
     data-plyr-provider="youtube"
     data-plyr-embed-id="%s"></div>]], embed_id)

    local caption_block = ""
    if caption_html then
      caption_block = string.format('\n  <p class="media-caption">%s</p>', caption_html)
    end

    local final_html = string.format([[
<div class="media-block media-block-yt">
  %s%s
</div>]], media_tag, caption_block)

    return pandoc.RawBlock("html", final_html)
  end

  local site_lang = get_site_lang()
  local media_full, vtt_full = build_paths(media_src, site_lang)

  local media_tag

  if media_type == "audio" then
    media_tag = string.format([[
<audio class="js-player" controls data-caption-src="%s" crossorigin="anonymous">
  <source src="%s" type="audio/mpeg">
  <track kind="subtitles"
         label="Transcript"
         srclang="%s"
         src="%s"
         crossorigin="anonymous">
</audio>]], vtt_full, media_full, site_lang, vtt_full)

  else
    media_tag = string.format([[
<video class="js-player" controls playsinline data-caption-src="%s" crossorigin="anonymous">
  <source src="%s" type="video/mp4">
  <track kind="subtitles"
         label="Transcript"
         srclang="%s"
         src="%s"
         crossorigin="anonymous">
</video>]], vtt_full, media_full, site_lang, vtt_full)
  end

  local caption_block = ""
  if caption_html then
    caption_block = string.format('\n  <p class="media-caption">%s</p>', caption_html)
  end

  local final_html = string.format([[
<div class="media-block">
  %s%s
</div>]], media_tag, caption_block)

  return pandoc.RawBlock("html", final_html)
end

return M

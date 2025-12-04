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

-- Parse argument list inside media shortcode, e.g.
--   yt_video("ID", start=10, autoplay=1, cclang="tr")
-- Returns table:
--   args["_id"] = "ID"
--   args["start"] = "10", ...
local function parse_media_args(str)
  local args = {}
  if not str or str == "" then
    return args
  end
  for part in string.gmatch(str, '([^,]+)') do
    part = trim(part)
    local k, v = part:match('^(%w+)%s*=%s*(.+)$')
    if k and v then
      v = trim(v)
      v = v:gsub('^"(.-)"$', '%1')
      v = v:gsub("^'(.-)'$", "%1")
      args[k] = v
    else
      part = part:gsub('^"(.-)"$', '%1')
      part = part:gsub("^'(.-)'$", "%1")
      if not args["_id"] then
        args["_id"] = part
      end
    end
  end

  return args
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

    elseif inl.t == "Emph" or inl.t == "Strong" or inl.t == "SmallCaps"
        or inl.t == "Strikeout" or inl.t == "Subscript" or inl.t == "Superscript" then
      for _, c in ipairs(inl.c) do
        render_inline(c)
      end

    elseif inl.t == "Link" then
      local href = inl.target
      local inner = {}
      for _, c in ipairs(inl.c) do
        if c.t == "Str" then
          table.insert(inner, c.text)
        elseif c.t == "Space" then
          table.insert(inner, " ")
        elseif c.t == "RawInline" and c.format == "html" then
          table.insert(inner, c.text)
        else
          -- fallback: convert to plain text
          table.insert(inner, pandoc.utils.stringify(c))
        end
      end
      table.insert(out, string.format('<a href="%s">%s</a>', href, table.concat(inner)))

    else
      -- fallback for any inline: stringify
      table.insert(out, pandoc.utils.stringify(inl))
    end
  end

  for _, inl in ipairs(inlines) do
    render_inline(inl)
  end

  return table.concat(out)
end

-- Para içindeki inlineları HTML string'e dönüştür
local function para_inlines_to_html(inlines)
  return render_inlines(inlines)
end

-- Site dilini al (varsayılan: "tr")
local function get_site_lang()
  if PANDOC_STATE and PANDOC_STATE.meta
     and PANDOC_STATE.meta["lang"]
     and PANDOC_STATE.meta["lang"].t == "MetaString"
  then
    return PANDOC_STATE.meta["lang"].text
  end
  return "tr"
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

local function strip_simple_quotes(s)
  if not s then return nil end
  s = trim(s)
  -- Only strip plain ASCII quotes; smart quotes will be handled on JS side
  s = s:gsub('^"(.-)"$', '%1')
  s = s:gsub("^'(.-)'$", "%1")
  return trim(s)
end

local function clean_jump_arg(s)
  if not s then return nil end
  s = trim(s)
  -- Remove ASCII quotes and Unicode smart quotes everywhere
  -- “ ” ‘ ’ ve " ' karakterlerini sil
  s = s:gsub('[\"\'“”‘’]', '')
  return trim(s)
end

-------------------------------------------------
-- Filter
-------------------------------------------------

-- Ortak block parser: hem Para hem Plain bunu kullanacak
local function handle_media_block(el)
  local raw_full = para_inlines_to_html(el.content)
  local raw = trim(raw_full)

  -- 0) Özel case: yt_jump(player, time, label)
  do
    local inside = raw:match('^yt_jump%((.*)%)$')
    if inside then
      -- 3 argümanı virgüllere göre ayır
      local a1, a2, a3 = inside:match('^(.-)%s*,%s*(.-)%s*,%s*(.-)$')
      if a1 and a2 and a3 then
        -- player id için sadece basit tırnakları uçtan temizleyelim
        local player = strip_simple_quotes(a1)
        -- time ve label için tüm ASCII + smart tırnakları sil
        local time   = clean_jump_arg(a2)
        local label  = clean_jump_arg(a3)

        if player and player ~= "" then
          -- Para mı Plain mi? Plain genelde liste item içi, Para normal paragraf
          local inner = string.format(
            '<a href="#%s&t=%s" class="timejump" data-player="%s" data-time="%s">[%s] %s</a>',
            player, time, player, time, time, label
          )

          local html
          if el.t == "Plain" then
            -- Liste içinde: <li><a ...>...</a></li>
            html = inner
          else
            -- Normal paragraf: <p><a ...>...</a></p>
            html = '<p>' .. inner .. '</p>'
          end

          return pandoc.RawBlock("html", html)
        end
      end
    end
  end

  -- pattern:
  --   audio(path/to/file.mp3)[CAPTION...]
  --   video(path/to/file.mp4)[CAPTION...]
  --   yt_video("ID", start=..., ...)[CAPTION...]  -- CAPTION optional
  local media_type, media_src, caption_html =
    raw:match("^([%w_]+)%(([^%)]-)%)%[(.*)%]$")

  -- If caption ([]) is omitted, e.g. audio(path/to/file.mp3)
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

  if media_type ~= "audio" and media_type ~= "video" and media_type ~= "yt_video" then
    return nil
  end

  -- Special case: YouTube video via yt_video(...)
  if media_type == "yt_video" then
    local args = parse_media_args(media_src)

    -- Normalize embed_id (strip optional quotes)
    local embed_id = args["_id"] or media_src
    embed_id = embed_id:gsub('^"(.-)"$', '%1')
    embed_id = embed_id:gsub("^'(.-)'$", "%1")

    -- DOM id: explicit id=... varsa onu kullan, yoksa embed_id
    local dom_id = args["id"] or embed_id

    local lines = {}
    table.insert(lines, '<div class="media-block media-block-yt">')
    table.insert(lines, '<div class="js-player"')
    table.insert(lines, '     id="' .. dom_id .. '"')
    table.insert(lines, '     data-plyr-provider="youtube"')
    table.insert(lines, '     data-plyr-embed-id="' .. embed_id .. '"')

    local function add_attr(key, attr)
      if args[key] then
        table.insert(lines, '     ' .. attr .. '="' .. args[key] .. '"')
      end
    end

    -- Generic playback attributes
    add_attr("start",       "data-start")
    add_attr("autoplay",    "data-autoplay")
    add_attr("loop",        "data-loop")
    add_attr("playsinline", "data-playsinline")

    -- Caption behaviour (priority: nocc > cc > cclang)
    if args["nocc"] == "1" or args["nocc"] == "true" then
      table.insert(lines, '     data-cc-force="off"')
    elseif args["cc"] == "1" or args["cc"] == "true" then
      table.insert(lines, '     data-cc-force="on"')
    elseif args["cclang"] then
      table.insert(lines, '     data-cc-lang="' .. args["cclang"] .. '"')
    end

    table.insert(lines, '></div>')

    if caption_html then
      table.insert(lines, '  <p class="media-caption">' .. caption_html .. '</p>')
    end

    table.insert(lines, '</div>')

    local final_html = table.concat(lines, "\n")
    return pandoc.RawBlock("html", final_html)
  end

  -- audio / video shortcodes (local files) keep existing behaviour
  -- Strip optional quotes around source path
  media_src = media_src:gsub('^"(.-)"$', '%1')
  media_src = media_src:gsub("^'(.-)'$", "%1")

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

-- Asıl filter girişleri: Para ve Plain
function M.Para(el)
  return handle_media_block(el)
end

function M.Plain(el)
  return handle_media_block(el)
end

return M

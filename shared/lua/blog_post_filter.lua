-- ../shared/lua/blog_post_filter.lua
-- This filter builds only the TOP META BLOCK:
--   AUTHOR / LAST UPDATED / SOURCE

local meta_author      = nil
local meta_author_url  = nil
local meta_date        = nil
local meta_source      = nil
local norm_source      = nil
local site_lang        = "tr"   -- default language

-- reading-time meta
local meta_rt_estimate   = nil   -- "≈ 11 min"
local meta_rt_words      = nil   -- e.g. "1071"
local meta_rt_syllables  = nil   -- e.g. "3159"

----------------------------------------------------------
-- Helper: normalize URL by removing query/fragment
----------------------------------------------------------
local function normalize_url(u)
  if not u then return nil end
  if not string.match(u, "^https?://") then
    return nil
  end
  u = u:gsub("[?#].*$", "")
  return u
end

----------------------------------------------------------
-- Helper: meta label span
----------------------------------------------------------
local function metaLabel(txt)
  return pandoc.Span({ pandoc.Str(txt) }, pandoc.Attr("", {"meta-label"}))
end

----------------------------------------------------------
-- Helper: raw HTML link for the source
----------------------------------------------------------
local function source_html_link(href, text)
  return string.format(
    '<a href="%s" target="_blank" rel="noopener">%s</a>',
    href,
    text
  )
end

----------------------------------------------------------
-- META: Extract page-level metadata
----------------------------------------------------------
function Meta(meta)
  -- Extract language (site-level)
  if meta.lang then
    site_lang = pandoc.utils.stringify(meta.lang)
  end

  -- Extract author
  if meta.author then
    if type(meta.author) == "table" and meta.author[1] and meta.author[1].name then
      meta_author = meta.author[1].name
    elseif type(meta.author) == "table" and meta.author[1] and type(meta.author[1]) == "string" then
      meta_author = meta.author[1]
    else
      meta_author = pandoc.utils.stringify(meta.author)
    end
  end

  -- Extract date
  if meta.date then
    meta_date = pandoc.utils.stringify(meta.date)
  end

  -- Extract source
  if meta.source then
    meta_source = pandoc.utils.stringify(meta.source)
    norm_source = normalize_url(meta_source)
  end

  -- Extract reading-time metadata (set by reading_time.lua)
  if meta["reading-time-estimate"] then
    meta_rt_estimate = pandoc.utils.stringify(meta["reading-time-estimate"])
  end
  if meta["reading-time-words"] then
    meta_rt_words = pandoc.utils.stringify(meta["reading-time-words"])
  end
  if meta["reading-time-syllables"] then
    meta_rt_syllables = pandoc.utils.stringify(meta["reading-time-syllables"])
  end
end

----------------------------------------------------------
-- MAIN: Build top meta row only
----------------------------------------------------------
function Pandoc(doc)

  ------------------------------------------------------
  -- Language-dependent constant labels
  ------------------------------------------------------
  local LABEL_AUTHOR
  local LABEL_DATE
  local LABEL_SOURCE
  local LABEL_READING_TIME
  local LABEL_WORD_COUNT
  local SOURCE_LINK_TEXT

  if site_lang == "en" then
    LABEL_AUTHOR       = "AUTHOR"
    LABEL_DATE         = "LAST UPDATED"
    LABEL_SOURCE       = "SOURCE"
    LABEL_READING_TIME = "READING TIME"
    LABEL_WORD_COUNT    = "WORD COUNT"
    SOURCE_LINK_TEXT   = "Original Source"
  else
    LABEL_AUTHOR       = "YAZAR"
    LABEL_DATE         = "GÜNCELLEME TARİHİ"
    LABEL_SOURCE       = "KAYNAK"
    LABEL_READING_TIME = "OKUMA SÜRESİ"
    LABEL_WORD_COUNT    = "KELİME SAYISI"
    SOURCE_LINK_TEXT   = "Orijinal Kaynak"
  end

  ------------------------------------------------------
  -- Try to build a relative link to the author page
  ------------------------------------------------------
  meta_author_url = nil
  if quarto and quarto.doc and quarto.doc.input_file then
    local input_path = quarto.doc.input_file
    local post_dir = input_path:gsub("/index%.qmd$", "")
    local author_dir = post_dir:match("(.+)/[^/]+$")
    if author_dir then
      meta_author_url = "../"
    end
  end

  ------------------------------------------------------
  -- Build the top meta block (AUTHOR / DATE / SOURCE)
  ------------------------------------------------------
  local cols = {}

  -- AUTHOR
  if meta_author then
    local author_node
    if meta_author_url then
      author_node = pandoc.Link(meta_author, meta_author_url, "", {rel="author"})
    else
      author_node = pandoc.Str(meta_author)
    end

    table.insert(cols,
      pandoc.Div({
        metaLabel(LABEL_AUTHOR),
        pandoc.LineBreak(),
        author_node
      }, pandoc.Attr("", {"col-meta"}))
    )
  end

  -- DATE
  if meta_date then
    table.insert(cols,
      pandoc.Div({
        metaLabel(LABEL_DATE),
        pandoc.LineBreak(),
        pandoc.Str(meta_date)
      }, pandoc.Attr("", {"col-meta"}))
    )
  end

  -- READING TIME
  if meta_rt_estimate then
    -- Simple text like "≈ 11 min"
    table.insert(cols,
      pandoc.Div({
        metaLabel(LABEL_READING_TIME),
        pandoc.LineBreak(),
        pandoc.Str(meta_rt_estimate)
      }, pandoc.Attr("", {"col-meta"}))
    )
  end

  -- WORD COUNT
  if meta_rt_estimate then
    table.insert(cols,
      pandoc.Div({
        metaLabel(LABEL_WORD_COUNT),
        pandoc.LineBreak(),
        pandoc.Str(meta_rt_words)
      }, pandoc.Attr("", {"col-meta"}))
    )
  end

  -- SOURCE
  if meta_source then
    local html = source_html_link(meta_source, SOURCE_LINK_TEXT)
    local link = pandoc.RawInline("html", html)

    table.insert(cols,
      pandoc.Div({
        metaLabel(LABEL_SOURCE),
        pandoc.LineBreak(),
        link
      }, pandoc.Attr("", {"col-meta"}))
    )
  end

  ------------------------------------------------------
  -- Insert meta block at top of document
  ------------------------------------------------------
  if #cols > 0 then
    local wrapper = pandoc.Div(cols, pandoc.Attr("", {"top-meta-row"}))
    table.insert(doc.blocks, 1, wrapper)
  end

  return doc
end


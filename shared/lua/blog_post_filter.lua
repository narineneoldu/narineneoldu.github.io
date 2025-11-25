-- ../shared/lua/blog_post_filter.lua
-- This filter builds only the TOP META BLOCK:
--   AUTHOR / LAST UPDATED / SOURCE

local meta_author      = nil
local meta_author_url  = nil
local meta_date        = nil
local meta_source      = nil
local norm_source      = nil
local site_lang        = "tr"   -- default language
local is_author_page   = false

-- reading-time meta
local rt_text_from_yml = nil
local rt_words_from_yml = nil

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

  -- Detect author page
  if meta["is-author-page"] ~= nil then
    local v = pandoc.utils.stringify(meta["is-author-page"]):lower()
    if v == "true" or v == "yes" or v == "1" then
      is_author_page = true
    end
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
    -- LABEL_READING_TIME = "READING TIME"
    -- LABEL_WORD_COUNT    = "WORD COUNT"
    SOURCE_LINK_TEXT   = "Original Source"
  else
    LABEL_AUTHOR       = "YAZAR"
    LABEL_DATE         = "GÜNCELLEME TARİHİ"
    LABEL_SOURCE       = "KAYNAK"
    -- LABEL_READING_TIME = "OKUMA SÜRESİ"
    -- LABEL_WORD_COUNT    = "KELİME SAYISI"
    SOURCE_LINK_TEXT   = "Orijinal Kaynak"
  end

  -- Determine input file path (QMD file)
  local input_file = nil
  if quarto and quarto.doc and quarto.doc.input_file then
    input_file = quarto.doc.input_file
  end

  local rt_stats_path = nil
  if input_file then
    local base = input_file:match("([^/]+)%.qmd$")
    if base then
      rt_stats_path = input_file:gsub("([^/]+)%.qmd$", base .. "_reading_stats.yml")
    end
  end

  -- Read reading stats YAML if present
  if rt_stats_path then
    local f = io.open(rt_stats_path, "r")
    if f then
      local text = f:read("*all")
      f:close()

      -- Parse YAML via pandoc.read by wrapping as front matter
      local md = "---\n" .. text .. "\n---\n"
      local ok, doc_or_err = pcall(pandoc.read, md, "markdown")
      if ok then
        local meta = doc_or_err.meta or {}
        local rt = meta["reading"]
        if rt then
          -- label and words are MetaValues, use stringify
          if rt["text"] then
            rt_text_from_yml = pandoc.utils.stringify(rt["text"])
          end
          if rt["words"] then
            rt_words_from_yml = pandoc.utils.stringify(rt["words"])
          end
          if rt["label_reading_time"] then
            LABEL_READING_TIME = pandoc.utils.stringify(rt["label_reading_time"])
          end
          if rt["label_word_count"] then
            LABEL_WORD_COUNT = pandoc.utils.stringify(rt["label_word_count"])
          end
        end
      else
        -- Optional: log parse error
        -- io.stderr:write("Failed to parse reading_stats yaml: " .. tostring(doc_or_err) .. "\n")
      end
    end
  end

  ------------------------------------------------------
  -- Build the top meta block (AUTHOR / DATE / SOURCE)
  ------------------------------------------------------
  local cols = {}

  -- If this page is the author page itself, do not create author info
  if not is_author_page then
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
  end

  -- READING TIME (from YAML)
  if rt_text_from_yml then
    table.insert(cols,
      pandoc.Div({
        metaLabel(LABEL_READING_TIME),
        pandoc.LineBreak(),
        pandoc.Str(rt_text_from_yml)
      }, pandoc.Attr("", {"col-meta"}))
    )
  end

  -- WORD COUNT (from YAML)
  if rt_words_from_yml then
    table.insert(cols,
      pandoc.Div({
        metaLabel(LABEL_WORD_COUNT),
        pandoc.LineBreak(),
        pandoc.Str(rt_words_from_yml)
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


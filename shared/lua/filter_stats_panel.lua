-- ../shared/lua/filter_stats_panel.lua
-- Simple stats panel for trial posts:
--   shows only reading time and word count.

local site_lang         = "tr"   -- default language
local stats_enabled     = true   -- can be disabled per document

----------------------------------------------------------
-- META: Extract page-level metadata
----------------------------------------------------------
function Meta(meta)
  -- Read site language from meta.lang (comes from _quarto.yml: lang: tr)
  if meta.lang then
    site_lang = pandoc.utils.stringify(meta.lang)
  end

  -- Optional per-document toggle:
  -- stats-panel: false
  if meta["stats-panel"] ~= nil then
    local v = pandoc.utils.stringify(meta["stats-panel"]):lower()
    if v == "false" or v == "no" or v == "off" or v == "0" then
      stats_enabled = false
    end
  end
end

local function file_exists(path)
  local f = io.open(path, "r")
  if f ~= nil then
    f:close()
    return true
  else
    return false
  end
end

local function relative_path(path)
  local project_root = quarto.project.directory
  return path:gsub("^" .. project_root .. "/?", "/")
end

local get_doc_path = function()
  -- default relative = false
  relative = relative or false

  if quarto and quarto.doc and quarto.doc.input_file then
    local path = quarto.doc.input_file
    if relative then
      return relative_path()
    else
      return path
    end
  end
  return nil
end

----------------------------------------------------------
-- Helper: label span
----------------------------------------------------------
local function statsLabel(txt)
  return pandoc.Span({ pandoc.Str(txt) }, pandoc.Attr("", {"stats-label"}))
end

local function statsValue(txt)
  return pandoc.Span({ pandoc.Str(txt) }, pandoc.Attr("", {"stats-value"}))
end

----------------------------------------------------------
-- MAIN: Build stats panel (only in trial/)
----------------------------------------------------------
function Pandoc(doc)
  -- 1) If panel disabled in YAML, do nothing
  if not stats_enabled then
    return doc
  end

  -- 3) Language-dependent labels
  local LABEL_READING_TIME
  local LABEL_WORD_COUNT

  -- 2) Only run for files under trial/ directory
  local in_trial = false
  local doc_path = get_doc_path()
  if doc_path then
    -- Normalize Windows-style backslashes just in case
    doc_path2 = doc_path:gsub("\\", "/")
    -- Matches "trial/index.qmd" or ".../trial/..."
    if doc_path2:match("/test/") or doc_path2:match("/trial/") then
      in_trial = true
    end
  end

  if not in_trial then
    return doc
  end

  ------------------------------------------------------
  -- Determine input file path (QMD file)
  ------------------------------------------------------
  local rt_label_from_yml = nil
  local rt_words_from_yml = nil
  local rt_stats_path = nil

  if doc_path then
    local base = doc_path:match("([^/]+)%.qmd$")
    if base then
      rt_stats_path = doc_path:gsub("([^/]+)%.qmd$", base .. "_reading_stats.yml")
      path_words_file = doc_path:gsub("([^/]+)%.qmd$", base .. "_words.json")
    end
  end

  ------------------------------------------------------
  -- Read reading stats YAML if present
  ------------------------------------------------------
  if rt_stats_path then
    local f = io.open(rt_stats_path, "r")
    if f then
      local text = f:read("*all")
      f:close()

      local md = "---\n" .. text .. "\n---\n"
      local ok, doc_or_err = pcall(pandoc.read, md, "markdown")
      if ok then
        local meta = doc_or_err.meta or {}
        local rt = meta["reading"]
        if rt then
          if rt["text"] then
            rt_label_from_yml = pandoc.utils.stringify(rt["text"])
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
      end
    end
  end

  -- 4) Build panel columns
  local cols = {}

  -- Reading time column
  if rt_label_from_yml then
    table.insert(cols,
      pandoc.Div({
        statsLabel(LABEL_READING_TIME),
        statsValue(rt_label_from_yml)
      }, pandoc.Attr("", {"col-stats"}))
    )
  end

  -- Word count column
  if rt_words_from_yml then
    table.insert(cols,
      pandoc.Div({
        statsLabel(LABEL_WORD_COUNT),
        statsValue(rt_words_from_yml)
      }, pandoc.Attr("", {"col-stats"}))
    )
  end

  ------------------------------------------------------
  -- Combined column: WordCloud Button + Stats Button
  ------------------------------------------------------
  local third_col_inlines = {}

  -- WordCloud Button (optional)
  if file_exists(path_words_file) then
    path_words_file = relative_path(path_words_file)

    local wc_close = "Kapat"
    local wc_label = "Kelime Bulutu"
    local svg_path = string.format("/resources/icons/wordcloud_%s.svg", site_lang)
    if site_lang == "en" then
      path_words_file = "/en" .. path_words_file
      wc_label = "WordCloud"
      wc_close = "Close"
    end

local wc_button_html = string.format([[
<button class="btn btn-secondary d-flex align-items-center justify-content-center btn-stats-panel wc-trigger" data-json="%s">
  <img src="%s" alt="%s" width="60" height="45">
</button>
]], path_words_file, svg_path, wc_label)

    table.insert(third_col_inlines, pandoc.RawInline("html", wc_button_html))
  end

  -- Stats Button (always)
  local alert_msg
  local stats_label

  if site_lang == "en" then
    alert_msg  = "Not yet ready! :)"
    stats_label = "STATISTICS"
  else
    alert_msg  = "Henüz hazır değil! :)"
    stats_label = "İSTATİSTİK"
  end

  local stats_button_html = string.format([[
<button class="btn btn-primary d-flex align-items-center justify-content-center btn-stats-panel stats-btn" type="button" onclick="alert('%s')">
  <span class="stats-icon"></span>
</button>
]], alert_msg)

  table.insert(third_col_inlines, pandoc.RawInline("html", stats_button_html))

  -- Insert combined column if it has any content
  if #third_col_inlines > 0 then
    table.insert(cols,
      pandoc.Div(third_col_inlines, pandoc.Attr("", {"col-buttons"}))
    )
  end

  -- If nothing to show, exit quietly
  if #cols == 0 then
    return doc
  end

  -- 5) Wrap and inject at top of document
  local wrapper = pandoc.Div(cols, pandoc.Attr("", {"stats-panel"}))
  table.insert(doc.blocks, 1, wrapper)

  return doc
end

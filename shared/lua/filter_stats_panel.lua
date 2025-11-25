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
  if quarto and quarto.doc and quarto.doc.input_file then
    local path = quarto.doc.input_file
    -- Normalize Windows-style backslashes just in case
    path = path:gsub("\\", "/")
    -- Matches "trial/index.qmd" or ".../trial/..."
    if path:match("^trial/") or path:match("/trial/") then
      in_trial = true
    end
  end

  if not in_trial then
    return doc
  end

  ------------------------------------------------------
  -- Determine input file path (QMD file)
  ------------------------------------------------------
  local input_file = nil
  if quarto and quarto.doc and quarto.doc.input_file then
    input_file = quarto.doc.input_file
  end

  local rt_label_from_yml = nil
  local rt_words_from_yml = nil
  local rt_stats_path = nil

  if input_file then
    local base = input_file:match("([^/]+)%.qmd$")
    if base then
      rt_stats_path = input_file:gsub("([^/]+)%.qmd$", base .. "_reading_stats.yml")
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

  -- === THIRD COLUMN: Trend Button ===

  local alert_msg
  local button_label

  if site_lang == "en" then
    alert_msg    = "Not yet ready! :)"
    button_label = "STATISTICS"
  else
    alert_msg    = "Henüz hazır değil! :)"
    button_label = "İSTATİSTİK"
  end

  local button_html = string.format([[
  <button class="btn btn-primary w-100 d-flex align-items-center justify-content-center stats-btn" type="button" onclick="alert('%s')">
    <span class="stats-inner">
      <span class="stats-text">%s</span>
      <span class="stats-icon"></span>
    </span>
  </button>
  ]], alert_msg, button_label)

  table.insert(cols,
    pandoc.Div({
      pandoc.RawInline("html", button_html)
    }, pandoc.Attr("", {"col-stats", "col-trend"}))
  )

  -- If nothing to show, exit quietly
  if #cols == 0 then
    return doc
  end

  -- 5) Wrap and inject at top of document
  local wrapper = pandoc.Div(cols, pandoc.Attr("", {"stats-panel"}))
  table.insert(doc.blocks, 1, wrapper)

  return doc
end

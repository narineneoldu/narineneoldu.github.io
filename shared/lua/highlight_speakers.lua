-- ../shared/lua/highlight_speakers.lua (metadata driven, span_multi-style)

local utils = require 'pandoc.utils'
local List  = require 'pandoc.List'

----------------------------------------------------------------
-- GLOBAL STATE
-- Stores speaker groups, lookup tables, and a merged list of all names.
----------------------------------------------------------------

local groups      = {}
local nameToClass = {}
local ALL_NAMES   = {}

----------------------------------------------------------------
-- LOAD SPEAKERS FROM METADATA
-- Reads the `speakers:` table from document or project metadata
-- and populates groups, nameToClass, and ALL_NAMES.
-- Names are sorted by length (descending) to match longer names first.
----------------------------------------------------------------

local function load_speakers_from_meta(meta)
  groups      = {}
  nameToClass = {}
  ALL_NAMES   = {}

  if not meta then
    return
  end

  -- speakers may appear as:
  -- meta.speakers
  -- meta.metadata.speakers  (Quarto projects)
  local speakers_meta = meta.speakers or (meta.metadata and meta.metadata.speakers)

  if type(speakers_meta) ~= "table" then
    return
  end

  for cls, names_meta in pairs(speakers_meta) do
    local names = {}

    -- Multi-item MetaList
    if type(names_meta) == "table" and names_meta[1] ~= nil then
      for _, item in ipairs(names_meta) do
        local s = utils.stringify(item)
        if s ~= "" then
          table.insert(names, s)
        end
      end

    -- Single MetaString
    else
      local s = utils.stringify(names_meta)
      if s ~= "" then
        table.insert(names, s)
      end
    end

    -- Register names under their class
    if #names > 0 then
      groups[cls] = names
      for _, n in ipairs(names) do
        nameToClass[n] = cls
        table.insert(ALL_NAMES, n)
      end
    end
  end

  -- Sort longest names first to avoid partial matches
  table.sort(ALL_NAMES, function(a, b) return #a > #b end)
end

----------------------------------------------------------------
-- UTILITY HELPERS
-- The following helpers handle inline classification, stripping,
-- and text extraction from Pandoc inline arrays.
----------------------------------------------------------------

-- Returns true if a Span/Link has one of the given classes.
local function has_class(attr, targets)
  if not attr or not attr.classes then return false end
  for _, c in ipairs(attr.classes) do
    for __, t in ipairs(targets) do
      if c == t then return true end
    end
  end
  return false
end

-- Detects anchors inserted by line-anchor filters.
local function is_anchor_inline(el)
  if el.t == "Span" and has_class(el.attr, {"line-anchor","la-link","anchor"}) then
    return true
  end
  if el.t == "Link" and has_class(el.attr, {"line-anchor","la-link","anchor"}) then
    return true
  end
  if el.t == "RawInline" and el.format == "html" then
    local s = el.text or ""
    if s:match("[<]a%s+[^>]*class=[\"'][^\"']*line%-anchor") or
       s:match("[<]a%s+[^>]*class=[\"'][^\"']*la%-link") or
       s:match("[<]a%s+[^>]*class=[\"'][^\"']*anchor") then
      return true
    end
  end
  return false
end

-- Extracts anchor elements at the start of a block and returns (anchors, rest).
local function take_leading_anchors(inlines)
  local anchors = List()
  local rest = List(inlines)
  while #rest > 0 and is_anchor_inline(rest[1]) do
    anchors:insert(rest[1])
    rest:remove(1)
  end
  return anchors, rest
end

-- Checks whether speaker markup was already applied.
local function already_processed(inlines)
  for _, el in ipairs(inlines) do
    if el.t == "Span" and has_class(el.attr, {"speaker"}) then
      return true
    end
  end
  return false
end

-- Converts a list of inlines into a raw string representation.
local function stringify_inlines(inlines)
  return utils.stringify(pandoc.Inlines(inlines))
end

-- Counts leading whitespace characters in a string.
local function leading_space_len(s)
  local _, j = s:find("^%s*")
  return (j or 0)
end

-- Removes `n` characters worth of prefix from the inline sequence.
-- Used when stripping "Speaker Name:" from the beginning of a line.
local function drop_prefix_chars(inlines, n)
  if n <= 0 then return List(inlines) end
  local out = List()
  local i = 1

  while i <= #inlines do
    local el = inlines[i]
    local t  = el.t

    if n <= 0 then
      for j=i,#inlines do out:insert(inlines[j]) end
      break
    end

    if t == "Space" or t == "SoftBreak" or t == "LineBreak" then
      n = n - 1
      i = i + 1

    elseif t == "Str" then
      local txt = el.text or ""
      local L = #txt
      if n >= L then
        n = n - L
        i = i + 1
      else
        local rest = txt:sub(n+1)
        out:insert(pandoc.Str(rest))
        n = 0
        for j=i+1,#inlines do out:insert(inlines[j]) end
        break
      end

    else
      -- Other inline types count as a single prefix-consuming unit.
      if n > 0 then
        out:insert(el)
        for j=i+1,#inlines do out:insert(inlines[j]) end
        break
      end
    end
  end

  return out
end

----------------------------------------------------------------
-- MATCH A SPEAKER NAME AT LINE START
-- Attempts to match:
--   Speaker Name : text...
-- Returns (name, prefix_length) or nil.
----------------------------------------------------------------

local function match_name_and_prefix_len(rest_inlines)
  local txt = stringify_inlines(rest_inlines)
  if txt == "" then return nil end

  local ls = leading_space_len(txt)
  local tail = txt:sub(ls + 1)

  for _, name in ipairs(ALL_NAMES) do
    -- Escape non-word characters for pattern safety
    local pat = "^" .. name:gsub("(%W)","%%%1") .. "%s*:%s*(.*)$"
    local utter = tail:match(pat)
    if utter ~= nil then
      local consumed = #tail - #utter
      local total_prefix = ls + consumed
      return name, total_prefix
    end
  end

  return nil
end

----------------------------------------------------------------
-- BUILD THE NEW INLINE SEQUENCE (anchors + speaker span + utterance span)
----------------------------------------------------------------

local function build_output_inlines(anchors, speakerName, utter_inlines, cls)
  local out = List()

  -- Keep leading anchors exactly as-is
  for _, a in ipairs(anchors) do out:insert(a) end

  -- Insert <span class="speaker CLASS">Speaker :</span>
  local sp = pandoc.Span(
    { pandoc.Str(speakerName), pandoc.Space(), pandoc.Str(":") },
    pandoc.Attr("", {"speaker", cls or "speaker-unknown"})
  )
  out:insert(sp)
  out:insert(pandoc.Space())

  -- Insert utterance as <span class="utterance">...</span>
  local ut = pandoc.Span(utter_inlines, pandoc.Attr("", {"utterance"}))
  out:insert(ut)

  return out
end

----------------------------------------------------------------
-- BASIC CHECK WHETHER A LINE BEGINS WITH TEXT (not a header, list, etc.)
----------------------------------------------------------------

local function first_texty(inlines)
  local el = inlines[1]
  if not el then return false end
  if el.t == "Str" or el.t == "SoftBreak" or el.t == "Space" then return true end
  if el.t == "RawInline" and (el.format == "html" or el.format == "latex") then
    return true
  end
  return false
end

----------------------------------------------------------------
-- MAIN BLOCK TRANSFORMER
-- Attempts speaker matching on each Para/Plain block.
-- Applies speaker markup if match succeeds.
----------------------------------------------------------------

local function transform_block(blk)
  if blk.t ~= "Para" and blk.t ~= "Plain" then return nil end
  if already_processed(blk.content) then return nil end

  local anchors, rest = take_leading_anchors(blk.content)

  -- If nothing textual remains after anchors, restore anchors and stop.
  if #rest == 0 or not first_texty(rest) then
    if #anchors > 0 then
      local restored = List()
      for _, a in ipairs(anchors) do restored:insert(a) end
      for _, r in ipairs(rest)    do restored:insert(r) end
      blk.content = restored
    end
    return nil
  end

  local speakerName, prefix_chars = match_name_and_prefix_len(rest)
  if not speakerName then
    -- No match → restore anchors untouched
    if #anchors > 0 then
      local restored = List()
      for _, a in ipairs(anchors) do restored:insert(a) end
      for _, r in ipairs(rest)    do restored:insert(r) end
      blk.content = restored
    end
    return nil
  end

  -- Strip prefix ("Speaker Name:") from inline list
  local utter_inlines = drop_prefix_chars(rest, prefix_chars)

  -- Remove leading spaces inside utterance span
  while #utter_inlines > 0 do
    local t = utter_inlines[1].t
    if t == "Space" or t == "SoftBreak" or t == "LineBreak" then
      table.remove(utter_inlines, 1)
    else
      break
    end
  end

  local cls = nameToClass[speakerName] or "speaker-unknown"
  local new_inlines = build_output_inlines(anchors, speakerName, utter_inlines, cls)

  if blk.t == "Para" then
    return pandoc.Para(new_inlines)
  else
    return pandoc.Plain(new_inlines)
  end
end

----------------------------------------------------------------
-- MODULE (META + PANDOC ENTRY POINT)
----------------------------------------------------------------

local M = {}

function M.Meta(m)
  load_speakers_from_meta(m)
  return m
end

function M.Pandoc(doc)
  -- Skip processing for index.qmd (often contains no transcripts)
  local input = (quarto and quarto.doc and quarto.doc.input_file) or ""
  if type(input) == "string" and input ~= "" then
    local fname = input:match("([^/\\]+)$") or input
    if fname == "index.qmd" then
      -- io.stderr:write("highlight_speakers: skipping index.qmd\n")
      return doc
    end
  end

  local speakerFilter = {
    Para  = transform_block,
    Plain = transform_block,
  }

  return doc:walk(speakerFilter)
end

----------------------------------------------------------------
-- EXPORT
----------------------------------------------------------------

return {
  M
}

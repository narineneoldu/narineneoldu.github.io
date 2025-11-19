-- ../shared/lua/highlight_speakers.lua
-- Speaker highlighting based on `metadata.participant` (same variants as utils_participant.lua)
--
-- Uses the participant table to generate name variants (prefix/suffix, short name, UPPERCASE surname)
-- and then matches "Name :" at line start to wrap as:
--   <span class="speaker GROUP">Name :</span> <span class="utterance">...</span>

local utils = require 'pandoc.utils'
local List  = require 'pandoc.List'

----------------------------------------------------------------
-- GLOBAL STATE
----------------------------------------------------------------

-- groups is not strictly needed here, but kept for symmetry
local groups      = {}
local nameToClass = {}  -- variant -> group key (e.g. "victim", "suspect")
local ALL_NAMES   = {}  -- flat list of all variants, sorted by length desc

----------------------------------------------------------------
-- HELPERS (copied from utils_participant.lua style)
----------------------------------------------------------------

-- Trim and normalize internal whitespace to a single space.
local function normalize_spaces(s)
  s = s:gsub("%s+", " ")
  s = s:match("^%s*(.-)%s*$") or s
  return s
end

-- Turkish-aware uppercase helper for the surname part (used for variant forms).
local function to_upper_tr(s)
  -- crude but good enough for common Turkish characters
  s = s:gsub("i", "İ")
       :gsub("ı", "I")
       :gsub("ç", "Ç")
       :gsub("ğ", "Ğ")
       :gsub("ö", "Ö")
       :gsub("ş", "Ş")
       :gsub("ü", "Ü")
  return s:upper()
end

-- Capitalize first character in a UTF-8 safe way (only touches the first character).
local function capitalize_first(s)
  if not s then return s end
  s = utils.stringify(s)
  if s == "" then return s end

  -- `string.sub` is byte-based but for first-char capitalization
  -- this is usually acceptable for our cases; if needed we can
  -- swap to pandoc.text later.
  local first = s:sub(1, 1)
  local rest  = s:sub(2)

  return first:upper() .. rest
end

-- Title-case helper for prefixes like "sanık" -> "Sanık", "katılan" -> "Katılan".
-- Only the first word's first character is capitalized; the rest is preserved.
local function title_case(s)
  if not s then return s end
  s = utils.stringify(s)
  if s == "" then return s end

  local space_pos = s:find(" ", 1, true)
  if not space_pos then
    -- single word
    return capitalize_first(s)
  end

  local first_word = s:sub(1, space_pos - 1)
  local rest       = s:sub(space_pos)  -- includes the space

  return capitalize_first(first_word) .. rest
end

----------------------------------------------------------------
-- VARIANT BUILDER (same logic as utils_participant.lua)
----------------------------------------------------------------

-- fullname: e.g. "Narin Güran"
-- prefixes: {"maktul", ...} or {}
-- suffixes: {...} or {}
-- enable_name_variants:
--   true  → generate short-name variants (e.g. "Narin", "maktul Narin")
--   false → only use fullname and prefix+fullname forms (no short-name variants)
local function build_variants_for_name(fullname, prefixes, suffixes, enable_name_variants)
  local variants = {}

  local function add(s)
    s = normalize_spaces(s)
    if s ~= "" then
      variants[s] = true
    end
  end

  fullname = normalize_spaces(fullname)
  if fullname == "" then
    return variants
  end

  --------------------------------------------------------------------
  -- Extract given-name part (everything except the last token),
  -- e.g. "Narin Güran"           → "Narin"
  --      "Muhammed Fatih Demir" → "Muhammed Fatih"
  --------------------------------------------------------------------
  local given_part = nil
  do
    local before, last = fullname:match("^(.-)%s+(%S+)$")
    if before and before ~= "" then
      given_part = normalize_spaces(before)
    end
  end

  --------------------------------------------------------------------
  -- 0) Base forms
  --------------------------------------------------------------------
  -- Always add the full name.
  add(fullname)

  local bases = { fullname }

  --------------------------------------------------------------------
  -- 0.1) If enable_name_variants: fullname with UPPERCASE SURNAME
  --------------------------------------------------------------------
  if enable_name_variants then
    local before, last = fullname:match("^(.-)%s+(%S+)$")
    if last then
      local given = normalize_spaces(before)
      local lastU = to_upper_tr(last)
      local upper_full = normalize_spaces(given .. " " .. lastU)
      add(upper_full)
      table.insert(bases, upper_full)
    end
  end

  -- If enabled, also add the given-name-only version as a base, e.g. "Narin".
  if enable_name_variants and given_part then
    add(given_part)
    table.insert(bases, given_part)
  end

  -- Add prefix+base variants, e.g. "maktul Narin", "Maktul Narin", etc.
  if prefixes and #prefixes > 0 then
    for _, base in ipairs(bases) do
      for _, pfx in ipairs(prefixes) do
        local p1 = normalize_spaces(pfx .. " " .. base)             -- lower-case prefix
        local p2 = normalize_spaces(title_case(pfx) .. " " .. base) -- capitalized prefix

        add(p1)
        add(p2)
      end
    end
  end

  --------------------------------------------------------------------
  -- Add suffixes (if any) to every variant we have so far.
  --------------------------------------------------------------------
  if suffixes and #suffixes > 0 then
    local current = {}
    for v, _ in pairs(variants) do
      table.insert(current, v)
    end
    for _, base in ipairs(current) do
      for _, sfx in ipairs(suffixes) do
        local s = normalize_spaces(base .. " " .. sfx)
        add(s)
      end
    end
  end

  return variants
end

----------------------------------------------------------------
-- LOAD SPEAKERS FROM `metadata.participant`
-- Mirrors the structure in utils_participant.lua, but:
--   * We only care about groups and name variants
--   * No tooltip labels; just group → CSS class mapping
----------------------------------------------------------------

local function load_speakers_from_meta(meta)
  groups      = {}
  nameToClass = {}
  ALL_NAMES   = {}

  if not meta then
    return
  end

  local participant_meta = meta.participant or (meta.metadata and meta.metadata.participant)
  if type(participant_meta) ~= "table" then
    return
  end

  -- participant:
  --   victim:
  --     - text: "Maktul"
  --     - variant: true
  --     - prefix: [ "maktul" ]
  --     - names:  [ "Narin Güran" ]
  for group, group_meta in pairs(participant_meta) do
    local group_variant = false
    local prefixes = {}
    local suffixes = {}
    local names    = {}

    if type(group_meta) == "table" then
      for _, item in ipairs(group_meta) do
        if type(item) == "table" then
          if item.variant ~= nil then
            group_variant = not not item.variant
          end
          if item.prefix ~= nil then
            if type(item.prefix) == "table" then
              for _, p in ipairs(item.prefix) do
                table.insert(prefixes, utils.stringify(p))
              end
            else
              table.insert(prefixes, utils.stringify(item.prefix))
            end
          end
          if item.suffix ~= nil then
            if type(item.suffix) == "table" then
              for _, s in ipairs(item.suffix) do
                table.insert(suffixes, utils.stringify(s))
              end
            else
              table.insert(suffixes, utils.stringify(item.suffix))
            end
          end
          if item.names ~= nil then
            if type(item.names) == "table" then
              for _, n in ipairs(item.names) do
                table.insert(names, utils.stringify(n))
              end
            else
              table.insert(names, utils.stringify(item.names))
            end
          end
        end
      end
    end

    if #names > 0 then
      -- group → original names (optional bookkeeping)
      groups[group] = names

      local enable_name_variants = group_variant

      for _, raw_name in ipairs(names) do
        local base = normalize_spaces(utils.stringify(raw_name) or "")
        if base ~= "" then
          local variants = build_variants_for_name(
            base,
            prefixes,
            suffixes,
            enable_name_variants
          )
          for v, _ in pairs(variants) do
            nameToClass[v] = group
            table.insert(ALL_NAMES, v)
          end
        end
      end
    end
  end

  -- Sort longest names first to avoid partial matches
  table.sort(ALL_NAMES, function(a, b) return #a > #b end)
end

----------------------------------------------------------------
-- UTILITY HELPERS (unchanged)
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
  -- Skip processing for index.qmd (optional, keeps old behavior)
  local input = (quarto and quarto.doc and quarto.doc.input_file) or ""
  if type(input) == "string" and input ~= "" then
    local fname = input:match("([^/\\]+)$") or input
    if fname == "index.qmd" then
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

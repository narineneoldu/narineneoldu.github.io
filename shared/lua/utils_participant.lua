-- ../shared/lua/utils_participant.lua
-- Participant / person name detector based on `metadata.participant`.
--
-- Public API:
--   M.set_dict(meta)
--   M.find(textline) ->
--       { { s = i1, e = j1, kind = "participant", group = "suspect", label = "Sanık" }, ... }

local M    = {}
local text = require 'pandoc.text'

-- Internal cache:
--   PARTICIPANTS: array of { name = "Nevzat Bahtiyar", group = "suspect", label = "Sanık" }
local PARTICIPANTS = nil

-- Optional human-readable labels for each group, taken from YAML `text`.
--   GROUP_LABELS["suspect"] = "Sanık"
local GROUP_LABELS = {}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

-- Trim and normalize internal whitespace to a single space.
local function normalize_spaces(s)
  s = s:gsub("%s+", " ")
  s = s:match("^%s*(.-)%s*$") or s
  return s
end

-- ASCII-only lowercase helper (UTF-8 safe for non-ASCII; only A–Z → a–z).
local function ascii_lower(s)
  return (s:gsub("%u", function(c)
    local b = c:byte()
    if b >= 65 and b <= 90 then -- 'A'..'Z'
      return string.char(b + 32)
    end
    return c
  end))
end

-- ASCII-only uppercase helper (UTF-8 safe for non-ASCII; only a–z → A–Z).
local function ascii_upper(s)
  return (s:gsub("%l", function(c)
    local b = c:byte()
    if b >= 97 and b <= 122 then -- 'a'..'z'
      return string.char(b - 32)
    end
    return c
  end))
end

-- Turkish-aware lowercase helper.
-- First map Turkish uppercase letters to their lowercase equivalents,
-- then lowercase remaining ASCII letters.
local function to_lower_tr(s)
  if not s then return "" end
  s = s:gsub("İ", "i")
       :gsub("I", "ı")
       :gsub("Ç", "ç")
       :gsub("Ğ", "ğ")
       :gsub("Ö", "ö")
       :gsub("Ş", "ş")
       :gsub("Ü", "ü")
  s = ascii_lower(s)
  return s
end

-- Turkish-aware uppercase helper for the surname part (used for variant forms).
-- First map Turkish lowercase letters to their uppercase equivalents,
-- then uppercase remaining ASCII letters.
local function to_upper_tr(s)
  if not s then return "" end
  s = s:gsub("i", "İ")
       :gsub("ı", "I")
       :gsub("ç", "Ç")
       :gsub("ğ", "Ğ")
       :gsub("ö", "Ö")
       :gsub("ş", "Ş")
       :gsub("ü", "Ü")
  s = ascii_upper(s)
  return s
end

-- Capitalize the first character in a UTF-8 safe way (only touches the first character).
local function capitalize_first(s)
  if not s then return s end
  s = pandoc.utils.stringify(s)
  if s == "" then return s end

  -- text.sub operates on codepoints, so it is UTF-8 safe.
  local first = text.sub(s, 1, 1)
  local rest  = text.sub(s, 2)

  -- Usually the first character is ASCII ("s" → "S"), so ascii_upper is enough here.
  return ascii_upper(first) .. rest
end

-- Title-case helper for prefixes like "sanık" -> "Sanık", "katılan" -> "Katılan".
-- Only the first word's first character is capitalized; the rest is preserved.
local function title_case(s)
  if not s then return s end
  s = pandoc.utils.stringify(s)
  if s == "" then return s end

  local space_pos = s:find(" ", 1, true)
  if not space_pos then
    return capitalize_first(s)
  end

  local first_word = s:sub(1, space_pos - 1)
  local rest       = s:sub(space_pos)

  return capitalize_first(first_word) .. rest
end

----------------------------------------------------------------------
-- Build participants table from metadata
----------------------------------------------------------------------

-- fullname: e.g. "Narin Güran"
-- prefixes: {"Sanık", "Maktul", ...} or {}
-- enable_name_variants:
--   true  → generate additional forms (e.g. UPPERCASE surname)
--   false → only use fullname and prefix+fullname forms
local function build_variants_for_name(fullname, prefixes, enable_name_variants)
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
  -- 0) Base forms (unprefixed)
  --------------------------------------------------------------------
  -- Always add the full name (e.g. "Narin Güran").
  add(fullname)

  local bases = { fullname }

  -- If enabled, also add a variant with UPPERCASE SURNAME
  -- (e.g. "Narin GÜRAN") to support matching text where the surname is uppercased.
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

  -- We do NOT add the bare given-name ("Salim") as an unprefixed variant,
  -- because standalone first names must not be wrapped.
  -- However, we still want forms like "Sanık Salim" / "Maktul Narin",
  -- so we add given_part into `bases` for prefix expansion only.
  if given_part then
    table.insert(bases, given_part)
  end

  --------------------------------------------------------------------
  -- 1) Prefix + base variants, for example:
  --    "sanık Salim", "Sanık Salim",
  --    "sanık Salim Güran", "Sanık Salim Güran",
  --    "maktul Narin", "Maktul Narin", etc.
  --
  -- These are the actual visible variants that will be matched in text.
  --------------------------------------------------------------------
  if prefixes and #prefixes > 0 then
    for _, base in ipairs(bases) do
      for _, pfx in ipairs(prefixes) do
        local pfx_lc = to_lower_tr(pfx)
        local p1 = normalize_spaces(pfx_lc .. " " .. base)             -- lower-case prefix
        local p2 = normalize_spaces(title_case(pfx_lc) .. " " .. base) -- capitalized prefix

        add(p1)
        add(p2)
      end
    end
  end

  -- We deliberately do NOT generate suffix variants such as:
  --   "Salim Güran’ın" / "Sanık Salim’in"
  -- so that the apostrophe and suffix stay outside the span.
  -- The matcher will only wrap the variant itself, e.g. "Sanık Salim".

  return variants
end

local function build_participants_from_meta(meta)
  PARTICIPANTS = {}
  GROUP_LABELS = {}

  if not meta then
    return
  end

  local participant_meta = meta.participant or (meta.metadata and meta.metadata.participant)
  if type(participant_meta) ~= "table" then
    return
  end

  -- participant_meta is expected to be a map from group name to a YAML sequence.
  for group, group_meta in pairs(participant_meta) do
    -- group_meta is a list (sequence) of small maps:
    --   - text:    "Sanık" / "Maktul" / ...
    --   - variant: true/false
    --   - prefix:  "..." or [ ... ]
    --   - names:   "..." or [ ... ]
    local group_variant = false
    local prefixes = {}
    local names    = {}
    local group_label = nil

    if type(group_meta) == "table" then
      for _, item in ipairs(group_meta) do
        if type(item) == "table" then
          if item.variant ~= nil then
            group_variant = not not item.variant
          end
          if item.text ~= nil then
            group_label = pandoc.utils.stringify(item.text)
          end
          if item.prefix ~= nil then
            if type(item.prefix) == "table" then
              for _, p in ipairs(item.prefix) do
                table.insert(prefixes, pandoc.utils.stringify(p))
              end
            else
              table.insert(prefixes, pandoc.utils.stringify(item.prefix))
            end
          end
          if item.names ~= nil then
            if type(item.names) == "table" then
              for _, n in ipairs(item.names) do
                table.insert(names, pandoc.utils.stringify(n))
              end
            else
              table.insert(names, pandoc.utils.stringify(item.names))
            end
          end
        end
      end
    end

    -- Store label per group (optional, might be reused elsewhere).
    if group_label and group_label ~= "" then
      GROUP_LABELS[group] = group_label
    end

    local enable_name_variants = group_variant
    local label_lc = group_label and to_lower_tr(group_label) or nil

    for _, raw_name in ipairs(names) do
      local base = normalize_spaces(pandoc.utils.stringify(raw_name) or "")
      if base ~= "" then
        local name_variants = build_variants_for_name(
          base,
          prefixes,
          enable_name_variants
        )

        -- Extract surname (last token) in lowercase, used for label decisions.
        local _, base_last = base:match("^(.-)%s+(%S+)$")
        local surname_lc = base_last and to_lower_tr(base_last) or nil

        for v, _ in pairs(name_variants) do
          local label_for_variant = nil

          if label_lc and label_lc ~= "" then
            local v_lc = to_lower_tr(v)

            local has_group   = v_lc:find(label_lc, 1, true) ~= nil
            local has_surname = surname_lc and v_lc:find(surname_lc, 1, true) ~= nil

            -- If the visible variant already contains the group label
            -- ("maktul"/"sanık"), do not repeat it in data-title.
            if not has_group then
              if not has_surname then
                -- No surname in the visible variant → label = "Maktul Narin Güran"
                label_for_variant = group_label .. " " .. base
              else
                -- Surname present but group label not → label = "Maktul"
                label_for_variant = group_label
              end
            end
          end

          table.insert(PARTICIPANTS, {
            name  = v,
            group = group,
            label = label_for_variant,
          })
        end
      end
    end
  end

  -- Sort by name length descending so that longer matches win when scanning.
  table.sort(PARTICIPANTS, function(a, b)
    return #a.name > #b.name
  end)
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function M.set_dict(meta)
  build_participants_from_meta(meta)
end

-- Check if a single-byte character is an ASCII letter or digit.
local function is_word_char(ch)
  if not ch or ch == "" then
    return false
  end
  -- %w = [0-9A-Za-z]; UTF-8 Turkish letters are not matched here,
  -- but this is enough for basic word-boundary checks.
  return ch:match("[%w]") ~= nil
end

-- Plain finder: returns a list of hits in `textline`.
-- We rely on outer merge logic to resolve overlaps between detectors,
-- but within this detector we prefer longer names by sorting PARTICIPANTS.
local function find_hits(textline)
  if not PARTICIPANTS or #PARTICIPANTS == 0 then
    return {}
  end

  local hits = {}

  -- First ":" position (used to detect speaker-like headers).
  local header_colon = textline:find(":", 1, true)

  -- Normalized line (for simple equality checks).
  local trimmed_line = normalize_spaces(textline)

  ------------------------------------------------------------------
  -- 1) PURE NAME LINE HEURISTIC
  --
  -- If the entire line is exactly a participant name (no colon),
  -- treat it as a header (speaker line) and do not wrap it.
  ------------------------------------------------------------------
  if not header_colon and trimmed_line ~= "" then
    for _, entry in ipairs(PARTICIPANTS) do
      if trimmed_line == entry.name then
        return {}
      end
    end
  end

  ------------------------------------------------------------------
  -- 2) Normal scan (plain find) + left boundary check
  --
  -- Important: we do NOT check the right boundary. That means if the
  -- text contains "Sanık Salim’in", and we have a variant "Sanık Salim",
  -- we will match exactly "Sanık Salim" and leave "’in" outside the span.
  ------------------------------------------------------------------
  local line_len = #textline

  for _, entry in ipairs(PARTICIPANTS) do
    local name  = entry.name
    local group = entry.group
    local label = entry.label

    local start = 1
    while true do
      local s, e = textline:find(name, start, true) -- plain, case-sensitive
      if not s then break end

      -- Is this within a "speaker header" region (before colon)?
      local is_header = false
      if header_colon and s <= header_colon and e <= header_colon then
        if s <= 40 then
          is_header = true
        end
      end

      local left_char  = (s > 1) and textline:sub(s - 1, s - 1) or ""
      local bad_left   = is_word_char(left_char)

      -- We only guard against something like "XSanık Salim" (no left boundary).
      -- On the right, we intentionally allow any continuation,
      -- so that apostrophe + suffix remain outside the span.
      if (not is_header) and (not bad_left) then
        hits[#hits + 1] = {
          s     = s,
          e     = e,
          kind  = "participant",
          group = group,
          label = label,
        }
      end

      start = e + 1
    end
  end

  return hits
end

function M.find(textline)
  return find_hits(textline)
end

return M

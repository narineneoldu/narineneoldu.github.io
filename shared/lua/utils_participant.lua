-- ../shared/lua/utils_participant.lua
-- Participant / person name detector based on `metadata.participant`.
--
-- Public API:
--   M.set_dict(meta)
--   M.find(text) ->
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

-- Turkish-aware lowercase helper.
local function to_lower_tr(s)
  if not s then return "" end
  s = s:gsub("İ", "i")
       :gsub("I", "ı")
       :gsub("Ç", "ç")
       :gsub("Ğ", "ğ")
       :gsub("Ö", "ö")
       :gsub("Ş", "ş")
       :gsub("Ü", "ü")
  return s:lower()
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
  s = pandoc.utils.stringify(s)
  if s == "" then return s end

  -- text.sub operates on codepoints, so it is UTF-8 safe
  local first = text.sub(s, 1, 1)
  local rest  = text.sub(s, 2)

  return text.upper(first) .. rest
end

-- Title-case helper for prefixes like "sanık" -> "Sanık", "katılan" -> "Katılan".
-- Only the first word's first character is capitalized; the rest is preserved.
local function title_case(s)
  if not s then return s end
  s = pandoc.utils.stringify(s)
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

----------------------------------------------------------------------
-- Build participants table from metadata
----------------------------------------------------------------------

-- fullname: e.g. "Narin Güran"
-- prefixes: {"maktul", ...} or {}
-- suffixes: {...} or {}
-- enable_name_variants:
--   true  → generate short-name variants (e.g. "Narin", "maktul Narin")
--   false → only use fullname and prefix+fullname forms (no short-name variants)
local function build_variants_for_name(fullname, group, prefixes, suffixes, enable_name_variants)
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

  -- ikinci değer olarak given_part'ı dön
  return variants, given_part
end

local function build_participants_from_meta(meta)
  PARTICIPANTS = {}
  GROUP_LABELS = {}   -- reset as well

  if not meta then
    return
  end

  local participant_meta = meta.participant or (meta.metadata and meta.metadata.participant)
  if type(participant_meta) ~= "table" then
    return
  end

  -- participant_meta is expected to be a map from group name to a YAML sequence.
  -- Example:
  --   participant:
  --     victim:
  --       - text: "Maktul"
  --       - variant: true
  --       - prefix: [ "maktul" ]
  --       - names:  [ "Narin Güran" ]
  for group, group_meta in pairs(participant_meta) do
    -- group_meta is a list (sequence) of small maps:
    --   - text:    "Sanık" / "Katılan" / ...
    --   - variant: true/false
    --   - prefix:  "..." or [ ... ]
    --   - suffix:  "..." or [ ... ]
    --   - names:   "..." or [ ... ]
    local group_variant = false
    local prefixes = {}
    local suffixes = {}
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
          if item.suffix ~= nil then
            if type(item.suffix) == "table" then
              for _, s in ipairs(item.suffix) do
                table.insert(suffixes, pandoc.utils.stringify(s))
              end
            else
              table.insert(suffixes, pandoc.utils.stringify(item.suffix))
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

    -- Store label per group (optional, might be reused elsewhere)
    if group_label and group_label ~= "" then
      GROUP_LABELS[group] = group_label
    end

    -- group_variant == true → generate short-name variants
    local enable_name_variants = group_variant
    local label_lc = group_label and to_lower_tr(group_label) or nil

    for _, raw_name in ipairs(names) do
      local base = normalize_spaces(pandoc.utils.stringify(raw_name) or "")
      if base ~= "" then
        -- variants + isteğe bağlı given_part (şu anda kullanmıyoruz ama dursun)
        local name_variants, given_part = build_variants_for_name(
          base,
          group,
          prefixes,
          suffixes,
          enable_name_variants
        )

        -- base içinden soyadı (son kelime) çıkar
        local _, base_last = base:match("^(.-)%s+(%S+)$")
        local surname_lc = base_last and to_lower_tr(base_last) or nil

        for v, _ in pairs(name_variants) do
          local label_for_variant = nil

          if label_lc and label_lc ~= "" then
            local v_lc = to_lower_tr(v)

            local has_group   = v_lc:find(label_lc, 1, true) ~= nil
            local has_surname = surname_lc and v_lc:find(surname_lc, 1, true) ~= nil

            -- Varyant içinde group_label ("maktul") zaten varsa label ekleme
            if not has_group then
              if not has_surname then
                -- Soyadı yok → "Maktul Narin Güran"
                label_for_variant = group_label .. " " .. base
              else
                -- Soyadı var ama "Maktul" yok → sadece "Maktul"
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

-- Check if a single-byte character is ASCII letter or digit
local function is_word_char(ch)
  if not ch or ch == "" then
    return false
  end
  -- %w = [0-9A-Za-z]; UTF-8 Türkçe harfleri saymaz ama
  -- hashtag / İngilizce harf / rakam gibi durumlar için yeterli.
  return ch:match("[%w]") ~= nil
end

-- Plain finder: returns a list of hits in `text`.
-- We rely on outer merge logic to resolve overlaps between detectors,
-- but within this detector we prefer longer names by sorting PARTICIPANTS.
local function find_hits(textline)
  if not PARTICIPANTS or #PARTICIPANTS == 0 then
    return {}
  end

  local hits = {}

  -- İlk ":" konumu (speaker header için)
  local header_colon = textline:find(":", 1, true)

  -- Satırı normalize edip kırp
  local trimmed_line = normalize_spaces(textline)

  ------------------------------------------------------------------
  -- 1) PURE NAME LINE HEURISTIC
  ------------------------------------------------------------------
  if not header_colon and trimmed_line ~= "" then
    for _, entry in ipairs(PARTICIPANTS) do
      if trimmed_line == entry.name then
        return {}
      end
    end
  end

  ------------------------------------------------------------------
  -- 2) Normal tarama + boundary kontrolü
  ------------------------------------------------------------------
  local line_len = #textline

  for _, entry in ipairs(PARTICIPANTS) do
    local name  = entry.name
    local group = entry.group
    local label = entry.label  -- per-variant label (may be nil)

    local start = 1
    while true do
      local s, e = textline:find(name, start, true) -- plain, case-sensitive
      if not s then break end

      -- Speaker header bölgesinde mi?
      local is_header = false
      if header_colon and s <= header_colon and e <= header_colon then
        if s <= 40 then
          is_header = true
        end
      end

      -- Boundary check:
      --   * left char: harf/rakam ise → skip
      --   * right char: apostrof hariç harf/rakam ise → skip
      local left_char  = (s > 1) and textline:sub(s - 1, s - 1) or ""
      local right_char = (e < line_len) and textline:sub(e + 1, e + 1) or ""

      local bad_left  = is_word_char(left_char)
      local bad_right = (right_char ~= "'" and is_word_char(right_char))

      if (not is_header) and (not bad_left) and (not bad_right) then
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

-- ../shared/lua/utils_participant.lua
-- Participant / person name detector based on `metadata.speakers`.
--
-- Public API:
--   M.set_dict(meta)
--   M.find(text) ->
--       { { s = i1, e = j1, kind = "participant", group = "suspect" }, ... }

local M = {}

-- Internal cache:
--   PARTICIPANTS: array of { name = "Nevzat Bahtiyar", group = "suspect" }
local PARTICIPANTS = nil

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

-- Trim and normalize internal whitespace to a single space.
local function normalize_spaces(s)
  s = s:gsub("%s+", " ")
  s = s:match("^%s*(.-)%s*$") or s
  return s
end

-- Turkish-aware uppercase helper for the surname part.
local function to_upper_tr(s)
  -- crude but good enough for common Turkish characters
  s = s:gsub("i", "İ")
  s = s:gsub("ı", "I")
  s = s:gsub("ç", "Ç")
  s = s:gsub("ğ", "Ğ")
  s = s:gsub("ö", "Ö")
  s = s:gsub("ş", "Ş")
  s = s:gsub("ü", "Ü")
  return s:upper()
end

-- Strip known prefixes like "Av." or "Law." from the beginning of a name
-- so that "Av. Yılmaz Demiroğlu" and "Yılmaz Demiroğlu" can be treated
-- consistently when needed.
local function strip_prefix(name)
  local s = name
  s = s:gsub("^%s*Av%.%s*", "")
  s = s:gsub("^%s*Law%.%s*", "")
  return normalize_spaces(s)
end

-- Given a base name like "Salim Güran", create an additional variant
-- "Salim GÜRAN" where only the last token is uppercased. This helps
-- matching forms where the surname is written in all caps.
local function make_lastname_upper_variant(base)
  -- require at least two tokens; do not touch single-word names
  local before, last = base:match("^(.-)%s+(%S+)$")
  if not last then
    return nil
  end

  local up_last = to_upper_tr(last)
  if up_last == last then
    return nil
  end

  if before and before ~= "" then
    return (before .. " " .. up_last)
  else
    return up_last
  end
end

----------------------------------------------------------------------
-- Build participants table from metadata
----------------------------------------------------------------------

local function build_participants_from_meta(meta)
  PARTICIPANTS = {}

  if not meta then
    return
  end

  local speakers_meta = meta.speakers or (meta.metadata and meta.metadata.speakers)
  if type(speakers_meta) ~= "table" then
    return
  end

  for group, names_meta in pairs(speakers_meta) do
    -- list case
    if type(names_meta) == "table" and names_meta[1] ~= nil then
      for _, item in ipairs(names_meta) do
        local raw = pandoc.utils.stringify(item)
        if raw ~= "" then
          local base = strip_prefix(raw)
          if base ~= "" then
            base = normalize_spaces(base)
            -- 1) original base
            table.insert(PARTICIPANTS, { name = base, group = group })

            -- 2) variant with LAST token uppercased (if applicable)
            local variant = make_lastname_upper_variant(base)
            if variant and variant ~= base then
              table.insert(PARTICIPANTS, { name = variant, group = group })
            end
          end
        end
      end

    -- single value case
    else
      local raw = pandoc.utils.stringify(names_meta)
      if raw ~= "" then
        local base = strip_prefix(raw)
        if base ~= "" then
          base = normalize_spaces(base)
          -- 1) original base
          table.insert(PARTICIPANTS, { name = base, group = group })

          -- 2) last-name-upper variant
          local variant = make_lastname_upper_variant(base)
          if variant and variant ~= base then
            table.insert(PARTICIPANTS, { name = variant, group = group })
          end
        end
      end
    end
  end

  -- Sort by length (longest first) so that longer names win when overlapping
  table.sort(PARTICIPANTS, function(a, b)
    return #a.name > #b.name
  end)

  -- io.stderr:write("utils_participant: loaded " .. tostring(#PARTICIPANTS) .. " participants\n")
  -- io.stderr:write("sorted participants:\n")
  -- for i,v in ipairs(PARTICIPANTS) do
  --   io.stderr:write("  " .. v.name .. "\n")
  -- end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function M.set_dict(meta)
  build_participants_from_meta(meta)
end

-- Plain finder: returns a list of hits in `text`.
-- We rely on the outer merge logic (span_multi) to resolve overlaps
-- between different detectors, but within this detector we prefer
-- longer names by sorting PARTICIPANTS accordingly.
local function find_hits(text)
  if not PARTICIPANTS or #PARTICIPANTS == 0 then
    return {}
  end

  local hits = {}

  -- First colon in the line (potential "Speaker :" header)
  local header_colon = text:find(":", 1, true)

  for _, entry in ipairs(PARTICIPANTS) do
    local name  = entry.name
    local group = entry.group

    local start = 1
    while true do
      local s, e = text:find(name, start, true) -- plain, case-sensitive
      if not s then break end

      local is_header = false
      if header_colon and s <= header_colon and e <= header_colon then
        -- name is entirely before the first colon
        -- and close to the start of the line → very likely a "Speaker :" label
        if s <= 40 then  -- tweakable threshold
          is_header = true
        end
      end

      if not is_header then
        hits[#hits + 1] = {
          s     = s,
          e     = e,
          kind  = "participant",
          group = group,
        }
      end

      start = e + 1
    end
  end

  return hits
end
function M.find(text)
  return find_hits(text)
end

return M

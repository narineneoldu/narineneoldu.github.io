--[[
  _extensions/media-short/plyr-common.lua

  Shared helpers for Plyr-based shortcodes (video, audio, etc.).

  This module is designed to be required from both filter-video.lua and
  filter-audio.lua so that the common logic lives in a single place.

  Provided helpers:

    - raw_block(html)
        Wraps a raw HTML string into a Pandoc RawBlock.

    - normalize_string(v)
        Converts a Pandoc MetaValue or arbitrary value into a string.
        Empty string ("") and literal "false" are treated as nil.

    - normalize_bool(v)
        Converts a Pandoc MetaValue or arbitrary value into a boolean.
        Accepted true values:  "true", "1"
        Accepted false values: "false", "0"
        Empty string is treated as nil. Any other value returns nil.

    - kw(kwargs, name)
        Convenience helper around normalize_string(kwargs[name]).

    - kw_bool(kwargs, name)
        Convenience helper around normalize_bool(kwargs[name]).

    - build_attr(tbl)
        Given a table of key -> value pairs, builds an inline HTML attribute
        string such as:
          { id = "foo", ["data-start"] = "10" }
        -> ' id="foo" data-start="10"'.

    - build_style(tbl)
        Given a table of CSS property -> value pairs, builds a style attribute:
          { ["max-width"] = "320px" }
        -> ' style="max-width:320px;"'.

    - read_plyr_meta_defaults(meta, ATTR_SPEC, meta_key)
        Reads per-page defaults from document metadata under a shared key
        (default "plyr-defaults"). The structure is:

          plyr-defaults:
            ratio: "16:9"
            controls: "shorts"
            fullscreen: false
            width: "320px"

        Only keys listed in ATTR_SPEC are consumed; all others are ignored.
        Additionally, the special key "controls" is read as a preset name and
        stored as result["controls"], so that control presets can be resolved
        uniformly in both video and audio filters.

        - meta        : pandoc.Meta
        - ATTR_SPEC   : table describing each supported attribute
                        (same format as in filter-video.lua / filter-audio.lua)
        - meta_key    : optional metadata key (defaults to "plyr-defaults")

        Returns: a plain Lua table with normalized values ready to be merged
        with shortcode kwargs.
]]

local M = {}

------------------------------------------------------------
-- Low-level helpers
------------------------------------------------------------

--- Wrap an HTML string in a Pandoc RawBlock.
-- @param html string: raw HTML markup
-- @return pandoc.RawBlock
function M.raw_block(html)
  return pandoc.RawBlock("html", html)
end

--- Normalize a value to a string for shortcode / metadata use.
-- Empty string and literal "false" are treated as nil.
-- @param v any
-- @return string|nil
function M.normalize_string(v)
  if v == nil then
    return nil
  end
  v = pandoc.utils.stringify(v)
  if v == "" or v == "false" then
    return nil
  end
  return v
end

--- Normalize a value to a boolean for shortcode / metadata use.
-- Accepts "true"/"1", "false"/"0"; others become nil.
-- @param v any
-- @return boolean|nil
function M.normalize_bool(v)
  if v == nil then
    return nil
  end
  v = pandoc.utils.stringify(v)
  if v == "" then
    return nil
  end
  if v == "true" or v == "1" then
    return true
  end
  if v == "false" or v == "0" then
    return false
  end
  return nil
end

--- Keyword argument normalizer (string) from shortcode kwargs.
-- Uses normalize_string under the hood.
-- @param kwargs table
-- @param name string
-- @return string|nil
function M.kw(kwargs, name)
  return M.normalize_string(kwargs[name])
end

--- Keyword argument normalizer (bool) from shortcode kwargs.
-- Uses normalize_bool under the hood.
-- @param kwargs table
-- @param name string
-- @return boolean|nil
function M.kw_bool(kwargs, name)
  return M.normalize_bool(kwargs[name])
end

------------------------------------------------------------
-- Attribute and style builders
------------------------------------------------------------

--- Build an attribute string from a table of key -> value pairs.
-- Example: {id="foo", ["data-start"]="10"} -> ' id="foo" data-start="10"'
-- @param tbl table
-- @return string
function M.build_attr(tbl)
  local keys = {}

  -- Collect keys that have non-nil values
  for k, v in pairs(tbl) do
    if v ~= nil then
      table.insert(keys, k)
    end
  end

  -- Sort attribute names alphabetically to ensure deterministic output
  table.sort(keys)

  -- Build attributes in sorted order
  local out = {}
  for _, k in ipairs(keys) do
    local v = tbl[k]
    table.insert(out, string.format(' %s="%s"', k, v))
  end

  return table.concat(out)
end

--- Build a style attribute from a map of CSS property -> value.
-- Example: {["max-width"]="320px"} -> ' style="max-width:320px;"'
-- @param tbl table
-- @return string
function M.build_style(tbl)
  local keys = {}

  -- Collect CSS property names that have non-nil values
  for css, val in pairs(tbl) do
    if val ~= nil then
      table.insert(keys, css)
    end
  end

  -- Sort properties alphabetically so output is stable
  table.sort(keys)

  -- Build style="..." string in sorted order
  local parts = {}
  for _, css in ipairs(keys) do
    local val = tbl[css]
    table.insert(parts, css .. ":" .. val .. ";")
  end

  if #parts == 0 then
    return ""
  end

  return ' style="' .. table.concat(parts, " ") .. '"'
end

------------------------------------------------------------
-- Metadata defaults reader
------------------------------------------------------------

--- Read per-page Plyr defaults from document metadata.
--
-- Metadata structure (for the default key "plyr-defaults"):
--
--   plyr-defaults:
--     ratio: "16:9"
--     controls: "shorts"
--     fullscreen: false
--     width: "320px"
--     class: "my-default-video"
--
-- Only keys listed in ATTR_SPEC are consumed. This allows video and audio
-- filters to share the same metadata block but ignore unsupported keys
-- (e.g. "ratio" for audio).
--
-- Additionally, the special key "controls" is read separately and returned
-- as result["controls"] so that control presets can be handled consistently.
--
-- @param meta      pandoc.Meta
-- @param ATTR_SPEC table: attribute specification map from the filter
-- @param meta_key  string|nil: metadata key, defaults to "plyr-defaults"
-- @return table
function M.read_plyr_meta_defaults(meta, ATTR_SPEC, meta_key)
  local result = {}

  local key = meta_key or "plyr-defaults"
  local node = meta and meta[key]
  if not node or type(node) ~= "table" then
    return result
  end

  -- Apply defaults for attributes defined in ATTR_SPEC
  for name, spec in pairs(ATTR_SPEC) do
    local raw = node[name]
    if raw ~= nil then
      if spec.type == "bool" then
        result[name] = M.normalize_bool(raw)
      else
        result[name] = M.normalize_string(raw)
      end
    end
  end

  -- Special handling for the controls preset name (if present)
  local raw_controls = node["controls"]
  if raw_controls ~= nil then
    result["controls"] = M.normalize_string(raw_controls)
  end

  return result
end

return M

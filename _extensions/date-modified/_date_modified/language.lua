--[[
  language.lua

  Generic helper module for Quarto Lua filters / extensions.

  Responsibilities:
    * Detect the effective language from document metadata (meta["lang"]).
    * Locate and load language YAML files relative to this module:
         <this_module_dir>/language
       Expected files:
         - _language.yml            (required, default)
         - _language-xx.yml         (optional, e.g. _language-tr.yml)
         - _language-xx-YY.yml      (optional, e.g. _language-tr-TR.yml)
    * Return a plain Lua table mirroring the keys in the loaded YAML file.

  Rules:
    * If _language.yml does not exist → raise an error.
    * If meta["lang"] is not defined → use _language.yml and log a warning.
    * If a specific language file is missing for the current lang:
         1) Try exact tag (e.g. _language-tr-TR.yml),
         2) Then try short code (e.g. _language-tr.yml),
         3) Otherwise fall back to _language.yml and log a warning.
]]

local M = {}

------------------------------------------------------------
-- Small helpers
------------------------------------------------------------

--- Directory where this module (language.lua) lives.
local function this_module_dir()
  -- debug.getinfo(1, "S").source returns something like "@/full/path/to/language.lua"
  local info = debug.getinfo(1, "S")
  local src = info and info.source or ""
  if src:sub(1, 1) == "@" then
    src = src:sub(2)
  end
  -- Strip filename, keep directory
  local dir = src:match("^(.*)[/\\][^/\\]+$") or "."
  return dir
end

--- Directory where language YAML files live (relative to language.lua).
local function language_dir()
  return this_module_dir() .. "/language"
end

--- Check whether a file exists.
-- @param path string
-- @return boolean
local function file_exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end


------------------------------------------------------------
-- Normalization: make values JSON-safe while preserving structure
-- - Maps stay maps, lists stay lists
-- - Leaves become primitives (string/number/boolean/nil)
-- - Pandoc Meta*/AST nodes are stringified
-- - No userdata reaches callers
------------------------------------------------------------

--- Normalize any plain Lua value into a JSON-safe structure.
-- Preserves tables (maps/lists) recursively; collapses non-JSON leaves to strings.
-- @param value any
-- @return any
local function normalize_tree(value)
  local t = type(value)

  if t == "nil" or t == "boolean" or t == "number" or t == "string" then
    return value
  end

  if t == "table" then
    -- Decide array vs object using keys
    local is_array = true
    local max_idx = 0

    for k, _ in pairs(value) do
      if type(k) ~= "number" then
        is_array = false
        break
      end
      if k > max_idx then
        max_idx = k
      end
    end

    if is_array then
      local out = {}
      for i = 1, max_idx do
        out[i] = normalize_tree(value[i])
      end
      return out
    else
      local out = {}
      for k, v in pairs(value) do
        out[tostring(k)] = normalize_tree(v)
      end
      return out
    end
  end

  -- userdata/function/thread: collapse to string to remain JSON-safe
  return tostring(value)
end

--- Convert Pandoc Meta values to plain Lua types.
-- YAML language files should become: string/boolean/table (recursively).
-- @param value any
-- @return any
local function meta_to_plain(value)
  local pt = pandoc.utils.type(value)

  if pt == "MetaMap" then
    local out = {}
    for k, v in pairs(value) do
      out[tostring(k)] = meta_to_plain(v)
    end
    return out
  end

  if pt == "MetaList" or pt == "List" then
    local out = {}
    for i, v in ipairs(value) do
      out[i] = meta_to_plain(v)
    end
    return out
  end

  if pt == "MetaBool" then
    return value.c
  end

  -- For language YAML: treat everything else as a string
  if pt ~= nil then
    return pandoc.utils.stringify(value)
  end

  -- Plain Lua already
  return value
end

--- Load a YAML file using pandoc's front-matter parser.
-- The file is wrapped in a dummy markdown document with YAML front matter.
-- @param path string
-- @return table|nil, string|nil  table on success, error message on failure
local function load_yaml_file(path)
  local f, err = io.open(path, "r")
  if not f then
    return nil, err or "unable to open file"
  end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then
    return {}
  end

  local doc = pandoc.read("---\n" .. content .. "\n---", "markdown")
  local meta = doc.meta or {}
  local result = {}
  for k, v in pairs(meta) do
    result[k] = meta_to_plain(v)
  end

  result = normalize_tree(result)

  return result
end

--- Detect language tag and short code from document metadata.
-- Uses meta["lang"]; examples:
--   "tr"      -> lang_tag="tr",    short="tr"
--   "tr-TR"   -> lang_tag="tr-TR", short="tr"
--   "" or nil -> lang_tag="en",    short="en" (with warning)
-- @param meta pandoc.Meta
-- @return string, string  lang_tag, short_code
local function detect_lang(meta)
  local lang_value = pandoc.utils.stringify(meta["lang"] or "")
  if lang_value == "" then
    io.stderr:write(
      "[language] Warning: no 'lang' defined in _quarto.yml; " ..
      "using default language file _language.yml\n"
    )
    return "en", "en"
  end

  local short = lang_value:match("^([a-z][a-z])") or "en"
  return lang_value, short
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------

--- Load language resources for the current document.
-- Looks for YAML files under <this_module_dir>/language:
--   _language.yml          (required, default)
--   _language-xx.yml       (optional: short code, e.g. tr)
--   _language-xx-YY.yml    (optional: full tag, e.g. tr-TR)
--
-- Resolution order for meta["lang"] = "tr-TR":
--   1) _language-tr-TR.yml (exact tag)
--   2) _language-tr.yml    (short code)
--   3) _language.yml       (default, with warning)
--
-- @param meta pandoc.Meta
-- @return table  plain key/value table from YAML, plus:
--   - lang      : short code (e.g. "tr")
--   - lang_tag  : full tag  (e.g. "tr-TR")
function M.load(meta)
  local dir = language_dir()
  local default_path = dir .. "/_language.yml"

  -- Default file is mandatory.
  if not file_exists(default_path) then
    error(
      "[language] Missing required default language file: " ..
      default_path .. "\n"
    )
  end

  local lang_tag, short = detect_lang(meta)

  local chosen_path = default_path

  -- 1) Try exact tag: _language-tr-TR.yml
  if lang_tag and lang_tag ~= "" and lang_tag ~= "en" then
    local candidate_full = dir .. "/_language-" .. lang_tag .. ".yml"
    if file_exists(candidate_full) then
      chosen_path = candidate_full
    else
      -- 2) Try short code: _language-tr.yml
      if short and short ~= "" and short ~= "en" then
        local candidate_short = dir .. "/_language-" .. short .. ".yml"
        if file_exists(candidate_short) then
          chosen_path = candidate_short
        else
          io.stderr:write(
            "[language] Warning: language files not found for lang='" ..
            lang_tag .. "' (tried " .. candidate_full .. " and " ..
            candidate_short .. "); falling back to _language.yml\n"
          )
        end
      else
        io.stderr:write(
          "[language] Warning: language file not found for lang='" ..
          lang_tag .. "' (" .. candidate_full ..
          "); falling back to _language.yml\n"
        )
      end
    end
  end

  local data, err = load_yaml_file(chosen_path)
  if not data then
    error(
      "[language] Failed to load language file '" ..
      chosen_path .. "': " .. tostring(err)
    )
  end

  -- Expose both short code and full tag for callers
  data["lang"] = short or "en"
  data["lang_tag"] = lang_tag or "en"

  -- Return the plain key/value table so callers can access YAML keys directly
  return data
end

return M

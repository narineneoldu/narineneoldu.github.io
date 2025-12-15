--[[
# _hashtag/config.lua

Configuration reader and normalizer for the `hashtag` Quarto extension.

Responsibilities:
  - Define default configuration values
  - Read user configuration from document or project metadata
  - Normalize and validate configuration fields
  - Merge provider registry overrides
  - Ensure required HTML dependencies when enabled

This module is intentionally side-effect free except for:
  - Ensuring icon dependencies when `icons: true`
  - Emitting warnings for invalid provider references

Exports:
  - read_config(meta) -> table
  - DEFAULT_CFG
]]

local M = {}

local deps      = require("_hashtag.deps")
local providers = require("_hashtag.providers")
local meta      = require("_hashtag.meta")

------------------------------------------------------------
-- Defaults
------------------------------------------------------------

M.DEFAULT_CFG = {
  -- Core behavior
  auto_scan        = false,
  linkify          = true,
  default_provider = "x",
  target           = "_blank",
  title            = true,

  -- Filtering / rendering
  skip_classes    = {},
  providers       = providers.PROVIDERS,
  icons           = true,
  rel             = "noopener noreferrer nofollow",
  hashtag_numbers = 0,
}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

--[[ Resolve the `hashtag` metadata block from document or project scope. ]]
local function get_hashtag_block(meta_in)
  local m = meta_in
  if quarto and quarto.doc and quarto.doc.meta then
    m = quarto.doc.meta
  end

  if not m then return nil end

  if type(m["hashtag"]) == "table" then
    return m["hashtag"]
  end

  -- Project-level defaults may arrive under `metadata:`
  if type(m["metadata"]) == "table" then
    return m["metadata"]["hashtag"]
  end

  return nil
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------

--[[
Read and normalize configuration from metadata.

Parameters:
  meta_in (table|nil): Pandoc metadata table

Returns:
  table: normalized configuration
]]
function M.read_config(meta_in)
  -- Start with a shallow copy of defaults
  local cfg = {
    auto_scan        = M.DEFAULT_CFG.auto_scan,
    linkify          = M.DEFAULT_CFG.linkify,
    default_provider = M.DEFAULT_CFG.default_provider,
    target           = M.DEFAULT_CFG.target,
    title            = M.DEFAULT_CFG.title,

    skip_classes    = {},
    providers       = M.DEFAULT_CFG.providers,
    icons           = M.DEFAULT_CFG.icons,
    rel             = M.DEFAULT_CFG.rel,
    hashtag_numbers = M.DEFAULT_CFG.hashtag_numbers,
  }

  local block = get_hashtag_block(meta_in)
  if type(block) ~= "table" then
    return cfg
  end

  ----------------------------------------------------------
  -- Core flags
  ----------------------------------------------------------

  cfg.linkify   = meta.read_bool(block["linkify"], cfg.linkify)
  cfg.auto_scan = meta.read_bool(block["auto-scan"], cfg.auto_scan)
  cfg.title     = meta.read_bool(block["title"], cfg.title)

  ----------------------------------------------------------
  -- Provider + link behavior
  ----------------------------------------------------------

  local pv = block["default-provider"]
  if pv ~= nil and not meta.is_disabled(pv) then
    local key = providers.normalize_provider_key(pv)
    if key then cfg.default_provider = key end
  end

  local tv = block["target"]
  if tv ~= nil then
    cfg.target = meta.is_disabled_signal(tv) and nil or pandoc.utils.stringify(tv)
  end

  local relv = block["rel"]
  if relv ~= nil then
    cfg.rel = meta.is_disabled_signal(relv) and nil or pandoc.utils.stringify(relv)
  end

  ----------------------------------------------------------
  -- Filtering and rendering options
  ----------------------------------------------------------

  cfg.skip_classes    = meta.read_string_list(block["skip-classes"], cfg.skip_classes)
  cfg.hashtag_numbers = meta.read_number(block["hashtag-numbers"], cfg.hashtag_numbers)

  cfg.icons = meta.read_bool(block["icons"], cfg.icons)
  if cfg.icons then
    deps.ensure_html_bi_dependency()
  end

  ----------------------------------------------------------
  -- Provider registry
  ----------------------------------------------------------

  cfg.providers = meta.deep_copy_providers(providers.PROVIDERS)

  if cfg.default_provider and not cfg.providers[cfg.default_provider] then
    io.stderr:write(
      "[hashtag] Warning: default-provider '" .. cfg.default_provider ..
      "' not found; hashtags will render as plain text.\n"
    )
  end

  if type(block["providers"]) == "table" then
    for k, v in pairs(block["providers"]) do
      local key = providers.normalize_provider_key(k)
      if key then
        cfg.providers[key] = {
          url  = v and v["url"]  and pandoc.utils.stringify(v["url"])
              or (cfg.providers[key] and cfg.providers[key].url),
          name = v and v["name"] and pandoc.utils.stringify(v["name"])
              or (cfg.providers[key] and cfg.providers[key].name),
        }
      end
    end
  end

  return cfg
end

return M

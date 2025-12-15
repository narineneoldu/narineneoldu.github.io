--[[
# _hashtag/core.lua

Core runtime utilities for the `hashtag` Quarto extension.

Responsibilities:
  - Read config (delegated to `_hashtag.config`)
  - Deterministic attribute construction for Link/Span
  - Numeric hashtag policy helpers
  - Provider URL expansion with safe URL-encoding
  - Provider-agnostic hashtag rendering utilities

Exports:
  - read_config(meta)
  - normalize_provider_key(v)
  - hashtag_link_attr(provider, cfg)
  - hashtag_span_attr(provider, cfg)
  - is_numeric_tag(body)
  - should_link_numeric(body, cfg)
  - url_encode(s)
  - build_url(cfg, provider, tag)
]]

local M = {}

local deps = require("_hashtag.deps")
local config = require("_hashtag.config")
local providers = require("_hashtag.providers")

------------------------------------------------------------
-- Config API (delegation)
------------------------------------------------------------

--[[ Read normalized config from metadata. ]]
function M.read_config(meta)
  return config.read_config(meta)
end

--[[ Normalize provider keys for user-facing inputs. ]]
M.normalize_provider_key = providers.normalize_provider_key

------------------------------------------------------------
-- Attribute helpers
------------------------------------------------------------

--[[ Get the display title for a provider from config. ]]
local function provider_title(cfg, provider)
  if not (cfg and cfg.title and cfg.providers and cfg.providers[provider]) then
    return nil
  end
  return cfg.providers[provider].name
end

--[[ Convert a key/value map into a deterministic Pandoc attribute list. ]]
local function build_sorted_kv(tbl)
  local keys = {}
  for k, v in pairs(tbl) do
    if v ~= nil then keys[#keys + 1] = k end
  end
  table.sort(keys)

  local out = {}
  for _, k in ipairs(keys) do
    out[#out + 1] = { k, tostring(tbl[k]) }
  end
  return out
end

--[[ Build shared CSS classes and return provider slug. ]]
local function build_classes(provider)
  local p = providers.normalize_provider_key(provider) or ""
  local classes = { "hashtag", "hashtag-provider" }
  if p ~= "" then classes[#classes + 1] = "hashtag-" .. p end
  return p, classes
end

--[[
Construct Pandoc Attr for LINK output.

Returns:
  pandoc.Attr
]]
function M.hashtag_link_attr(provider, cfg)
  deps.ensure_html_dependency()

  local p, classes = build_classes(provider)
  local title = provider_title(cfg, provider)
  local target = (cfg == nil) and "_blank" or cfg.target

  local attr_map = {
    target = target, -- default unless explicitly disabled
    rel = (cfg and cfg.rel) or nil,
    ["data-provider"] = (p ~= "" and p) or nil,
    ["data-title"] = title,
  }

  return pandoc.Attr("", classes, build_sorted_kv(attr_map))
end

--[[
Construct Pandoc Attr for SPAN output.

Returns:
  pandoc.Attr
]]
function M.hashtag_span_attr(provider, cfg)
  deps.ensure_html_dependency()

  local p, classes = build_classes(provider)
  local title = provider_title(cfg, provider)

  local attr_map = {
    ["data-provider"] = (p ~= "" and p) or nil,
    ["data-title"] = title,
  }

  return pandoc.Attr("", classes, build_sorted_kv(attr_map))
end

------------------------------------------------------------
-- Numeric hashtag policy
------------------------------------------------------------

--[[ Return true if the hashtag body is numeric-only (digits only). ]]
function M.is_numeric_tag(body)
  if type(body) ~= "string" then return false end
  return body:match("^%d+$") ~= nil
end

--[[ Decide whether numeric-only body should be auto-processed. ]]
function M.should_link_numeric(body, cfg)
  if type(body) ~= "string" then return false end
  if not body:match("^%d+$") then return false end

  local threshold = cfg and cfg.hashtag_numbers or 0
  if threshold <= 0 then return false end
  return #body >= threshold
end

------------------------------------------------------------
-- URL helpers
------------------------------------------------------------

--[[ URL-encode a string for safe insertion into provider URL templates. ]]
function M.url_encode(s)
  s = tostring(s or "")
  return (s:gsub("([^A-Za-z0-9%-%._~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

--[[ Build the final URL for a provider and tag using a template. ]]
function M.build_url(cfg, provider, tag)
  if not cfg or not cfg.providers then return nil end

  local key = providers.normalize_provider_key(provider) or provider
  local p = cfg.providers[key]
  if not p or not p.url then return nil end

  deps.ensure_html_dependency()

  local encoded = M.url_encode(tag)
  return p.url:gsub("{tag}", function() return encoded end)
end

return M

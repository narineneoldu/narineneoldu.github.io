--[[
# hashtag.meta.lua

Shared metadata parsing helpers for the `hashtag` extension.

Responsibilities:
  - Normalize Pandoc metadata values into Lua primitives
  - Provide consistent semantics for booleans, numbers, strings, and lists
  - Detect explicit "disabled" signals in metadata

This module is intentionally generic and reusable.
It contains NO hashtag-specific business logic.

Exports:
  - is_disabled(v)
  - is_disabled_signal(v)
  - read_bool(v, default)
  - read_number(v, default)
  - read_string_list(v, default)
  - read_nonempty_string(v, default)
  - deep_copy_providers(src)
]]

local M = {}

------------------------------------------------------------
-- Disabled semantics
------------------------------------------------------------

--[[ Return true when metadata value indicates "disabled". ]]
function M.is_disabled(v)
  if v == nil then return true end
  if type(v) == "boolean" then return v == false end
  if type(v) == "table" and v.t == "MetaBool" then return v.c == false end
  local s = pandoc.utils.stringify(v):lower()
  return (s == "" or s == "false" or s == "0" or s == "no" or s == "off")
end

--[[ Return true only when a value explicitly signals "disabled". ]]
function M.is_disabled_signal(v)
  if v == nil then return false end
  if type(v) == "boolean" then return v == false end
  if type(v) == "table" and v.t == "MetaBool" then return v.c == false end
  local s = pandoc.utils.stringify(v):lower()
  return (s == "" or s == "false" or s == "0" or s == "no" or s == "off")
end

------------------------------------------------------------
-- Normalizers
------------------------------------------------------------

--[[ Normalize a metadata value into a boolean. ]]
function M.read_bool(v, default)
  if v == nil then return default end
  if type(v) == "table" and v.t == "MetaBool" then return v.c == true end
  if type(v) == "boolean" then return v end

  local s = pandoc.utils.stringify(v):lower()
  if s == "" or s == "false" or s == "0" or s == "no" or s == "off" then return false end
  if s == "true" or s == "1" or s == "yes" or s == "on" then return true end
  return default
end

--[[ Normalize a metadata value into a numeric threshold. ]]
function M.read_number(v, default)
  if v == nil then return default or 0 end
  if v == true then return 1 end
  if v == false then return 0 end
  if type(v) == "table" and v.t == "MetaBool" then
    return (v.c == true) and 1 or 0
  end

  local s = pandoc.utils.stringify(v):lower()
  if s == "" or s == "false" or s == "0" or s == "no" or s == "off" then return 0 end
  if s == "true" or s == "yes" or s == "on" or s == "1" then return 1 end

  local n = tonumber(s)
  if n and n >= 1 then return math.floor(n) end
  return default or 0
end

--[[ Read a metadata value as a string list (MetaList or scalar). ]]
function M.read_string_list(v, default)
  if v == nil then return default or {} end

  if type(v) == "table" and v.t == "MetaList" then
    local out = {}
    for _, item in ipairs(v.c) do
      local s = pandoc.utils.stringify(item)
      if s ~= "" then out[#out + 1] = s end
    end
    return out
  end

  local s = pandoc.utils.stringify(v)
  if s ~= "" then return { s } end
  return default or {}
end

--[[ Read a metadata value as a non-empty string (or return default). ]]
function M.read_nonempty_string(v, default)
  if v == nil then return default end
  local s = pandoc.utils.stringify(v)
  return (s ~= "" and s) or default
end

------------------------------------------------------------
-- Utilities
------------------------------------------------------------

--[[ Deep-copy provider registry (one level). ]]
function M.deep_copy_providers(src)
  local out = {}
  for k, v in pairs(src or {}) do
    out[k] = { name = v.name, url = v.url }
  end
  return out
end

return M

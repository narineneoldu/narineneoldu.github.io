-- utils_internal_links.lua
-- Mark internal (same-site or relative) links using website.site-url from _quarto.yml.

local M = {}

local SITE_URL = nil

----------------------------------------------------------------------
-- Meta: read site-url from _quarto.yml
----------------------------------------------------------------------

function M.Meta(meta)
  -- Be defensive: meta might be nil or not a table in some weird calls
  if type(meta) ~= "table" then
    return meta
  end

  if meta.website and meta.website["site-url"] then
    local raw = pandoc.utils.stringify(meta.website["site-url"])
    if raw and raw ~= "" then
      -- Normalize: strip trailing slashes
      SITE_URL = raw:gsub("/+$", "")
    end
  end

  return meta
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function is_fragment(href)
  return href and href:sub(1, 1) == "#"
end

local function is_mailto_or_tel(href)
  if not href then return false end
  return href:match("^mailto:") or href:match("^tel:")
end

local function has_scheme(href)
  if not href then return false end
  -- scheme: "http:", "https:", "ftp:", etc.
  return href:match("^%a[%w+.-]*:")
end

local function is_httpish(href)
  if not href then return false end
  return href:match("^https?://") ~= nil
end

local function is_protocol_relative(href)
  if not href then return false end
  return href:match("^//") ~= nil
end

-- Decide if the link should be considered *internal* for styling purposes
local function is_internal_link(href)
  if not href or href == "" then
    return false
  end

  -- Same-page anchors: internal
  if is_fragment(href) then
    return true
  end

  -- mailto/tel: never internal
  if is_mailto_or_tel(href) then
    return false
  end

  -- Protocol-relative URLs: treat as external
  if is_protocol_relative(href) then
    return false
  end

  -- Absolute http/https URLs
  if is_httpish(href) then
    -- Preview URLs on localhost are considered internal
    if href:match("://localhost") then
      return true
    end

    -- If site-url is configured, same-site URLs are internal
    if SITE_URL and href:sub(1, #SITE_URL) == SITE_URL then
      return true
    end

    -- Other http(s) URLs: external
    return false
  end

  -- Anything without a scheme and not protocol-relative is treated as relative → internal
  -- Examples: "foo/bar", "../x", "/y"
  return true
end

----------------------------------------------------------------------
-- Link: add class "internal-link" where appropriate
----------------------------------------------------------------------

function M.Link(el)
  local href = el.target

  if is_internal_link(href) then
    local current = el.attributes["class"]
    if current and current ~= "" then
      el.attributes["class"] = current .. " internal-link"
    else
      el.attributes["class"] = "internal-link"
    end
  end

  return el
end

return M

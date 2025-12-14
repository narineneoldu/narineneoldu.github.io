--[[
# hashtag.providers.lua

Provider registry and provider-key normalization for the `hashtag` extension.

Responsibilities:
  - Provide the default PROVIDERS registry
  - Normalize provider keys coming from user metadata / shortcodes
  - Provide a safe provider slug for CSS/data attributes

Exports:
  - PROVIDERS
  - normalize_provider_key(v)
]]

local M = {}

------------------------------------------------------------
-- Constants
------------------------------------------------------------

M.PROVIDERS = {
  x         = { name = "X Social",        url = "https://x.com/search?q=%23{tag}&src=typed_query&f=live" },
  mastodon  = { name = "Mastodon",        url = "https://mastodon.social/tags/{tag}" },
  bsky      = { name = "Bluesky",         url = "https://bsky.app/search?q=%23{tag}" },
  instagram = { name = "Instagram",       url = "https://www.instagram.com/explore/tags/{tag}/" },
  threads   = { name = "Threads",         url = "https://www.threads.net/tag/{tag}" },
  linkedin  = { name = "LinkedIn",        url = "https://www.linkedin.com/feed/hashtag/{tag}/" },
  tiktok    = { name = "TikTok",          url = "https://www.tiktok.com/tag/{tag}" },
  youtube   = { name = "YouTube",         url = "https://www.youtube.com/hashtag/{tag}" },
  tumblr    = { name = "Tumblr",          url = "https://www.tumblr.com/tagged/{tag}" },
  reddit    = { name = "Reddit (search)", url = "https://www.reddit.com/search/?q=%23{tag}" },
}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

--[[ Trim and stringify a metadata key/value. ]]
local function normalize_key(v)
  local s = pandoc.utils.stringify(v or "")
  return s:match("^%s*(.-)%s*$") -- trim
end

--[[ Sanitize a provider identifier for safe CSS/data attribute usage. ]]
local function sanitize_provider(p)
  p = tostring(p or ""):lower()
  p = p:gsub("[^a-z0-9%-]+", "-")
  p = p:gsub("%-+", "-")
  p = p:gsub("^%-", ""):gsub("%-$", "")
  return p
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------

--[[
Normalize provider keys read from metadata/shortcodes.

Steps:
  - stringify
  - trim
  - lowercase + safe slug (a-z0-9-)

Returns:
  string|nil: Normalized provider key, or nil if empty.
]]
function M.normalize_provider_key(v)
  local s = normalize_key(v)
  local key = sanitize_provider(s)
  if key == "" then return nil end
  return key
end

return M

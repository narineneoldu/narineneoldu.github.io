--[[
  _date_modified/url.lua

  URL normalization for the date-modified extension.

  Isolates the Git remote URL → https://github.com/... mapping so it can be
  unit tested without loading the full filter (which depends on Pandoc/Quarto
  globals, filesystem state, and subprocess execution).

  Supported inputs:
    * git@github.com:user/repo(.git)?
    * git@github-<alias>:user/repo(.git)?    (SSH host alias for GitHub)
    * https://github.com/user/repo(.git)?
    * Any other URL (returned unchanged)
]]

local M = {}

local function trim(s)
  if not s then return s end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Normalize a Git remote URL to a clean https://github.com/... form.
-- @param url string: remote URL
-- @return string|nil: normalized GitHub URL, original string if not GitHub,
--                     or nil if input is empty
function M.normalize_github_url(url)
  if not url or url == "" then return nil end
  url = trim(url)

  -- git@github.com:user/repo(.git)?
  -- Repo name may contain dots (e.g. `narineneoldu.github.io`), so the
  -- capture must be greedy and `.git` suffix optional.
  local user, repo = url:match("^git@github%.com:([^/]+)/(.+)$")
  if user and repo then
    repo = repo:gsub("%.git$", "")
    return string.format("https://github.com/%s/%s", user, repo)
  end

  -- git@github-<alias>:user/repo(.git)?
  -- SSH host aliases (e.g. github-isezen, github-narineneoldu) are a common
  -- pattern for users juggling multiple GitHub identities via ~/.ssh/config.
  -- The host itself is synthetic; user/repo still live on github.com.
  user, repo = url:match("^git@github%-[%w%-_]+:([^/]+)/(.+)$")
  if user and repo then
    repo = repo:gsub("%.git$", "")
    return string.format("https://github.com/%s/%s", user, repo)
  end

  -- https://github.com/user/repo(.git)?
  local path = url:match("^https://github%.com/([^%s]+)")
  if path then
    path = path:gsub("%.git$", "")
    return "https://github.com/" .. path
  end

  return url
end

return M

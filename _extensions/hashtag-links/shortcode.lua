-- shortcodes.lua
-- Hashtag shortcodes (generic + aliases)

local core = require("hashtag_links.core")

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

-- Sanitize provider name so it is safe to use as a CSS class suffix.
-- Keeps only [a-z0-9-], converts others to '-'.
local function sanitize_provider(p)
  p = tostring(p or ""):lower()
  p = p:gsub("[^a-z0-9%-]+", "-")
  p = p:gsub("%-+", "-")
  p = p:gsub("^%-", ""):gsub("%-$", "")
  return p
end

local function hashtag_attr(provider, cfg)
  local p = sanitize_provider(provider)
  local classes = { "hashtag-link", "hashtag-provider" }
  if p ~= "" then
    table.insert(classes, "hashtag-" .. p)
  end

  local kv = {
    { "target", "_blank" },
    { "data-provider", p },
  }

  if cfg and cfg.rel then
    table.insert(kv, { "rel", cfg.rel })
  end

  return pandoc.Attr("", classes, kv)
end

------------------------------------------------------------
-- Core renderer
------------------------------------------------------------

local function render_hashtag(args, meta, provider_override)
  local tag = args[1] and pandoc.utils.stringify(args[1]) or nil
  if not tag or tag == "" then
    return pandoc.Str("")
  end

  -- Do not link numeric hashtags like #2
  if core.is_numeric_tag(tag) then
    return pandoc.Str("#" .. tag)
  end

  -- Prefer cached config set by filter.lua; fallback to reading meta if needed.
  local cfg = core.read_config(meta)
  local provider = provider_override or cfg.provider
  local url = core.build_url(cfg, provider, tag)

  if not url then
    return pandoc.Str("#" .. tag)
  end

  local attr = core.hashtag_attr(provider, cfg)
  local link = pandoc.Link(
    { pandoc.Str("#" .. tag) },
    url,
    "",
    attr
  )

  return link
end

------------------------------------------------------------
-- Generic shortcode
-- Usage: {{< hashtag "x" "SomeTag" >}}
------------------------------------------------------------

function hashtag(args, kwargs, meta)
  local provider = pandoc.utils.stringify(args[1] or "")
  local tag      = args[2]

  if provider == "" or not tag then
    return pandoc.Str("")
  end

  return render_hashtag({ tag }, meta, provider)
end

------------------------------------------------------------
-- Aliases
------------------------------------------------------------

function x(args, kwargs, meta)
  return render_hashtag(args, meta, "x")
end

function mastodon(args, kwargs, meta)
  return render_hashtag(args, meta, "mastodon")
end

function bsky(args, kwargs, meta)
  return render_hashtag(args, meta, "bsky")
end

function instagram(args, kwargs, meta)
  return render_hashtag(args, meta, "instagram")
end

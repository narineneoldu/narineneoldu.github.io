-- shortcode.lua
-- Hashtag shortcodes (generic + aliases)

local core = require("_hashtag.core")

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

  if cfg.linkify then
    local url = core.build_url(cfg, provider, tag)
    if not url then
      return pandoc.Str("#" .. tag)
    end

    local attr = core.hashtag_link_attr(provider, cfg)
    return pandoc.Link(
      { pandoc.Str("#" .. tag) },
      url,
      "",
      attr
    )
  else
    local attr = core.hashtag_span_attr(provider, cfg)
    return pandoc.Span({ pandoc.Str("#" .. tag) }, attr)
  end
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

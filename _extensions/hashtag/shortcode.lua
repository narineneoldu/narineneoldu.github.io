--[[
# shortcode.lua

Hashtag shortcodes for the `hashtag` Quarto extension.

This file implements user-facing shortcodes that explicitly render hashtags
as either links or spans, independent of the automatic inline filter logic.

Important design notes:
- Shortcodes ALWAYS honor the `linkify` setting.
- Numeric hashtags are NOT restricted here; if a user explicitly writes a
  shortcode, it is assumed intentional.
- No auto-detection or skip-class logic is applied in this layer.

Supported forms:
  {{< htag "x" "SomeTag" >}}      -- Explicit provider
  {{< htag "SomeTag" >}}          -- Uses default provider from metadata
  {{< x "SomeTag" >}}             -- Provider alias
  {{< threads "SomeTag" >}}
  {{< linkedin "SomeTag" >}}
  {{< tiktok "SomeTag" >}}
  {{< youtube "SomeTag" >}}
  {{< tumblr "SomeTag" >}}
  {{< reddit "SomeTag" >}}
  {{< mastodon "SomeTag" >}}
  {{< bsky "SomeTag" >}}
  {{< instagram "SomeTag" >}}
]]

local core = require("_hashtag.core")

--[[
Render a single hashtag via shortcode.

This function is the shared implementation used by the generic `htag` shortcode
and all provider aliases.

Parameters:
  args (table)
    Positional shortcode arguments. args[1] is expected to be the tag value.
  meta (Meta)
    Document metadata (used to resolve config).
  provider_override (string|nil)
    Provider name to force (e.g. "x", "mastodon").

Returns:
  pandoc.Inline
    A Link or Span inline element, or an empty Str.
]]
local function render_hashtag(args, meta, provider_override)
  local tag = args[1] and pandoc.utils.stringify(args[1]) or nil
  if not tag or tag == "" then
    return pandoc.Str("")
  end

  -- Read configuration from document metadata.
  -- Shortcodes intentionally re-read config and do not rely on filter cache.
  local cfg = core.read_config(meta)

  local provider = provider_override or cfg.default_provider or ""
  provider = core.normalize_provider_key(provider) or provider
  if provider == "" then return pandoc.Str("#" .. tag) end

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

--[[
Generic hashtag shortcode.

Usage:
  {{< htag "TagName" >}}            -- uses default provider from metadata
  {{< htag "provider" "TagName" >}} -- explicit provider
]]
function htag(args, kwargs, meta)
  -- Read config so we can use the default provider when not passed explicitly
  local cfg = core.read_config(meta)

  local a1 = args[1]
  local a2 = args[2]

  -- One-argument form: {{< htag "Test" >}}
  if a1 ~= nil and a2 == nil then
    local tag = pandoc.utils.stringify(a1)
    if tag == "" then
      return pandoc.Str("")
    end

    local provider = cfg.default_provider or ""
    if provider == "" then
      -- No provider configured; fail safely by outputting plain text
      return pandoc.Str("#" .. tag)
    end

    return render_hashtag({ a1 }, meta, provider)
  end

  -- Two-argument form: {{< htag "x" "Test" >}}
  local provider = core.normalize_provider_key(a1) or
    pandoc.utils.stringify(a1 or "")
  local tag = a2

  if provider == "" or not tag then
    return pandoc.Str("")
  end

  return render_hashtag({ tag }, meta, provider)
end

------------------------------------------------------------
-- Aliases
------------------------------------------------------------

--[[ Alias shortcode for provider "x". ]]
function x(args, kwargs, meta)
  return render_hashtag(args, meta, "x")
end

--[[ Alias shortcode for provider "mastodon". ]]
function mastodon(args, kwargs, meta)
  return render_hashtag(args, meta, "mastodon")
end

--[[ Alias shortcode for provider "bsky". ]]
function bsky(args, kwargs, meta)
  return render_hashtag(args, meta, "bsky")
end

--[[ Alias shortcode for provider "instagram". ]]
function instagram(args, kwargs, meta)
  return render_hashtag(args, meta, "instagram")
end

--[[ Alias shortcode for provider "threads". ]]
function threads(args, kwargs, meta)
  return render_hashtag(args, meta, "threads")
end

--[[ Alias shortcode for provider "linkedin". ]]
function linkedin(args, kwargs, meta)
  return render_hashtag(args, meta, "linkedin")
end

--[[ Alias shortcode for provider "tiktok". ]]
function tiktok(args, kwargs, meta)
  return render_hashtag(args, meta, "tiktok")
end

--[[ Alias shortcode for provider "youtube". ]]
function youtube(args, kwargs, meta)
  return render_hashtag(args, meta, "youtube")
end

--[[ Alias shortcode for provider "tumblr". ]]
function tumblr(args, kwargs, meta)
  return render_hashtag(args, meta, "tumblr")
end

--[[ Alias shortcode for provider "reddit". ]]
function reddit(args, kwargs, meta)
  return render_hashtag(args, meta, "reddit")
end

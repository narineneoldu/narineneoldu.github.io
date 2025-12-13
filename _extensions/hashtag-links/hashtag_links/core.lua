-- hashtag-links.lua
-- Shared helpers for hashtag-links extension

local M = {}

local deps = require("hashtag_links.deps")

local DEFAULT_PROVIDERS = {
  x            = { name = "X Social",         url = "https://x.com/search?q=%23{tag}&src=typed_query&f=live" },
  mastodon     = { name = "Mastadon Social",  url = "https://mastodon.social/tags/{tag}" },
  bsky         = { name = "Bluesky Social",   url = "https://bsky.app/search?q=%23{tag}" },
  instagram    = { name = "Instagram Social", url = "https://www.instagram.com/explore/tags/{tag}/" }
}


function M.read_config(meta)
  local cfg = {
    auto          = false,
    auto_provider = nil,
    providers     = DEFAULT_PROVIDERS,
    rel           = "noopener noreferrer nofollow",
  }

  -- Prefer Quarto's document metadata when available.
  -- Shortcode metadata can be incomplete (e.g., keys with false/empty values may be dropped).
  local m = meta
  if quarto and quarto.doc and quarto.doc.meta then
    m = quarto.doc.meta
  end

  local block = m and m["hashtag-links"]
  if type(block) ~= "table" then
    return cfg
  end

  -- Read rel (string => set, ""/false => disable)
  local relv = block["rel"]

  -- MetaBool false => disable
  if type(relv) == "table" and relv.t == "MetaBool" and relv.c == false then
    cfg.rel = nil
  elseif relv ~= nil then
    local rels = pandoc.utils.stringify(relv)
    if rels == "" or rels == "false" or rels == "False" or rels == "0" then
      cfg.rel = nil
    else
      cfg.rel = rels
    end
  end

  -- Load providers overrides (if present)
  if type(block["providers"]) == "table" then
    cfg.providers = {}
    for k, v in pairs(block["providers"]) do
      cfg.providers[k] = { url = pandoc.utils.stringify(v["url"]) }
    end
  end

  -- Read auto-provider (nil/false/"" => disabled, string => provider name)
  local ap = block["auto-provider"]

  if ap == nil then
    return cfg
  end

  -- MetaBool false => disabled
  if type(ap) == "table" and ap.t == "MetaBool" then
    if ap.c == false then
      return cfg
    end
  end

  local ap_str = pandoc.utils.stringify(ap)
  if ap_str == "" or ap_str == "false" or ap_str == "False" or ap_str == "0" then
    return cfg
  end

  -- Provider validation
  if not cfg.providers[ap_str] then
    io.stderr:write(
      "[hashtag-links] Warning: auto-provider '" .. ap_str ..
      "' not found in providers; auto scan disabled.\n"
    )
    return cfg
  end

  cfg.auto = true
  cfg.auto_provider = ap_str

  return cfg
end

------------------------------------------------------------
-- Shared attribute builder (single source of truth)
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

------------------------------------------------------------
-- Deterministic attribute builder
------------------------------------------------------------

-- Build pandoc attribute list from a key-value table.
-- Keys are sorted alphabetically to ensure deterministic output.
-- Nil values are ignored.
local function build_sorted_kv(tbl)
  local keys = {}

  for k, v in pairs(tbl) do
    if v ~= nil then
      table.insert(keys, k)
    end
  end

  table.sort(keys)

  local out = {}
  for _, k in ipairs(keys) do
    table.insert(out, { k, tostring(tbl[k]) })
  end

  return out
end

--- Build Pandoc Attr for hashtag links.
-- Attribute order is FIXED and deterministic:
--   1) target
--   2) rel (if any)
--   3) data-provider
function M.hashtag_attr(provider, cfg)
  local p = sanitize_provider(provider)

  -- Fixed class order (classes are NOT sorted on purpose)
  local classes = {
    "hashtag-link",
    "hashtag-provider",
  }

  if p ~= "" then
    table.insert(classes, "hashtag-" .. p)
  end

  -- Attributes as a map
  local attr_map = {
    target = "_blank",
    rel = (cfg and cfg.rel) or nil,
    ["data-provider"] = p,
    ["data-title"] = cfg.providers[p].name or nil,
  }

  return pandoc.Attr(
    "",
    classes,
    build_sorted_kv(attr_map)
  )
end

function M.is_numeric_tag(body)
  if type(body) ~= "string" then return false end
  return body:match("^%d") ~= nil
end

function M.build_url(cfg, provider, tag)
  local p = cfg.providers[provider]
  if not p or not p.url then
    return nil
  end
  deps.ensure_html_dependency()
  return p.url:gsub("{tag}", tag)
end

M.HASHTAG_PATTERN = "(#([%wçğıİöşüÇĞİÖŞÜ_]+))"

return M

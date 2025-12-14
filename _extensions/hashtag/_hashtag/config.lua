local M = {}

local deps      = require("_hashtag.deps")
local providers = require("_hashtag.providers")
local meta      = require("_hashtag.meta")

------------------------------------------------------------
-- Defaults
------------------------------------------------------------

M.DEFAULT_CFG = {
  auto_scan        = false,
  linkify          = true,
  default_provider = "x",
  target           = "_blank",
  title            = true,
  pattern          = nil,
  skip_classes     = {},
  providers        = providers.PROVIDERS,
  icons            = true,
  rel              = "noopener noreferrer nofollow",
  hashtag_numbers  = 0,
}

------------------------------------------------------------
-- Public API
------------------------------------------------------------

function M.read_config(meta_in)
  local cfg = {
    auto_scan        = M.DEFAULT_CFG.auto_scan,
    linkify          = M.DEFAULT_CFG.linkify,
    default_provider = M.DEFAULT_CFG.default_provider,
    target           = M.DEFAULT_CFG.target,
    title            = M.DEFAULT_CFG.title,
    pattern          = M.DEFAULT_CFG.pattern,
    skip_classes     = {},
    providers        = M.DEFAULT_CFG.providers,
    icons            = M.DEFAULT_CFG.icons,
    rel              = M.DEFAULT_CFG.rel,
    hashtag_numbers  = M.DEFAULT_CFG.hashtag_numbers,
  }

  local m = meta_in
  if quarto and quarto.doc and quarto.doc.meta then
    m = quarto.doc.meta
  end

  local block = m and m["hashtag"]
  -- Quarto project defaults may arrive under `metadata:`
  if type(block) ~= "table" and m and type(m["metadata"]) == "table" then
    block = m["metadata"]["hashtag"]
  end

  if type(block) ~= "table" then
    return cfg
  end

  cfg.linkify   = meta.read_bool(block["linkify"], cfg.linkify)
  cfg.auto_scan = meta.read_bool(block["auto-scan"], cfg.auto_scan)

  local pv = block["default-provider"]
  if pv ~= nil and not meta.is_disabled(pv) then
    local key = providers.normalize_provider_key(pv)
    if key then cfg.default_provider = key end
  end

  local tv = block["target"]
  if tv ~= nil then
    cfg.target = meta.is_disabled_signal(tv) and nil or pandoc.utils.stringify(tv)
  end

  cfg.title        = meta.read_bool(block["title"], cfg.title)
  cfg.pattern      = meta.read_nonempty_string(block["pattern"], cfg.pattern)
  cfg.skip_classes = meta.read_string_list(block["skip-classes"], cfg.skip_classes)

  cfg.icons = meta.read_bool(block["icons"], cfg.icons)
  if cfg.icons then
    deps.ensure_html_bi_dependency()
  end

  cfg.hashtag_numbers = meta.read_number(block["hashtag-numbers"], 0)

  local relv = block["rel"]
  if relv ~= nil then
    cfg.rel = meta.is_disabled_signal(relv) and nil or pandoc.utils.stringify(relv)
  end

  cfg.providers = meta.deep_copy_providers(providers.PROVIDERS)

  if cfg.default_provider and not cfg.providers[cfg.default_provider] then
    io.stderr:write("[hashtag] Warning: default-provider '" .. cfg.default_provider ..
      "' not found in providers; hashtags will render as plain text.\n")
  end

  if type(block["providers"]) == "table" then
    for k, v in pairs(block["providers"]) do
      local key = providers.normalize_provider_key(k)
      if key then
        local url  = v and v["url"]  and pandoc.utils.stringify(v["url"])
                  or (cfg.providers[key] and cfg.providers[key].url)

        local name = v and v["name"] and pandoc.utils.stringify(v["name"])
                  or (cfg.providers[key] and cfg.providers[key].name)

        cfg.providers[key] = { url = url, name = name }
      end
    end
  end

  return cfg
end

return M

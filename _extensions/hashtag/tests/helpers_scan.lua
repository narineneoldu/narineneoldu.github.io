-- tests/helpers_scan.lua
-- Shared setup for scan.lua tests: deterministic monkeypatch for _hashtag.core.

local H = require("tests.helpers")

local M = {}

function M.cfg_default()
  return {
    linkify = true,
    default_provider = "x",
    hashtag_numbers = 0,
  }
end

function M.cfg_span_only()
  return {
    linkify = false,
    default_provider = "x",
    title = false,
    providers = { x = { name = "X", url = "https://example.test/{tag}" } },
    hashtag_numbers = 0,
  }
end

-- Flatten any inline/container list into plain text
function M.flatten_text(inlines)
  local out = {}
  local function emit(el)
    if el.t == "Str" then
      out[#out + 1] = el.text or ""
    elseif el.t == "Space" then
      out[#out + 1] = " "
    elseif el.t == "Code" or el.t == "CodeSpan" then
      out[#out + 1] = el.text or ""
    elseif el.t == "Span" or el.t == "Link" then
      for _, c in ipairs(el.content or {}) do emit(c) end
    elseif el.content then
      for _, c in ipairs(el.content or {}) do emit(c) end
    end
  end

  for _, el in ipairs(inlines or {}) do emit(el) end
  return table.concat(out)
end

-- Return true if an inline is a hashtag produced by the extension (Span or Link)
function M.is_hashtag_inline(el)
  if not el then return false end
  if el.t ~= "Span" and el.t ~= "Link" then return false end
  if not el.attr or not el.attr.classes then return false end
  for _, c in ipairs(el.attr.classes) do
    if c == "hashtag" then return true end
  end
  return false
end

-- True if any hashtag inline exists anywhere (recursive)
function M.any_converted(inlines)
  local function walk(el)
    if M.is_hashtag_inline(el) then return true end
    for _, c in ipairs(el.content or {}) do
      if walk(c) then return true end
    end
    return false
  end

  for _, el in ipairs(inlines or {}) do
    if walk(el) then return true end
  end
  return false
end

-- Count hashtag inlines anywhere (recursive)
function M.count_converted(inlines)
  local n = 0
  local function walk(el)
    if M.is_hashtag_inline(el) then n = n + 1 end
    for _, c in ipairs(el.content or {}) do walk(c) end
  end
  for _, el in ipairs(inlines or {}) do walk(el) end
  return n
end

function M.monkeypatch_core_for_scan()
  local core = require("_hashtag.core")

  -- Deterministic attrs/urls for unit tests (no deps side effects)
  core.hashtag_link_attr = function(provider, _cfg)
    -- Must include "hashtag" so scan.lua can detect already-emitted nodes
    return pandoc.Attr("", { "hashtag", "hashtag-provider", "hashtag-" .. tostring(provider) }, {})
  end

  core.hashtag_span_attr = function(provider, _cfg)
    -- Must include "hashtag" so scan.lua can detect already-emitted nodes
    return pandoc.Attr("", { "hashtag", "hashtag-provider", "hashtag-" .. tostring(provider) }, {})
  end
  core.build_url = function(_cfg, provider, tag)
    return "https://example.test/" .. provider .. "/" .. tag
  end

  -- Numeric helpers: keep deterministic and explicit
  core.is_numeric_tag = function(body)
    return type(body) == "string" and body:match("^%d+$") ~= nil
  end
  core.should_link_numeric = function(body, cfg)
    local threshold = (cfg and cfg.hashtag_numbers) or 0
    if threshold <= 0 then return false end
    return #body >= threshold
  end

  return core
end

M.Str = H.Str
M.Span = H.Span
M.texts = H.texts

return M

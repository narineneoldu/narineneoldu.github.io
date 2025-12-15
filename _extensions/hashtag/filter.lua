--[[
# filter.lua

Pandoc filter entry point for the "hashtag" Quarto extension.

Responsibilities:
  - Gate on HTML-like formats only
  - Read extension configuration via `_hashtag.core`
  - Build skip-class lookup set
  - Traverse blocks (Para/Plain/Div) and delegate inline processing to `_hashtag.scan`

This file intentionally avoids embedding hashtag scanning logic.
All hashtag scanning and UTF-8 character handling live in:
  - `_hashtag.scan`
  - `_hashtag.utf8`
]]

local core = require("_hashtag.core")
local scan = require("_hashtag.scan")

------------------------------------------------------------
-- Helpers: format + class handling
------------------------------------------------------------

--[[ Return true if the current target format is HTML-ish. ]]
local function is_html()
  -- FORMAT is a Pandoc global; match "html" for html, html5, revealjs, etc.
  return (FORMAT and FORMAT:match("html") ~= nil) or false
end

--[[ Convert a list of class names into a lookup set. ]]
local function class_set(list)
  local set = {}
  for _, c in ipairs(list or {}) do set[c] = true end
  return set
end

--[[ Return true if `attr.classes` contains any class in `skip_set`. ]]
local function has_any_class(attr, skip_set)
  if not attr or not attr.classes then return false end
  for _, c in ipairs(attr.classes) do
    if skip_set[c] then return true end
  end
  return false
end

------------------------------------------------------------
-- Block handling
------------------------------------------------------------

--[[ Build a new Para/Plain block by processing its inline content. ]]
local function handle_inlines_block(block, ctor, cfg, skip_set, skip)
  local new_inlines = scan.process_inlines(block.content, cfg, skip_set, skip)
  return ctor(new_inlines)
end

--[[ Map block types that carry inline content to their constructors. ]]
local INLINE_BLOCK_CTORS = {
  Para  = pandoc.Para,
  Plain = pandoc.Plain,
}

--[[
Process block-level elements and propagate skip regions.

Parameters:
  block (pandoc.Block): The block element to process.
  cfg (table): Parsed extension configuration.
  skip_set (table): Lookup table of classes that disable hashtag processing.
  skip (boolean): Whether the parent container disabled processing.

Returns:
  pandoc.Block|nil: The transformed block, or nil to leave unchanged.
]]
local function handle_block(block, cfg, skip_set, skip)
  local ctor = INLINE_BLOCK_CTORS[block.t]
  if ctor then
    return handle_inlines_block(block, ctor, cfg, skip_set, skip)
  end

  if block.t == "Div" then
    local skip_here = skip or has_any_class(block.attr, skip_set)

    -- Walk Div children manually (avoid List:walk in emulated runtimes)
    local new_content = pandoc.List:new()
    for _, child in ipairs(block.content) do
      local replaced = handle_block(child, cfg, skip_set, skip_here)
      new_content:insert(replaced or child)
    end

    block.content = new_content
    return block
  end

  return nil
end

------------------------------------------------------------
-- Pandoc entry point
------------------------------------------------------------

--[[
Pandoc filter entry point.

Returns:
  pandoc.Pandoc: The transformed document (or original if disabled).
]]
function Pandoc(doc)
  -- Do not mutate non-HTML outputs (PDF/Docx/LaTeX)
  if not is_html() then return doc end

  local cfg = core.read_config(doc.meta)
  if not cfg.auto_scan then return doc end

  local skip_set = class_set(cfg.skip_classes)

  doc.blocks = doc.blocks:walk({
    Para  = function(b) return handle_block(b, cfg, skip_set, false) end,
    Plain = function(b) return handle_block(b, cfg, skip_set, false) end,
    Div   = function(b) return handle_block(b, cfg, skip_set, false) end,
  })

  return doc
end

return {
  { Pandoc = Pandoc }
}

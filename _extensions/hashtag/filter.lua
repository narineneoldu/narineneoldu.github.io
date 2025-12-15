--[[
# filter.lua

Automatic hashtag conversion filter for the "hashtag" Quarto extension.

Responsibilities:
  • Scan inline text nodes for hashtag patterns
  • Convert hashtags into Link or Span nodes depending on configuration
  • Respect numeric hashtag rules (hashtag-numbers)
  • Respect skip-classes for Div and Span containers
  • Avoid processing inside Code, CodeSpan, and existing Links

This file delegates all configuration, URL building, attribute construction,
and pattern definitions to `_hashtag.core`.
]]

local core = require("_hashtag.core")

------------------------------------------------------------
-- Helpers: class handling
------------------------------------------------------------

--[[ Return true if the current target format is HTML. ]]
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
-- Inline processor
------------------------------------------------------------

--[[
Process a list of inline elements, converting hashtags when allowed.

This function:
  • Walks inline nodes recursively
  • Converts hashtag text into Link or Span nodes
  • Respects skip regions inherited from parent containers
  • Leaves content untouched when `skip == true`

Parameters:
  inlines (pandoc.List): Inline elements to process.
  cfg (table): Parsed extension configuration from `_hashtag.core.read_config`.
  skip_set (table): Lookup table of classes that disable hashtag processing.
  skip (boolean): Whether processing is disabled due to a parent container.

Returns:
  pandoc.List: New list of inline elements with hashtag transformations applied.
]]
local function process_inlines(inlines, cfg, skip_set, skip)
  local out = pandoc.List:new()

  -- If this region is marked as skipped, return inlines unchanged
  if skip then
    for _, el in ipairs(inlines) do out:insert(el) end
    return out
  end

  -- Fast path: if no Str contains '#', return original inlines
  local has_hash = false
  for _, el in ipairs(inlines) do
    if el.t == "Str" and el.text and el.text:find("#", 1, true) then
      has_hash = true
      break
    end
  end

  if not has_hash then
    for _, el in ipairs(inlines) do out:insert(el) end
    return out
  end

  local linkify
  local pattern
  local word_char_pat
  local provider
  local attr

  local function ensure_invariants()
    if pattern then return end -- already initialized

    linkify  = cfg.linkify == true
    pattern = core.get_pattern(cfg)
    word_char_pat = core.get_boundary_char_pattern(cfg)
    provider = cfg.default_provider or "x"

    attr = linkify
      and core.hashtag_link_attr(provider, cfg)
      or  core.hashtag_span_attr(provider, cfg)
  end

  --[[ Rebuild an inline container by recursively processing its content. ]]
  local function rebuild_container(el, new_content)
    if el.t == "Span" then
      return pandoc.Span(new_content, el.attr)
    elseif el.t == "Emph" then
      return pandoc.Emph(new_content)
    elseif el.t == "Strong" then
      return pandoc.Strong(new_content)
    elseif el.t == "Quoted" then
      return pandoc.Quoted(el.quotetype, new_content)
    end
    return el
  end

  --[[ Emit a hashtag token as Link/Span or plain text (numeric policy applied outside). ]]
  local function emit_hashtag(full, body)
    ensure_invariants()
    if linkify then
      local url = core.build_url(cfg, provider, body)
      if url then
        out:insert(pandoc.Link({ pandoc.Str(full) }, url, "", attr))
      else
        -- Provider missing or url template missing => fail safe
        out:insert(pandoc.Str(full))
      end
    else
      out:insert(pandoc.Span({ pandoc.Str(full) }, attr))
    end
  end

  --[[ Return true if the character should be treated as a hashtag "word" char. ]]
  local function is_word_char(ch)
    return ch and word_char_pat and ch:match(word_char_pat) ~= nil
  end

  --[[ Return the last character of a Str node's text, or nil. ]]
  local function last_char_of_str(el)
    if not el or el.t ~= "Str" then return nil end
    local t = el.text or ""
    if t == "" then return nil end
    return t:sub(-1)
  end

  --[[ Return true if the previous output inline ends with a word character. ]]
  local function prev_inline_ends_with_word(out_list)
    local prev_el = out_list[#out_list]
    local ch = last_char_of_str(prev_el)
    return is_word_char(ch)
  end

  ----------------------------------------------------------
  -- Main walk
  ----------------------------------------------------------

  for _, el in ipairs(inlines) do
    -- Never touch code or existing links
    if el.t == "Link" or el.t == "Code" or el.t == "CodeSpan" then
      out:insert(el)

    elseif el.t == "Str" then
      local text = el.text or ""

      -- Fast path: no hashtag character
      if not text:find("#", 1, true) then
        out:insert(el)
      else
        local i = 1
        while i <= #text do
          -- Capture:
          --   full = "#Tag"
          --   body = "Tag"
          ensure_invariants()
          local s, e, full, body = text:find(pattern, i)

          if not s then
            out:insert(pandoc.Str(text:sub(i)))
            break
          end

          -- Reject matches that start in the middle of a word (e.g., "abc#Tag").
          -- If rejected, we MUST emit the text up to and including '#', otherwise we drop "abc#".
          local prev = nil
          if s > 1 then
            prev = text:sub(s - 1, s - 1)
          else
            -- Match begins at start of this Str; check the previous inline for a trailing word char.
            if prev_inline_ends_with_word(out) then
              prev = "x" -- any non-nil marker; is_word_char check below uses the char
              -- But we need the actual trailing character to be correct:
              prev = last_char_of_str(out[#out])
            end
          end

          if prev and is_word_char(prev) then
            out:insert(pandoc.Str(text:sub(i, s))) -- includes the '#'
            i = s + 1
          else
            if s > i then
              out:insert(pandoc.Str(text:sub(i, s - 1)))
            end

            if core.is_numeric_tag(body) and not core.should_link_numeric(body, cfg) then
              out:insert(pandoc.Str(full))
            else
              emit_hashtag(full, body)
            end

            i = e + 1
          end
        end
      end

    elseif el.t == "Span" or el.t == "Emph" or el.t == "Strong" or el.t == "Quoted" then
      -- Containers may introduce or inherit skip regions
      local child_skip = skip
      if el.t == "Span" then
        child_skip = child_skip or has_any_class(el.attr, skip_set)
      end

      local new_content = process_inlines(el.content, cfg, skip_set, child_skip)
      out:insert(rebuild_container(el, new_content))

    else
      out:insert(el)
    end
  end

  return out
end

------------------------------------------------------------
-- Helpers: block construction
------------------------------------------------------------

--[[ Build a new Para/Plain block by processing its inline content. ]]
local function handle_inlines_block(block, ctor, cfg, skip_set, skip)
  return ctor(process_inlines(block.content, cfg, skip_set, skip))
end

------------------------------------------------------------
-- Block handler
------------------------------------------------------------

--[[ Map block types that carry inline content to their constructors. ]]
local INLINE_BLOCK_CTORS = {
  Para  = pandoc.Para,
  Plain = pandoc.Plain,
}

--[[
Process block-level elements and propagate skip regions.

This function:
  • Applies inline processing to Para and Plain blocks
  • Recursively walks Div blocks
  • Activates skip mode when a Div has a skip-class

Parameters:
  block (pandoc.Block): The block element to process.
  cfg (table): Parsed extension configuration.
  skip_set (table): Lookup table of classes that disable hashtag processing.
  skip (boolean): Whether the parent container disabled processing.

Returns:
  pandoc.Block|nil: The transformed block, or nil to leave unchanged.
]]
local function handle_block(block, cfg, skip_set, skip)
  -- Handle inline-carrying blocks (Para/Plain) via a single table lookup
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

This function:
  • Reads extension configuration
  • Builds the skip-class lookup table
  • Applies block-level traversal only when auto-scan is enabled

Parameters:
  doc (pandoc.Pandoc): The Pandoc document.

Returns:
  pandoc.Pandoc: The transformed document.
]]
--[[ Pandoc filter entry point. ]]
function Pandoc(doc)
  -- Do not mutate non-HTML outputs (PDF/Docx/LaTeX) unless explicitly desired
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

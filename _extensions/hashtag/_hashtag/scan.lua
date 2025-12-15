--[[
# _hashtag/scan.lua

Hashtag scanning and inline transformation logic for the `hashtag` Quarto extension.

Responsibilities:
  - Scan pandoc inline Str nodes for hashtag tokens starting with '#'
  - Enforce start-boundary and stop-character rules
  - Avoid processing inside Link/Code/CodeSpan
  - Respect skip regions inherited from Div/Span containers
  - Avoid matching hashtag-like sequences in URL contexts
  - Delegate URL building and attribute construction to `_hashtag.core`
  - Operate on UTF-8 characters for boundary and stop checks

Exports:
  - process_inlines(inlines, cfg, skip_set, skip) -> pandoc.List
]]

local core = require("_hashtag.core")
local utf8 = require("_hashtag.utf8")

------------------------------------------------------------
-- Boundary/Stop sets (tuned for real-world text)
------------------------------------------------------------

--[[ Build a set table from a list of string keys. ]]
local function make_set(keys)
  local s = {}
  for _, k in ipairs(keys or {}) do s[k] = true end
  return s
end

--[[ Shallow copy of a set table. ]]
local function copy_set(src)
  local dst = {}
  for k, v in pairs(src or {}) do dst[k] = v end
  return dst
end

-- Common separators/punctuation typically surrounding hashtags in prose.
local COMMON_BOUNDARIES = make_set({
  " ", "\t", "\n", "\r",
  "(", ")", "[", "]", "{", "}",
  "'", '"', "`", "’",
  "!", "?", ".", ",", ";", ":",
  "-", "+", "*", "=", "/", "\\",
})

-- Characters allowed before '#' to start a hashtag.
-- nil (start of string / start of inline) is also allowed by logic.
local START_BOUNDARY = COMMON_BOUNDARIES

-- Characters that terminate a hashtag body.
-- Includes angle brackets and pipe which often appear in HTML-ish or templated text.
local STOP_CHAR = (function()
  local s = copy_set(COMMON_BOUNDARIES)
  s["<"] = true
  s[">"] = true
  s["|"] = true
  return s
end)()

------------------------------------------------------------
-- URL context detection
------------------------------------------------------------

--[[
Heuristic: determine whether the '#' appears in a URL-like context.

We only inspect up to ~64 bytes before '#', optionally including the previous inline's tail.
This is intentionally cheap and conservative.

Parameters:
  text (string): current Str text
  hash_pos (number): byte index of '#'
  out_list (pandoc.List): already-emitted inlines (used to peek previous Str tail)

Returns:
  boolean: true if URL-like context is detected
]]
local function is_url_context(text, hash_pos, out_list)
  local start = math.max(1, hash_pos - 64)
  local prev = text:sub(start, hash_pos - 1)

  -- Include previous inline tail if hashtag is at the start of this Str
  if hash_pos == 1 and out_list[#out_list] and out_list[#out_list].t == "Str" then
    local t = out_list[#out_list].text or ""
    prev = t:sub(math.max(1, #t - 64)) .. prev
  end

  -- Minimal URL signals
  if prev:find("://", 1, true) then return true end
  if prev:find("www.", 1, true) then return true end

  return false
end

------------------------------------------------------------
-- Inline container rebuild
------------------------------------------------------------

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

------------------------------------------------------------
-- Hashtag emission helpers
------------------------------------------------------------

--[[
Create an emitter closure that inserts Link/Span hashtags into `out`.

Parameters:
  out (pandoc.List): output list to insert into
  cfg (table): normalized configuration

Returns:
  function(full, body): emits hashtag (or falls back to plain text)
]]
local function make_emitter(out, cfg)
  local linkify = nil
  local provider = nil
  local attr = nil

  local function ensure_invariants()
    if attr then return end
    linkify  = cfg.linkify == true
    provider = cfg.default_provider or "x"
    attr = linkify and core.hashtag_link_attr(provider, cfg)
                 or  core.hashtag_span_attr(provider, cfg)
  end

  local function emit_hashtag(full, body)
    ensure_invariants()

    if linkify then
      local url = core.build_url(cfg, provider, body)
      if url then
        out:insert(pandoc.Link({ pandoc.Str(full) }, url, "", attr))
      else
        -- Provider missing or URL template missing => fail safe
        out:insert(pandoc.Str(full))
      end
    else
      out:insert(pandoc.Span({ pandoc.Str(full) }, attr))
    end
  end

  return function(full, body)
    -- Numeric policy remains filter-only; apply here consistently.
    if core.is_numeric_tag(body) and not core.should_link_numeric(body, cfg) then
      out:insert(pandoc.Str(full))
    else
      emit_hashtag(full, body)
    end
  end
end

------------------------------------------------------------
-- Str scanning (core logic)
------------------------------------------------------------

--[[
Get the UTF-8 character immediately preceding byte index `hash_pos` in `text`,
or from the previous emitted Str in `out` when hash_pos == 1.

Parameters:
  text (string): current Str text
  hash_pos (number): byte index of '#'
  out (pandoc.List): emitted output list

Returns:
  string|nil: previous UTF-8 character substring, or nil if none
]]
local function get_prev_char(text, hash_pos, out)
  if hash_pos > 1 then
    return utf8.char_before_byte(text, hash_pos - 1)
  end

  -- hash_pos == 1: look at previous emitted Str
  local prev_el = out[#out]
  if prev_el and prev_el.t == "Str" then
    return utf8.last_char(prev_el.text or "")
  end

  return nil
end

--[[
Scan a Str text and append transformed inlines to out.

Rules:
  - A candidate starts at '#' and must have at least 1 char after '#'
  - Start boundary: previous character must be nil or in START_BOUNDARY
  - URL context: skip if URL context detected
  - Body extends until STOP_CHAR (UTF-8 aware)
  - Emoji: ignored by design (we do not treat emoji specially)
  - Underscore: remains part of the body unless included as STOP_CHAR (it is not)

Parameters:
  text (string): Str node text
  out (pandoc.List): output list
  cfg (table): config
  emit_token (function): function(full, body) that emits hashtag/link/span
]]
local function scan_str_text(text, out, cfg, emit_token)
  local i = 1
  while i <= #text do
    local s = text:find("#", i, true)
    if not s then
      local rest = text:sub(i)
      if rest ~= "" then out:insert(pandoc.Str(rest)) end
      break
    end

    -- Emit text before '#'
    if s > i then
      local before = text:sub(i, s - 1)
      if before ~= "" then out:insert(pandoc.Str(before)) end
    end

    -- Start boundary check
    local prev = get_prev_char(text, s, out)
    -- prev == nil => allowed (start of text or start of inline)
    if prev ~= nil and not START_BOUNDARY[prev] then
      out:insert(pandoc.Str("#"))
      i = s + 1
      goto continue
    end

    -- URL context check (skip processing if URL-ish)
    if is_url_context(text, s, out) then
      out:insert(pandoc.Str("#"))
      i = s + 1
      goto continue
    end

    -- Read body (UTF-8 aware stop chars)
    local j = s + 1
    while j <= #text do
      local ch, nextj = utf8.next_char(text, j)
      if not ch then break end
      if STOP_CHAR[ch] then break end
      j = nextj
    end

    local body = text:sub(s + 1, j - 1)

    -- Require at least 1 character after '#'
    if body == "" then
      out:insert(pandoc.Str("#"))
      i = s + 1
      goto continue
    end

    local full = "#" .. body
    emit_token(full, body)
    i = j

    ::continue::
  end
end

------------------------------------------------------------
-- Public API: process_inlines
------------------------------------------------------------

--[[
Process a list of inline elements, converting hashtags when allowed.

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

  -- Skip region: return inlines unchanged
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

  local emit_token = make_emitter(out, cfg)

  for _, el in ipairs(inlines) do
    -- Never touch code or existing links
    if el.t == "Link" or el.t == "Code" or el.t == "CodeSpan" then
      out:insert(el)

    elseif el.t == "Str" then
      local text = el.text or ""
      if text == "" or not text:find("#", 1, true) then
        out:insert(el)
      else
        scan_str_text(text, out, cfg, emit_token)
      end

    elseif el.t == "Span" or el.t == "Emph" or el.t == "Strong" or el.t == "Quoted" then
      -- Containers may introduce or inherit skip regions
      local child_skip = false
      if el.t == "Span" then
        child_skip = (el.attr and el.attr.classes) and (function()
          for _, c in ipairs(el.attr.classes) do
            if skip_set and skip_set[c] then return true end
          end
          return false
        end)() or false
      end

      local new_content = process_inlines(el.content, cfg, skip_set, child_skip)
      out:insert(rebuild_container(el, new_content))

    else
      out:insert(el)
    end
  end

  return out
end

return {
  process_inlines = process_inlines
}

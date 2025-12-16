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
  "'", '"', "`",
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

-- Build ASCII byte lookup sets to avoid per-char substring allocations
local function make_byte_set(char_set)
  local bs = {}
  for k, _ in pairs(char_set or {}) do
    local b = string.byte(k)
    if b and b < 128 then bs[b] = true end
  end
  return bs
end

local START_BYTE = make_byte_set(START_BOUNDARY)
local STOP_BYTE  = make_byte_set(STOP_CHAR)

-- UTF-8 bytes for U+2019 RIGHT SINGLE QUOTATION MARK (’): E2 80 99
local U2019_B1, U2019_B2, U2019_B3 = 0xE2, 0x80, 0x99

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
  if prev:find("mailto:", 1, true) then return true end
  if prev:find("href=", 1, true) then return true end

  return false
end

------------------------------------------------------------
-- Inline container rebuild
------------------------------------------------------------

--[[ Return true if attr.classes contains any class in skip_set. ]]
local function has_any_class(attr, skip_set)
  if not skip_set then return false end
  if not attr or not attr.classes then return false end
  for _, c in ipairs(attr.classes) do
    if skip_set[c] then return true end
  end
  return false
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

-- Return true if a Str contains a '#' marker.
local function str_has_hash(el)
  return el and el.t == "Str" and el.text and el.text:find("#", 1, true) ~= nil
end

-- Return true if this inline is a container we recurse into.
local function is_supported_container(el)
  return el and (el.t == "Span" or el.t == "Emph" or el.t == "Strong" or el.t == "Quoted")
end

-- Return true if this element should never be processed (kept as-is).
local function is_passthrough_inline(el)
  return el and (el.t == "Link" or el.t == "Code" or el.t == "CodeSpan")
end

-- Return true if this Span is already an emitted hashtag span (avoid reprocessing).
local function is_emitted_hashtag_span(el)
  if not el or el.t ~= "Span" then return false end
  local classes = (el.attr and el.attr.classes) or {}
  for _, c in ipairs(classes) do
    if c == "hashtag" then return true end
  end
  return false
end

--[[
Cheap pre-scan: return true if there is any '#' to process.
Recurses into supported containers, but never inspects inside Link/Code/CodeSpan.
]]
local function contains_hash_anywhere(inlines)
  for _, el in ipairs(inlines or {}) do
    if str_has_hash(el) then return true end
    if is_passthrough_inline(el) then
      -- do not inspect inside
    elseif is_supported_container(el) and el.content then
      if contains_hash_anywhere(el.content) then return true end
    end
  end
  return false
end

--[[
Decide whether a hashtag may start at `hash_pos` based on the previous character.

This implements the "start boundary" rule:
  - If the character immediately before '#' is nil (start of text / start of inline), allow.
  - Otherwise, allow only if that previous character is in START_BOUNDARY.

To support cross-Str boundaries, if `hash_pos == 1` (the '#' is at the start of the current Str),
the function peeks the last emitted inline in `out`:
  - If the previous emitted inline is a Str, it uses its last character as the boundary context.
  - If not, it treats the position as a boundary (allowed).

Performance notes:
  - Uses byte-level checks for ASCII (START_BYTE) to avoid substring allocations.
  - Falls back to UTF-8 helpers for non-ASCII characters.

Parameters:
  text (string): current Str text
  hash_pos (number): byte index of '#' within `text` (1-based)
  out (pandoc.List): output list already emitted (used to peek previous Str tail)

Returns:
  boolean: true if '#' is allowed to start a hashtag at this position, false otherwise
]]
local function prev_allows_start(text, hash_pos, out)
  if hash_pos > 1 then
    local b = string.byte(text, hash_pos - 1)
    if b and b < 128 then
      return START_BYTE[b] == true
    end
    local ch = utf8.char_before_byte(text, hash_pos - 1)
    return (ch == nil) or (START_BOUNDARY[ch] == true)
  end

  local prev_el = out[#out]
  if prev_el and prev_el.t == "Str" then
    local t = prev_el.text or ""
    if #t == 0 then return true end

    local lb = string.byte(t, #t)
    if lb and lb < 128 then
      return START_BYTE[lb] == true
    end

    local ch = utf8.last_char(t)
    return (ch == nil) or (START_BOUNDARY[ch] == true)
  end

  return true
end

 -- Scan forward from `j` (byte index) until a stop char is found; returns new j.
local function scan_body_end(text, j)
  local n = #text

  while j <= n do
    local b1 = string.byte(text, j)
    if not b1 then break end

    if b1 < 128 then
      if STOP_BYTE[b1] then break end
      j = j + 1
    else
      -- UTF-8 stop check for curly apostrophe ’ (E2 80 99)
      if b1 == U2019_B1 then
        local b2 = string.byte(text, j + 1)
        local b3 = string.byte(text, j + 2)
        if b2 == U2019_B2 and b3 == U2019_B3 then
          break
        end
      end

      -- Advance by UTF-8 sequence length using leading byte.
      if b1 < 0xE0 then
        j = math.min(j + 2, n + 1)
      elseif b1 < 0xF0 then
        j = math.min(j + 3, n + 1)
      else
        j = math.min(j + 4, n + 1)
      end
    end
  end

  return j
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
  local n = #text
  while i <= n do
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
    if not prev_allows_start(text, s, out) then
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

    -- Read body; fast-path ASCII, plus a cheap UTF-8 skip (no decoding)
    local j = scan_body_end(text, s + 1)

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

-- Forward declaration to allow mutual recursion
local process_inlines

-- Process a single inline and append to out.
local function process_inline(el, out, cfg, skip_set, skip, emit_token)
  if is_passthrough_inline(el) then
    out:insert(el)
    return
  end

  if el.t == "Str" then
    local text = el.text or ""
    if text == "" or not text:find("#", 1, true) then
      out:insert(el)
    else
      scan_str_text(text, out, cfg, emit_token)
    end
    return
  end

  if is_supported_container(el) then
    if el.t == "Span" and is_emitted_hashtag_span(el) then
      out:insert(el)
      return
    end

    local child_skip = skip
    if el.t == "Span" then
      child_skip = child_skip or has_any_class(el.attr, skip_set)
    end

    local new_content = process_inlines(el.content, cfg, skip_set, child_skip)
    out:insert(rebuild_container(el, new_content))
    return
  end

  out:insert(el)
end

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
process_inlines = function(inlines, cfg, skip_set, skip)
  local out = pandoc.List:new()

  if skip then
    for _, el in ipairs(inlines or {}) do out:insert(el) end
    return out
  end

  -- Fast path: no '#' anywhere
  if not contains_hash_anywhere(inlines) then
    for _, el in ipairs(inlines or {}) do out:insert(el) end
    return out
  end

  local emit_token = make_emitter(out, cfg)

  for _, el in ipairs(inlines or {}) do
    process_inline(el, out, cfg, skip_set, skip, emit_token)
  end

  return out
end

return {
  process_inlines = process_inlines
}

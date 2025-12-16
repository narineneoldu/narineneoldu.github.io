--[[
# hashtag.deps.lua

Registers the HTML dependency used by the `hashtag` extension.

## What it does

- Adds a Quarto HTML dependency named `hashtag`
- Injects the stylesheet `css/hashtag.css`
- Only runs for HTML output
- Adds the dependency at most once (idempotent)

## When to use

Call `ensure_html_dependency()` from any shortcode/filter code that emits
HTML relying on the extension’s CSS.

## Notes

This module is intentionally defensive:
- If the Quarto runtime is unavailable, it exits silently.
- If the target format is not HTML, it exits silently.
]]

local M = {}

------------------------------------------------------------
-- Guards
------------------------------------------------------------

--[[
Return true if the current Pandoc output format is HTML-ish.

Notes:
- FORMAT is a Pandoc global (e.g., "html", "html5", "revealjs").
- This check is a lightweight first gate; Quarto checks below are stricter.
]]
local function is_html()
  return (FORMAT and FORMAT:match("html") ~= nil)
end

--[[
Return true if we are in a Quarto HTML context where adding dependencies is valid.

Why this exists:
- Avoids errors when running outside Quarto (plain Pandoc).
- Avoids adding dependencies for non-HTML targets.
- Centralizes the guard logic to keep ensure_* functions minimal.

Returns:
  boolean
]]
local function is_quarto_html_context()
  if not is_html() then
    return false
  end
  if not quarto or not quarto.doc or not quarto.doc.is_format then
    return false
  end
  if not quarto.doc.is_format("html") then
    return false
  end
  return true
end

------------------------------------------------------------
-- Core JS/CSS dependency
------------------------------------------------------------

local added = {}

--[[
Add an HTML dependency if not already added and in a Quarto HTML context.
Parameters:
  name (string)
    Name of the dependency.
  stylesheets (table of string)
    List of stylesheet paths to include.
]]
local function add_dep(name, stylesheets)
  if added[name] then return end
  if not is_quarto_html_context() then return end

  quarto.doc.add_html_dependency({
    name = name,
    stylesheets = stylesheets
  })

  added[name] = true
end

--[[
Ensure the extension's HTML dependency is registered.

Behavior:
- No-op if already added (idempotent).
- No-op if not running in a Quarto HTML context.
- Otherwise registers:
    name = "hashtag"
    stylesheets = { "css/hashtag.css" }

Where to add HTML guards:
- Put the guard immediately after the idempotency check, before touching quarto APIs.
]]
local function ensure_html_dependency()
  add_dep("hashtag", { "css/hashtag.css" })
end

--[[
Ensure the extension's Bootstrap Icons (or icon-related) HTML dependency is registered.

Behavior:
- No-op if already added (idempotent).
- No-op if not running in a Quarto HTML context.
- Otherwise registers:
    name = "hashtag-bi"
    stylesheets = { "css/hashtag-bi.css" }

Where to add HTML guards:
- Same place: right after the idempotency check.
]]
local function ensure_html_bi_dependency()
  add_dep("hashtag-bi", { "css/hashtag-bi.css" })
end

M.ensure_html_dependency = ensure_html_dependency
M.ensure_html_bi_dependency = ensure_html_bi_dependency

return M

-- hashtag.deps.lua
-- Add JS/CSS dependencies for last modified display

local M = {}

------------------------------------------------------------
-- Core JS/CSS dependency
------------------------------------------------------------

local added = false
local function ensure_html_dependency()
  if added then return end

  -- Safety: make sure we are in a Quarto HTML context
  if not quarto or not quarto.doc or not quarto.doc.is_format then
    return
  end
  if not quarto.doc.is_format("html") then
    return
  end

  quarto.doc.add_html_dependency({
    name = "hashtag",
    stylesheets = { "css/hashtag.css" }
  })
  added = true
end

M.ensure_html_dependency = ensure_html_dependency

return M

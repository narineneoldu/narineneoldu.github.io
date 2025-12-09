-- _extensions/media-short/deps.lua
-- Only add Plyr dependencies once per document.

local M = {}

local added = false

local function ensure_plyr()
  if added then
    return
  end

  -- Only for HTML-ish outputs
  if not quarto.doc.is_format("html") then
    return
  end

  quarto.doc.add_html_dependency({
    name = "plyr-jump",
    scripts = {
      { path = "plyr-jump.js",   afterBody = true }
    },
  })

  added = true
end

M.ensure_plyr = ensure_plyr

return M

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
  --       { path = "plyr-ui.js",      afterBody = true },
  quarto.doc.add_html_dependency({
    name = "plyr-bundle",
    stylesheets = { "css/plyr.css", "css/media-block.css", "css/vol-popup.css" },
    scripts = {
      { path = "js/plyr.js",           afterBody = true },
      { path = "js/plyr-core.js",      afterBody = true },
      { path = "js/plyr-vol-popup.js", afterBody = true },
      { path = "js/plyr-caption.js",   afterBody = true },
    },
  })

  added = true
end

M.ensure_plyr = ensure_plyr

return M

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
    stylesheets = { "plyr.css", "media-block.css", "vol-popup.css" },
    scripts = {
      { path = "plyr.js",           afterBody = true },
      { path = "plyr-core.js",      afterBody = true },
      { path = "plyr-vol-popup.js", afterBody = true },
      { path = "plyr-caption.js",   afterBody = true },
    },
  })

  added = true
end

M.ensure_plyr = ensure_plyr

return M

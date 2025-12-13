-- _extensions/date-modified/deps.lua
-- Add JS/CSS dependencies for last modified display

local M = {}

local json = require("date_modified.json")

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
    name = "date-modified",
    stylesheets = { "css/date_modified.css" },
    scripts = {{ path = "js/date_modified.js", afterBody = true }},
  })
  added = true
end

------------------------------------------------------------
-- Helper: inject JSON i18n data into <head>
------------------------------------------------------------

-- Track ids we have already emitted (per Pandoc run)
local injected_ids = {}

--- Ensure an inline JSON <script> tag is present in <head>.
-- The tag will have the given id and the given Lua table encoded as JSON.
-- It is only added once per id.
-- @param meta pandoc.Meta: document metadata table
-- @param id   string      : DOM id for the <script> element
-- @param data table       : plain Lua table to encode as JSON
local function ensure_i18n_json(meta, id, data)
  if type(id) ~= "string" or id == "" then return end
  if injected_ids[id] then return end

  -- Safety: Quarto HTML context guard
  if not quarto or not quarto.doc or not quarto.doc.is_format then
    return
  end
  if not quarto.doc.is_format("html") then
    return
  end
  if type(data) ~= "table" then
    return
  end

  local ok, payload = pcall(json.encode, data)
  if not ok or type(payload) ~= "string" then
    io.stderr:write("[date-modified] Warning: failed to encode i18n JSON for id='" .. id .. "'\n")
    return
  end
  payload = payload:gsub("</", "<\\/")

  local html = string.format(
    '<script id="%s" type="application/json">%s</script>',
    id,
    payload
  )

  local block = pandoc.RawBlock("html", html)

  local header = meta["header-includes"]
  if not header then
    meta["header-includes"] = pandoc.MetaList({ block })
  elseif header.t == "MetaList" then
    table.insert(header, block)
    meta["header-includes"] = header
  else
    meta["header-includes"] = pandoc.MetaList({ header, block })
  end

  injected_ids[id] = true
end

M.ensure_html_dependency = ensure_html_dependency
M.ensure_i18n_json       = ensure_i18n_json

return M

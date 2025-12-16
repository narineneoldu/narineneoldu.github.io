-- tests/helpers.lua
-- Shared test helpers (text extraction, small constructors, module reload utilities).

local M = {}

function M.Str(s) return pandoc.Str(s) end

function M.Span(content, classes)
  return pandoc.Span(content, { classes = classes or {} })
end

-- Concatenate textual representation of a pandoc inline list output (Str/Link/Span)
function M.texts(out)
  local acc = {}
  for _, el in ipairs(out or {}) do
    if el.t == "Str" then
      acc[#acc + 1] = el.text or ""
    elseif el.t == "Link" or el.t == "Span" then
      if el.content and el.content[1] and el.content[1].t == "Str" then
        acc[#acc + 1] = el.content[1].text or ""
      end
    end
  end
  return table.concat(acc, "")
end

-- Recursive inline text extraction (useful for shortcode outputs)
function M.inline_text(el)
  if not el then return "" end
  if el.t == "Str" then return el.text or "" end
  if el.t == "Span" or el.t == "Link" then
    local b = {}
    for _, c in ipairs(el.content or {}) do
      b[#b + 1] = M.inline_text(c)
    end
    return table.concat(b)
  end
  return ""
end

-- Reload a module (and optionally additional dependent modules)
function M.reload(mods)
  for _, m in ipairs(mods or {}) do
    package.loaded[m] = nil
  end
  -- Return last required module if caller wants it
  local last
  for _, m in ipairs(mods or {}) do
    last = require(m)
  end
  return last
end

return M

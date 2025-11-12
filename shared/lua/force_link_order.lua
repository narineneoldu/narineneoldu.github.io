-- ../shared/lua/force_link_order.lua
-- Pandoc’un attr sıralamasını atlatır ve class, data-* dâhil her şeyi korur.

local M = {}

local function attrs_to_string(attr)
  if not attr then return "" end
  local out = {}

  -- 1️⃣ class’ları ekle
  if attr.classes and #attr.classes > 0 then
    table.insert(out, string.format('class="%s"', table.concat(attr.classes, " ")))
  end

  -- 2️⃣ attributes tablosundan target/rel harici olanları ekle
  if attr.attributes then
    for k, v in pairs(attr.attributes) do
      if k ~= "target" and k ~= "rel" then
        table.insert(out, string.format('%s="%s"', k, v))
      end
    end
  end

  return #out > 0 and (" " .. table.concat(out, " ")) or ""
end

function M.Link(el)
  local href = el.target or ""
  local text = pandoc.utils.stringify(el.content)

  local target = ""
  if el.attr and el.attr.attributes and el.attr.attributes["target"] then
    target = ' target="' .. el.attr.attributes["target"] .. '"'
  end

  local rel = ""
  if el.attr and el.attr.attributes and el.attr.attributes["rel"] then
    rel = ' rel="' .. el.attr.attributes["rel"] .. '"'
  end

  local extra = attrs_to_string(el.attr)

  local html = string.format(
    '<a href="%s"%s%s%s>%s</a>',
    href,
    target,   -- target daima önce
    rel,      -- sonra rel
    extra,    -- sonra class, data-*, title...
    text
  )

  return pandoc.RawInline("html", html)
end

return M

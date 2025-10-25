-- line_anchors_headings.lua
local h = 0

function Header(el)
  local id = el.identifier
  if not id or id == "" then
    h = h + 1
    id = string.format("H%02d", h)
    el.identifier = id
  end
  local html = string.format(
    '<a href="#%s" class="line-anchor heading-anchor" aria-label="Bu başlığa bağlantı">&#8203;</a>',
    id
  )
  el.content:insert(pandoc.Space())
  el.content:insert(pandoc.RawInline('html', html))
  return el
end

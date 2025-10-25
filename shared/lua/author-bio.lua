-- author-page-bio.lua

local is_author_page = false
local author_info = { name = nil, bio = nil, links = {} }

local function S(v)
  if not v then return nil end
  return pandoc.utils.stringify(v)
end

local function make_link(href, icon, text)
  local inlines = {}
  if icon and icon ~= "" then
    table.insert(inlines,
      pandoc.RawInline("html", '<i class="bi bi-' .. icon .. '"></i>')
    )
    table.insert(inlines, pandoc.Space())
  end
  if text and text ~= "" then
    table.insert(inlines, pandoc.Str(text))
  end
  return pandoc.Link(inlines, href, "", {target="_blank", rel="noopener"})
end

function Meta(meta)
  -- Bu bir yazar sayfası mı?
  if meta["is-author-page"] == true or meta["is-author-page"] == "true" then
    is_author_page = true
  elseif meta.listing and meta.listing.contents then
    local c = pandoc.utils.stringify(meta.listing.contents)
    if c == "." then
      is_author_page = true
    end
  end

  -- İsim: Quarto bunu kesmiyor
  if meta.author then
    author_info.name = S(meta.author)
  end

  -- Bio: Quarto bunu kesmiyor çünkü custom field
  if meta["author-bio"] then
    author_info.bio = S(meta["author-bio"])
  end

  -- Linkler: yine custom olduğu için olduğu gibi geliyor
  if meta["author-links"] and type(meta["author-links"]) == "table" then
    for _, L in ipairs(meta["author-links"]) do
      table.insert(author_info.links, {
        href = S(L.href) or "",
        icon = S(L.icon) or "",
        text = S(L.text) or ""
      })
    end
  end
end

function Pandoc(doc)
  if not is_author_page then
    return doc
  end

  -- blog-post-filter.lua'nın eklediği top-meta-row'u yazar sayfasından kaldır
  local cleaned = {}
  for _, block in ipairs(doc.blocks) do
    local drop = false
    if block.t == "Div" and block.attr and block.attr.classes then
      for _, cls in ipairs(block.attr.classes) do
        if cls == "top-meta-row" then
          drop = true
          break
        end
      end
    end
    if not drop then table.insert(cleaned, block) end
  end
  doc.blocks = cleaned

  -- Yazar kutusu yoksa hiç ekleme
  if not author_info.name then
    return doc
  end

  local box_blocks = {}

  -- İsim
  table.insert(box_blocks,
    pandoc.RawBlock("html",
      '<h1 class="author-bio-name">' .. author_info.name .. '</h1>'
    )
  )

  -- Bio
  if author_info.bio and author_info.bio ~= "" then
    table.insert(box_blocks,
      pandoc.Para({ pandoc.Str(author_info.bio) })
    )
  end

  -- Linkler
  if #author_info.links > 0 then
    local link_inlines = {}
    for _, L in ipairs(author_info.links) do
      table.insert(link_inlines,
        make_link(L.href, L.icon, L.text)
      )
      table.insert(link_inlines, pandoc.Space())
    end
    table.insert(box_blocks,
      pandoc.Para(link_inlines)
    )
  end

  local box = pandoc.Div(box_blocks, pandoc.Attr("", {"author-bio-box"}))
  table.insert(doc.blocks, 1, box)

  return doc
end

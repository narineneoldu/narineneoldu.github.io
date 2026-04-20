--[[
shortcode-photo-gallery.lua
Generates a photo gallery grid (chips + search + modal lightbox) from a
_photos.yml manifest that lives alongside the host qmd file in a sibling
directory named after the qmd stem.

Layout expected:
  <category>.qmd              <- hosts {{< photo-gallery >}}
  <category>/_photos.yml      <- manifest
  <category>/*.jpg            <- image files (paths relative to this dir)

YAML schema (supports inline and block tag lists):
  photos:
    - file: 2024-07-01-aile.jpg
      date: 2024-07-01
      title: "Başlık"
      caption: "Kısa açıklama."
      location: "Tavşantepe"
      tags: [aile, anne, baba]
]]--

local function read_file(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local content = f:read('*a')
  f:close()
  return content
end

local function trim(s)
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function strip_quotes(s)
  s = trim(s)
  if #s < 2 then return s end
  local q = s:sub(1, 1)
  if (q == '"' or q == "'") and s:sub(-1) == q then
    return s:sub(2, -2)
  end
  return s
end

local function parse_inline_list(s)
  local inner = s:match('^%[(.*)%]$')
  if not inner then return nil end
  local items = {}
  for item in inner:gmatch('[^,]+') do
    local trimmed = strip_quotes(trim(item))
    if trimmed ~= '' then
      table.insert(items, trimmed)
    end
  end
  return items
end

local function parse_yaml_photos(content)
  local photos = {}
  local current = nil
  local in_photos = false
  local in_tags_block = false

  for raw_line in content:gmatch('[^\r\n]+') do
    -- Strip inline comments (simple; doesn't handle # inside quoted strings)
    local line = raw_line:gsub('%s+#.*$', '')
    if line:match('^%s*#') then line = '' end
    if not line:match('%S') then goto continue end

    if line:match('^photos%s*:') then
      in_photos = true
      goto continue
    end

    if not in_photos then goto continue end

    local file_match = line:match('^%s*%-%s*file%s*:%s*(.+)$')
    if file_match then
      if current then table.insert(photos, current) end
      current = { file = strip_quotes(file_match), tags = {} }
      in_tags_block = false
      goto continue
    end

    if not current then goto continue end

    if in_tags_block then
      local item = line:match('^%s+%-%s*(.+)$')
      if item then
        table.insert(current.tags, strip_quotes(item))
        goto continue
      else
        in_tags_block = false
      end
    end

    local key, val = line:match('^%s+([%w_%-]+)%s*:%s*(.*)$')
    if key then
      val = trim(val or '')
      if key == 'tags' then
        if val == '' then
          in_tags_block = true
          current.tags = {}
        else
          local list = parse_inline_list(val)
          if list then current.tags = list end
        end
      else
        current[key] = strip_quotes(val)
      end
    end

    ::continue::
  end

  if current then table.insert(photos, current) end
  return photos
end

local function collect_unique_tags(photos)
  local seen = {}
  local tags = {}
  for _, p in ipairs(photos) do
    for _, t in ipairs(p.tags or {}) do
      if not seen[t] and t ~= '' then
        seen[t] = true
        table.insert(tags, t)
      end
    end
  end
  table.sort(tags)
  return tags
end

local function escape_html(s)
  if s == nil then return '' end
  return (tostring(s)
           :gsub('&', '&amp;')
           :gsub('<', '&lt;')
           :gsub('>', '&gt;')
           :gsub('"', '&quot;'))
end

local TR_MONTHS = {
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
}
local EN_MONTHS = {
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
}

local function format_date(date_str, lang)
  if not date_str or date_str == '' then return '' end
  local y, m, d = date_str:match('^(%d%d%d%d)-(%d%d)-(%d%d)$')
  if not y then return date_str end
  local months = (lang == 'en') and EN_MONTHS or TR_MONTHS
  local mi = tonumber(m)
  local month_name = (mi and months[mi]) or m
  return string.format('%d %s %s', tonumber(d), month_name, y)
end

local function detect_lang(file_path)
  if not file_path then return 'tr' end
  if file_path:match('[/\\]en[/\\]') then return 'en' end
  return 'tr'
end

local function build_description(p, lang)
  local parts = {}
  if p.title and p.title ~= '' then
    table.insert(parts, '<strong>' .. escape_html(p.title) .. '</strong>')
  end
  local date_fmt = format_date(p.date, lang)
  if date_fmt ~= '' or (p.location and p.location ~= '') then
    local loc_date = {}
    if date_fmt ~= '' then table.insert(loc_date, escape_html(date_fmt)) end
    if p.location and p.location ~= '' then
      table.insert(loc_date, escape_html(p.location))
    end
    table.insert(parts, table.concat(loc_date, ', '))
  end
  if p.caption and p.caption ~= '' then
    table.insert(parts, escape_html(p.caption))
  end
  return table.concat(parts, '<br>')
end

return {
  ['photo-gallery'] = function(args, kwargs, meta, raw_args, context)
    local input_file = quarto.doc.input_file
    if not input_file then
      return pandoc.RawBlock('html',
        '<!-- photo-gallery: quarto.doc.input_file not available -->')
    end

    local input_dir = pandoc.path.directory(input_file)
    local fname = pandoc.path.filename(input_file)
    local category = fname:match('^(.+)%..+$') or fname
    local yaml_path = pandoc.path.join({ input_dir, category, '_photos.yml' })

    local lang = detect_lang(input_file)
    local empty_msg = (lang == 'en')
      and 'This category is currently empty. New photos will appear here as they are added.'
      or 'Bu kategori şu anda boş. Yeni fotoğraflar eklendikçe burada görünecek.'

    local content = read_file(yaml_path)
    if not content then
      return pandoc.RawBlock('html',
        '<div class="photo-gallery-empty">' .. empty_msg .. '</div>')
    end

    local photos = parse_yaml_photos(content)
    if #photos == 0 then
      return pandoc.RawBlock('html',
        '<div class="photo-gallery-empty">' .. empty_msg .. '</div>')
    end

    local tags = collect_unique_tags(photos)
    local placeholder = (lang == 'en')
      and 'Search (AND: &&, OR: ||)…'
      or 'Ara (VE: &&, VEYA: ||)…'
    local close_l = (lang == 'en') and 'Close' or 'Kapat'
    local prev_l = (lang == 'en') and 'Previous' or 'Önceki'
    local next_l = (lang == 'en') and 'Next' or 'Sonraki'

    local html = {}
    table.insert(html, string.format(
      '<div class="photo-gallery" data-gallery="%s">', escape_html(category)))
    table.insert(html, '<div class="gallery-controls">')
    table.insert(html, '<div class="tag-chips" role="group">')
    for _, t in ipairs(tags) do
      table.insert(html, string.format(
        '<button type="button" class="tag-chip" data-tag="%s">%s</button>',
        escape_html(t), escape_html(t)))
    end
    table.insert(html, '</div>')
    table.insert(html, string.format(
      '<input type="search" class="gallery-search" placeholder="%s">',
      escape_html(placeholder)))
    table.insert(html, '</div>')

    table.insert(html, '<div class="photo-grid">')
    for i, p in ipairs(photos) do
      local img_url = category .. '/' .. (p.file or '')
      local alt = p.title or p.caption or p.file or ''
      local tag_attr = table.concat(p.tags or {}, ' ')
      local date_fmt = format_date(p.date, lang)
      local description = build_description(p, lang)

      table.insert(html, string.format(
        '<figure class="photo-card" data-index="%d" data-tags="%s" data-title="%s" data-caption="%s" data-date="%s" data-description="%s">',
        i,
        escape_html(tag_attr),
        escape_html(p.title or ''),
        escape_html(p.caption or ''),
        escape_html(p.date or ''),
        escape_html(description)))
      table.insert(html, string.format(
        '<span class="photo-number" aria-hidden="true">%d</span>', i))
      table.insert(html, string.format(
        '<img src="%s" alt="%s" loading="lazy">',
        escape_html(img_url), escape_html(alt)))
      table.insert(html, '<figcaption>')
      if p.title and p.title ~= '' then
        table.insert(html, string.format(
          '<div class="photo-title">%s</div>', escape_html(p.title)))
      end
      if date_fmt ~= '' then
        table.insert(html, string.format(
          '<time class="photo-date" datetime="%s">%s</time>',
          escape_html(p.date or ''), escape_html(date_fmt)))
      end
      table.insert(html, '</figcaption>')
      table.insert(html, '</figure>')
    end
    table.insert(html, '</div>')

    table.insert(html, '<div class="gallery-modal" aria-hidden="true">')
    table.insert(html, string.format(
      '<button type="button" class="modal-close" aria-label="%s">×</button>',
      escape_html(close_l)))
    table.insert(html, string.format(
      '<button type="button" class="modal-prev" aria-label="%s">‹</button>',
      escape_html(prev_l)))
    table.insert(html, string.format(
      '<button type="button" class="modal-next" aria-label="%s">›</button>',
      escape_html(next_l)))
    table.insert(html, '<div class="modal-content">')
    table.insert(html, '<img class="modal-img" alt="">')
    table.insert(html, '<div class="modal-caption"></div>')
    table.insert(html, '</div>')
    table.insert(html, '</div>')
    table.insert(html, '</div>')

    return pandoc.RawBlock('html', table.concat(html, '\n'))
  end
}

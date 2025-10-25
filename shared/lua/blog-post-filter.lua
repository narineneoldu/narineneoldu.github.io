-- blog-post-filter.lua (çok dilli)
-- 1) Üst blok: YAZAR / TARİH / KAYNAK
-- 2) Alt blok: Dış Bağlantılar / External Links
-- 3) Dil: _quarto.yml içindeki metadata.site-lang ile belirlenir

local meta_author      = nil
local meta_author_url  = nil
local meta_date        = nil
local meta_source      = nil
local norm_source      = nil
local site_lang        = "tr"   -- varsayılan

-- küçük yardımcı: label span
local function metaLabel(txt)
  return pandoc.Span({ pandoc.Str(txt) }, pandoc.Attr("", {"meta-label"}))
end

-- URL normalize et: query, anchor at
local function normalize_url(u)
  if not u then return nil end
  if not string.match(u, "^https?://") then
    return nil
  end
  u = u:gsub("[?#].*$", "")
  return u
end

-- Meta: hem sayfa hem proje metadata'sı buradan gelir
function Meta(meta)
  -- 1. dil bilgisini yakala
  --    _quarto.yml içinde:
  --    metadata:
  --      site-lang: tr  (veya en)
  if meta["site-lang"] then
    site_lang = pandoc.utils.stringify(meta["site-lang"])
  end

  -- 2. author bilgisini normalleştir
  if meta.author then
    if type(meta.author) == "table" and meta.author[1] and meta.author[1].name then
      meta_author = meta.author[1].name
    elseif type(meta.author) == "table" and meta.author[1] and type(meta.author[1]) == "string" then
      meta_author = meta.author[1]
    else
      meta_author = pandoc.utils.stringify(meta.author)
    end
  end

  -- 3. date
  if meta.date then
    meta_date = pandoc.utils.stringify(meta.date)
  end

  -- 4. source (orijinal kaynak)
  if meta.source then
    meta_source = pandoc.utils.stringify(meta.source)
    norm_source = normalize_url(meta_source)
  end
end

function Pandoc(doc)
  -------------------------------------------------
  -- A) Dil bazlı sabit metinler
  -------------------------------------------------
  local LABEL_AUTHOR
  local LABEL_DATE
  local LABEL_SOURCE
  local LINKS_HEADER
  local SOURCE_LINK_TEXT

  if site_lang == "en" then
    LABEL_AUTHOR      = "AUTHOR"
    LABEL_DATE        = "LAST UPDATED"
    LABEL_SOURCE      = "SOURCE"
    LINKS_HEADER      = "External Links"
    SOURCE_LINK_TEXT  = "Original Source"
  else
    LABEL_AUTHOR      = "YAZAR"
    LABEL_DATE        = "GÜNCELLEME TARİHİ"
    LABEL_SOURCE      = "KAYNAK"
    LINKS_HEADER      = "Dış Bağlantılar"
    SOURCE_LINK_TEXT  = "Orijinal Kaynak"
  end

  -------------------------------------------------
  -- B) Yazar sayfasına link ver (../)
  --    Varsayım: blog/posts/<yazar>/<slug>/index.qmd
  --    yazar sayfası: blog/posts/<yazar>/index.qmd
  -------------------------------------------------
  meta_author_url = nil
  if quarto and quarto.doc and quarto.doc.input_file then
    local input_path = quarto.doc.input_file
    -- slug klasörünü at
    local post_dir = input_path:gsub("/index%.qmd$", "")
    -- yazar klasörü
    local author_dir = post_dir:match("(.+)/[^/]+$")
    if author_dir then
      -- yazı -> ../ -> yazar sayfası
      meta_author_url = "../"
    end
  end

  -------------------------------------------------
  -- C) Sayfadaki tüm dış linkleri topla
  -------------------------------------------------
  local collected = {}

  local function add_found_url(u)
    local n = normalize_url(u)
    if not n then return end
    -- orijinal kaynak URL'sini dış bağlantılar listesine ekleme
    if norm_source and n == norm_source then
      return
    end
    table.insert(collected, n)
  end

  -- Üst seviye blokların içinden yürü
  for _, block in ipairs(doc.blocks) do

    -- doğrudan RawBlock (iframe vs)
    if block.t == "RawBlock" and block.format == "html" then
      for url in block.text:gmatch('https?://[^%s"\'>]+') do
        add_found_url(url)
      end
    end

    -- alt içerikleri gez
    pandoc.walk_block(block, {
      -- klasik markdown linki
      Link = function(l)
        add_found_url(l.target)
      end,

      -- inline raw html (<a href="...">, <iframe src="..."> vs)
      RawInline = function(ri)
        if ri.format == "html" then
          for url in ri.text:gmatch('href="(https?://[^"]+)"') do
            add_found_url(url)
          end
          for url in ri.text:gmatch('src="(https?://[^"]+)"') do
            add_found_url(url)
          end
          for url in ri.text:gmatch('https?://[^%s"\'>]+') do
            add_found_url(url)
          end
        end
      end,

      -- nested RawBlock (bazı layoutlarda blok içinde de gelebilir)
      RawBlock = function(rb)
        if rb.format == "html" then
          for url in rb.text:gmatch('https?://[^%s"\'>]+') do
            add_found_url(url)
          end
        end
      end,
    })
  end

  -- Tekilleştir
  local unique = {}
  do
    local seen = {}
    for _, u in ipairs(collected) do
      if not seen[u] then
        table.insert(unique, u)
        seen[u] = true
      end
    end
  end

  -------------------------------------------------
  -- D) Üst meta bloğunu (yazar / tarih / kaynak) hazırla
  -------------------------------------------------
  local cols = {}

  if meta_author then
    local author_node
    if meta_author_url then
      author_node = pandoc.Link(meta_author, meta_author_url, "", {rel="author"})
    else
      author_node = pandoc.Str(meta_author)
    end

    table.insert(cols,
      pandoc.Div({
        metaLabel(LABEL_AUTHOR),
        pandoc.LineBreak(),
        author_node
      }, pandoc.Attr("", {"col-meta"}))
    )
  end

  if meta_date then
    table.insert(cols,
      pandoc.Div({
        metaLabel(LABEL_DATE),
        pandoc.LineBreak(),
        pandoc.Str(meta_date)
      }, pandoc.Attr("", {"col-meta"}))
    )
  end

  if meta_source then
    local source_link = pandoc.Link(
      SOURCE_LINK_TEXT,
      meta_source,
      "",
      {target="_blank", rel="noopener"}
    )

    table.insert(cols,
      pandoc.Div({
        metaLabel(LABEL_SOURCE),
        pandoc.LineBreak(),
        source_link
      }, pandoc.Attr("", {"col-meta"}))
    )
  end

  if #cols > 0 then
    local wrapper_div = pandoc.Div(cols, pandoc.Attr("", {"top-meta-row"}))
    table.insert(doc.blocks, 1, wrapper_div)
  end

  -------------------------------------------------
  -- E) Alta bağlantı listesi (External Links / Dış Bağlantılar)
  --    İçindekiler'e girmesin diye toc-ignore koyuyoruz
  -------------------------------------------------
  if #unique > 0 then
  -- h3 başlığını normal HTML olarak enjekte ediyoruz.
  local header_html = string.format(
    '<h3 class="external-links-heading">%s</h3>',
    LINKS_HEADER
  )
  local header = pandoc.RawBlock("html", header_html)

    local items = {}
    for _, u in ipairs(unique) do
      local link = pandoc.Link(u, u, "", {target="_blank", rel="noopener"})
      table.insert(items, pandoc.Plain({link}))
    end
    local list = pandoc.OrderedList(items)

    table.insert(doc.blocks, header)
    table.insert(doc.blocks, list)
  end

  return doc
end

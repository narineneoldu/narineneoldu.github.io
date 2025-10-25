-- external-links.lua
-- Yazı içindeki dış bağlantıları toplayıp sayfa sonuna
-- "Dış Bağlantılar" başlığı altında tıklanabilir liste olarak ekler.
-- meta.source (orijinal kaynak) dahil edilmez.
-- URL parametreleri (? ... ve # ...) temizlenir.
-- iframe src dahil her türlü html içinde yakalamaya çalışır.

local page_source = nil

-- Yardımcı: normalize edip listeye ekle
local function add_url(acc, url)
  if not url then return end

  -- sadece http/https olanlar
  if not string.match(url, "^https?://") then
    return
  end

  -- query string ve anchor'ı at
  url = url:gsub("[?#].*$", "")

  -- orijinal kaynak URL'si ise alma
  if page_source and url == page_source then
    return
  end

  table.insert(acc, url)
end

-- metadata'dan source'u al
function Meta(meta)
  if meta.source then
    page_source = pandoc.utils.stringify(meta.source)
    -- normalize source da aynı şekilde parametreleri temizle
    page_source = page_source:gsub("[?#].*$", "")
  end
end

function Pandoc(doc)
  local found = {}

  -- tüm blokları gez
  for _, block in pairs(doc.blocks) do
    pandoc.walk_block(block, {

      -- Normal markdown linkleri [text](url)
      Link = function(l)
        add_url(found, l.target)
      end,

      -- Inline raw HTML (ör: <a ...>, <iframe ...> tek satırda)
      RawInline = function(ri)
        if ri.format == "html" then
          -- İçindeki tüm http/https linklerini çek
          for url in ri.text:gmatch('https?://[^%s"\'>]+') do
            add_url(found, url)
          end
        end
      end,

      -- Block-level raw HTML (ör: çok satırlı <iframe ...> .. </iframe>)
      RawBlock = function(rb)
        if rb.format == "html" then
          for url in rb.text:gmatch('https?://[^%s"\'>]+') do
            add_url(found, url)
          end
        end
      end,
    })
  end

  -- hiç link yoksa çık
  if #found == 0 then
    return doc
  end

  -- tekilleştir
  local unique = {}
  local seen = {}
  for _, u in ipairs(found) do
    if not seen[u] then
      table.insert(unique, u)
      seen[u] = true
    end
  end

  -- tekilleştikten sonra da boşsa çık
  if #unique == 0 then
    return doc
  end

  -- "Dış Bağlantılar" başlığı
  local header = pandoc.Header(3, "Dış Bağlantılar")

  -- numaralı liste (tıklanabilir linkler yeni sekmede)
  local items = {}
  for _, u in ipairs(unique) do
    local link = pandoc.Link(u, u, "", {target="_blank", rel="noopener"})
    table.insert(items, pandoc.Plain({link}))
  end
  local list = pandoc.OrderedList(items)

  -- üstüne ince çizgi gibi görünen <hr>
  local hr = pandoc.HorizontalRule()

  table.insert(doc.blocks, hr)
  table.insert(doc.blocks, header)
  table.insert(doc.blocks, list)

  return doc
end

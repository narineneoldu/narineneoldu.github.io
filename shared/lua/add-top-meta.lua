-- external-links.lua
-- Amaç:
-- 1. Yazı içindeki tüm dış linkleri (http/https) topla
-- 2. ?... ve #... parametrelerini kaldır
-- 3. meta.source ile aynı olanı çıkar (orijinal kaynak gelmesin)
-- 4. Tekilleştir
-- 5. Sayfa sonuna "Dış Bağlantılar" başlığı + numaralı tıklanabilir liste ekle
-- 6. Eğer hiç link yoksa hiçbir şey ekleme
--
-- Ekstra: iframe src içindeki YouTube linklerini de yakala

local page_source = nil

-- küçük yardımcı: normalize edip listeye ekle
local function add_url(acc, url)
  if not url then return end

  -- sadece dış linkler
  if not string.match(url, "^https?://") then
    return
  end

  -- query string ve anchor'ı temizle
  url = url:gsub("[?#].*$", "")

  -- orijinal kaynakla aynıysa atla
  if page_source and url == page_source then
    return
  end

  table.insert(acc, url)
end

-- meta.source değerini al (orijinal kaynak)
function Meta(meta)
  if meta.source then
    page_source = pandoc.utils.stringify(meta.source)
    -- aynı normalize işlemi
    page_source = page_source:gsub("[?#].*$", "")
  end
end

function Pandoc(doc)
  local found = {}

  -- her üst seviye block üzerinde dönüyoruz
  for _, block in ipairs(doc.blocks) do

    -- 1) Blok kendisi RawBlock ise (örn. <iframe ...> tek başına duruyorsa)
    if block.t == "RawBlock" and block.format == "html" then
      -- içindeki TÜM http/https linklerini yakala (iframe src dahil)
      for url in block.text:gmatch('https?://[^%s"\'>]+') do
        add_url(found, url)
      end
    end

    -- 2) Bloğun içindeki alt içerikleri gez (Link, RawInline vs.)
    pandoc.walk_block(block, {
      -- Normal markdown linkleri [text](url)
      Link = function(l)
        add_url(found, l.target)
      end,

      -- Inline raw html (ör. <a href="...">Cumhuriyet</a> gibi)
      RawInline = function(ri)
        if ri.format == "html" then
          -- href="...":
          for url in ri.text:gmatch('href="(https?://[^"]+)"') do
            add_url(found, url)
          end
          -- src="...": iframe inline yazılmışsa
          for url in ri.text:gmatch('src="(https?://[^"]+)"') do
            add_url(found, url)
          end
          -- daha güvenli olsun diye fallback: her türlü çıplak https://...
          for url in ri.text:gmatch('https?://[^%s"\'>]+') do
            add_url(found, url)
          end
        end
      end,

      -- Alt seviyede yine RawBlock çıkarsa (bazı durumlarda Pandoc nested Div içinde RawBlock tutabiliyor)
      RawBlock = function(rb)
        if rb.format == "html" then
          for url in rb.text:gmatch('https?://[^%s"\'>]+') do
            add_url(found, url)
          end
        end
      end,
    })

  end

  -- hiç link yoksa bırak gitsin
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

  if #unique == 0 then
    return doc
  end

  -- Bölüm parçaları: hr + "Dış Bağlantılar" başlığı + numaralı liste
  local hr = pandoc.HorizontalRule()
  local header = pandoc.Header(3, "Dış Bağlantılar")

  local items = {}
  for _, u in ipairs(unique) do
    local link = pandoc.Link(u, u, "", {target="_blank", rel="noopener"})
    table.insert(items, pandoc.Plain({link}))
  end
  local list = pandoc.OrderedList(items)

  -- sayfanın sonuna ekle
  table.insert(doc.blocks, hr)
  table.insert(doc.blocks, header)
  table.insert(doc.blocks, list)

  return doc
end

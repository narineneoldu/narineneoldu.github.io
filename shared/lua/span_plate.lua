-- ../shared/lua/span_plate.lua
-- "23 XX 630" gibi Türk plaka kalıplarını <span class="plate">…</span> ile sarar.
-- Şema: 2 rakam (il) + 1+ boşluk + 1–3 harf + 1+ boşluk + 2–4 rakam.
-- NBSP ve SoftBreak dahil; kod/link/math/html içine girmez.

-- en üste:
local M = {}
local PLATES = nil

-- meta’dan sözlük oku
local function load_plates_from_meta(meta)
  if not meta then return end
  local dict = meta.plates or (meta.metadata and meta.metadata.plates)
  if type(dict) ~= "table" then return end
  local t = {}
  for k, v in pairs(dict) do
    local key = pandoc.utils.stringify(k)
    local val = pandoc.utils.stringify(v)
    if key ~= "" and val ~= "" then
      -- anahtarı normalize et: iç boşlukları tek boşluğa indir, trim
      key = key:gsub("%s+", " "):match("^%s*(.-)%s*$")
      t[key] = val
    end
  end
  if next(t) then PLATES = t end
end

function M.Meta(m)
  load_plates_from_meta(m)
end

local List = require 'pandoc.List'

-- --- yardımcı: sınıf kontrolü
local function has_class(attr, name)
  if not attr or not attr.classes then return false end
  for _, c in ipairs(attr.classes) do
    if c == name then return true end
  end
  return false
end

-- ---- Koşuyu (run) Str/Space/SoftBreak ile linearize et ----
local function run_linearize(run)
  local buf, map = {}, {}
  local pos = 0
  for idx, el in ipairs(run) do
    if el.t == "Str" then
      local s = el.text
      for i = 1, #s do
        pos = pos + 1
        buf[pos] = s:sub(i,i)
        map[pos] = {ix = idx, off = i}
      end
    elseif el.t == "Space" or el.t == "SoftBreak" then
      pos = pos + 1
      buf[pos] = " "
      map[pos] = {ix = idx, off = 0}
    end
  end
  return table.concat(buf), map
end

local function valid_plate_parts(il, letters, digits)
  -- il 01..81
  local n = tonumber(il)
  if not n or n < 1 or n > 81 then return false end

  -- Q, W, yasak, X serbest
  if letters:match("[QW]") then return false end

  local L = #letters
  local D = #digits

  -- harf sayısına göre rakam sayısı
  local ok_len =
      (L == 1 and (D == 4 or D == 5))
   or (L == 2 and (D == 3 or D == 4))
   or (L == 3 and (D == 2 or D == 3))

  if not ok_len then return false end

  -- tüm rakamlar 0 olamaz
  if digits:match("^0+$") then return false end

  return true
end

-- ---- Plaka arayıcı ----
-- 2 rakam + boşluk(lar) + 1–3 harf + boşluk(lar) + 2–4 rakam
-- %f[%d] ve %f[%D] sınırlarıyla, rakam sınırları güvenceye alınır.
-- 2 rakam + boşluk(lar) + 1–3 **büyük** harf + boşluk(lar) + 2–4 rakam
local PAT_PLATE = '%f[%d](%d%d)%s+([A-Z][A-Z]?[A-Z]?)%s+(%d%d%d?%d?%d?)%f[%D]'

local function find_plates_in_text(text)
  local hits = {}
  local i = 1
  while true do
    local a,b,il,letters,digits = text:find(PAT_PLATE, i)
    if not a then break end

    if valid_plate_parts(il, letters, digits) then
      -- DEBUG
      -- io.stderr:write(string.format("[span-plate] hit: %s %s %s\n", il, letters, digits))
      table.insert(hits, {s=a, e=b})
      i = b + 1
    else
      -- şartları sağlamıyorsa, aramayı bir karakter ileri kaydır
      i = a + 1
    end
  end

  -- çakışma temizliği (varsa)
  table.sort(hits, function(x,y) return x.s < y.s end)
  local filtered = {}
  for _, h in ipairs(hits) do
    local overlap = false
    for _, k in ipairs(filtered) do
      if not (h.e < k.s or h.s > k.e) then overlap = true; break end
    end
    if not overlap then table.insert(filtered, h) end
  end
  return filtered
end

-- ---- Run'ı vuruşlara göre yeniden inşa et ----
local function rebuild_run_from_hits(run, text, map, hits)
  if #hits == 0 then return run end

  local out = List:new()
  local pos = 1

  local function emit_plain(p1, p2)
    if p2 < p1 then return end
    local i = p1
    while i <= p2 do
      local m = map[i]
      if not m then
        i = i + 1
      elseif m.off == 0 then
        out:insert(pandoc.Space()); i = i + 1
      else
        local ix, start_off = m.ix, m.off
        local j, end_off = i, start_off
        while j+1 <= p2 and map[j+1] and map[j+1].ix == ix and map[j+1].off == end_off + 1 do
          j = j + 1; end_off = end_off + 1
        end
        local el = run[ix]
        out:insert(pandoc.Str(el.text:sub(start_off, end_off)))
        i = j + 1
      end
    end
  end

  local hix = 1
  while pos <= #text and hix <= #hits do
    local h = hits[hix]
    if pos < h.s then emit_plain(pos, h.s - 1); pos = h.s end

    -- hit'i topla (orijinal boşlukları koru)
    local parts = {}
    local i = h.s
    while i <= h.e do
      local m = map[i]
      if m and m.off == 0 then
        table.insert(parts, " "); i = i + 1
      elseif m then
        local ix, start_off = m.ix, m.off
        local j, end_off = i, start_off
        while j+1 <= h.e and map[j+1] and map[j+1].ix == ix and map[j+1].off == end_off + 1 do
          j = j + 1; end_off = end_off + 1
        end
        local el = run[ix]
        table.insert(parts, el.text:sub(start_off, end_off))
        i = j + 1
      else
        i = i + 1
      end
    end
    local tok = table.concat(parts)
    -- tooltip metnini sözlükten bul (aynı normalize ile)
    local key = tok:gsub("%s+", " "):match("^%s*(.-)%s*$")
    local tip = PLATES and PLATES[key] or nil
    local attrs = { }
    -- TODO: erişilebilirlik için tabindex ve aria-label ekle
    -- git-diff için attribute sırası dalaşması sorununu çözmen gerekiyor.
    -- attrs["tabindex"] = "0"            -- mobil/klavye için odaklanabilir
    -- attrs["aria-label"] = tip  -- ekran okuyucu için
    if tip then attrs["data-title"] = tip end  -- CSS tooltip bu alanı kullanacak
    -- (title eklemiyoruz ki native tooltip çıkmasın)
    out:insert(pandoc.Span({ pandoc.Str(tok) }, pandoc.Attr('', {'plate'}, attrs)))

    pos = h.e + 1
    hix = hix + 1
  end
  if pos <= #text then emit_plain(pos, #text) end
  return out
end

-- ---- Inlines işleme: metin koşularına uygula, kapsayıcıların içine gir ----
local function process_inlines(inlines)
  local out = List:new()
  local i, n = 1, #inlines

  local function is_textlike(el)
    return el.t == "Str" or el.t == "Space" or el.t == "SoftBreak"
  end

  while i <= n do
    if is_textlike(inlines[i]) then
      -- bir koşu topla
      local run = List:new()
      local j = i
      while j <= n and is_textlike(inlines[j]) do
        run:insert(inlines[j]); j = j + 1
      end

      local text, map = run_linearize(run)
      local hits = find_plates_in_text(text)
      local rebuilt = rebuild_run_from_hits(run, text, map, hits)
      out:extend(rebuilt)
      i = j
    else
      local el = inlines[i]
      -- ZATEN plate sınıfına sahip bir Span ise, **içine girmeden** bırak
      if el.t == "Span" and has_class(el.attr, "plate") then
        out:insert(el)
      else
        -- diğer kapsayıcıların içine rekürsif gir
        if el.content and type(el.content) == "table" then
          el.content = process_inlines(el.content)
        end
        out:insert(el)
      end
      i = i + 1
    end
  end
  return out
end

function M.Pandoc(doc)
  -- meta’yı burada yükle (garanti)
  PLATES = nil
  load_plates_from_meta(doc.meta)

  -- istersen debug:
  -- local cnt = 0; if PLATES then for _ in pairs(PLATES) do cnt = cnt + 1 end end
  -- io.stderr:write(string.format("[span-plate] plates loaded: %d\n", cnt))

  -- meta yoksa dokümanı olduğu gibi döndür
  if not PLATES then return doc end

  -- inlines işleyicisiyle dokümanı yürüt
  return doc:walk({ Inlines = function(inl) return process_inlines(inl) end })
end

return M

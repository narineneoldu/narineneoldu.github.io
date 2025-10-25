-- line_speakers.lua (time-badge dostu)
-- Konuşmacı adını (başta) tespit eder, anchor'ları korur,
-- UTTERANCE içeriğini *inline* olarak olduğu gibi bırakır (time-badge vb. bozulmaz).

-- --- guard: index.qmd'te filtreden çık ---
local input = (quarto and quarto.doc and quarto.doc.input_file) or ""
if type(input) == "string" and input ~= "" then
  -- Yalın dosya adını çek (slash veya backslash'tan sonraki parça)
  local fname = input:match("([^/\\]+)$") or input
  if fname == "index.qmd" then
    return {}  -- bu dosyada filtre tamamen devre dışı
  end
end
-- --- /guard ---

local utils = require 'pandoc.utils'

-- --- groups (JS ile birebir) ---
local groups = {
  ["suspect"]       = {"Nevzat Bahtiyar", "Yüksel Güran", "Enes Güran",
                       "Sanık Enes Güran", "Salim Güran", "Sanık Salim Güran"},
  ["witness"]       = {"Gazal Bahtiyar", "Baran Güran", "Maşşallah Güran",
                       "Osman Güran", "Muhammed Kaya"
  },
  ["judge"]         = {"Mahkeme Başkanı","Mahkeme Üye Hakimi",
                       "Presiding Judge", "Associate Judge"},
  ["prosecutor"]    = {"Duruşma Savcısı", "Trial Prosecutor"},
  ["kdb"]           = {"Av. Nahit Eren", "Av. Aydın Özdemir", "Av. Erdem Kaya",
                       "Av. Mehdi Özdemir","Av. Asya Cemre Işık",
                       "Av. Berat Kocakaya","Av. Derya Yıldırım",
                       "Av. Metin Arkaş",
                       "Law. Nahit Eren", "Law. Aydın Özdemir", "Law. Erdem Kaya",
                       "Law. Mehdi Özdemir","Law. Asya Cemre Işık",
                       "Law. Berat Kocakaya","Law. Derya Yıldırım",
                       "Law. Metin Arkaş"
  },
  ["ashb"]          = {"Av. Şeyhmus Erdoğan", "Av. Abdullah Yılmaz",
                       "Av. Elif Aslı Şahin Torun", "Av. Emine Akçalı",
                       "Law. Şeyhmus Erdoğan", "Law. Abdullah Yılmaz",
                       "Law. Elif Aslı Şahin Torun", "Law. Emine Akçalı"
  },
  ["mudafi-enes"]   = {"Av. Mahir Akbilek", "Av. Mustafa Demir",
                       "Av. Muhammed Fatih Demir", "Av. Recep Kızılok",
                       "Law. Mahir Akbilek", "Law. Mustafa Demir",
                       "Law. Muhammed Fatih Demir", "Law. Recep Kızılok"
  },
  ["mudafi-yuksel"] = {"Av. Yılmaz Demiroğlu", "Av. Tuncay Erkuş",
                       "Av. Furkan Çakır","Av. Doğuş Can Kurucu",
                       "Sanık Yüksel Müdafi",
                       "Law. Yılmaz Demiroğlu", "Law. Tuncay Erkuş",
                       "Law. Furkan Çakır","Law. Doğuş Can Kurucu",
                       "Defense Counsel for Yüksel Güran"
  },
  ["mudafi-salim"]  = {"Av. Onur Akdağ", "Law. Onur Akdağ"},
  ["mudafi-nevzat"] = {"Av. Ali Eryılmaz", "Av. Adnan Ataş",
                       "Law. Ali Eryılmaz", "Law. Adnan Ataş"
  },
  ["others"] = {"Tercüman", "Avukat Hanım", "Interpreter", "Female Lawyer"},
}

local nameToClass, ALL_NAMES = {}, {}
for cls, names in pairs(groups) do
  for _, n in ipairs(names) do
    nameToClass[n] = cls
    table.insert(ALL_NAMES, n)
  end
end
table.sort(ALL_NAMES, function(a,b) return #a > #b end) -- en uzun önce

-- --- yardımcılar ---
local function has_class(attr, targets)
  if not attr or not attr.classes then return false end
  for _, c in ipairs(attr.classes) do
    for __, t in ipairs(targets) do
      if c == t then return true end
    end
  end
  return false
end

local function is_anchor_inline(el)
  if el.t == "Span" and has_class(el.attr, {"line-anchor","la-link","anchor"}) then return true end
  if el.t == "Link" and has_class(el.attr, {"line-anchor","la-link","anchor"}) then return true end
  if el.t == "RawInline" and el.format == "html" then
    local s = el.text or ""
    if s:match("[<]a%s+[^>]*class=[\"'][^\"']*line%-anchor[^\"']*[\"']") or
       s:match("[<]a%s+[^>]*class=[\"'][^\"']*la%-link[^\"']*[\"']") or
       s:match("[<]a%s+[^>]*class=[\"'][^\"']*anchor[^\"']*[\"']") then
      return true
    end
  end
  return false
end

local function take_leading_anchors(inlines)
  local anchors = pandoc.List()
  local rest = pandoc.List(inlines)
  while #rest > 0 and is_anchor_inline(rest[1]) do
    anchors:insert(rest[1]); rest:remove(1)
  end
  return anchors, rest
end

local function already_processed(inlines)
  for _, el in ipairs(inlines) do
    if el.t == "Span" and has_class(el.attr, {"speaker"}) then
      return true
    end
  end
  return false
end

local function stringify(inlines)
  return utils.stringify(pandoc.Inlines(inlines))
end

-- Başlangıçtaki whitespace uzunluğunu bul
local function leading_space_len(s)
  local _, j = s:find("^%s*")
  return (j or 0)
end

-- Baş prefix’i (karakter sayısı) kadar inline akışından düş.
-- Str/Space/SoftBreak/LineBreak üzerinde ilerler; diğer inline’ları
-- (ör. time-badge span) prefix tüketimi bitmeden görülürse tüketimi durdurur.
local function drop_prefix_chars(inlines, n)
  if n <= 0 then return pandoc.List(inlines) end
  local out = pandoc.List()
  local i = 1
  while i <= #inlines do
    local el = inlines[i]
    local t = el.t

    if n <= 0 then
      -- prefix bitti, kalanları aynen aktar
      for j=i,#inlines do out:insert(inlines[j]) end
      break
    end

    if t == "Space" or t == "SoftBreak" or t == "LineBreak" then
      -- stringify bunları 1 karakter sayar
      n = n - 1
      -- tamamen tüketildi, ekleme yok
      i = i + 1

    elseif t == "Str" then
      local txt = el.text or ""
      local L = #txt
      if n >= L then
        -- tüm Str tüketildi
        n = n - L
        i = i + 1
      else
        -- Str’nin başını kes, kalanı bırak
        local rest = txt:sub(n+1)
        out:insert(pandoc.Str(rest))
        n = 0
        -- kalan inline’ların hepsini aktar
        for j=i+1,#inlines do out:insert(inlines[j]) end
        break
      end

    else
      -- Diğer inline türlerine (Span, Emph, Link, RawInline vb.) gelmeden
      -- prefix bitmiş olmalıydı. Yine de güvenli olmak için:
      if n > 0 then
        -- Buraya geldiysek, prefix tüketimi sırasında beklenmedik inline var.
        -- Prefix'i burada sonlandırıp geri kalan her şeyi aynen aktaralım.
        out:insert(el)
        for j=i+1,#inlines do out:insert(inlines[j]) end
        break
      end
    end
  end

  if n <= 0 and #out == 0 then
    -- prefix tam Str üzerinde bitti ve hemen devam yoksa, boş döndük;
    -- bu durumda kalanları ekle.
    -- (üstteki “break” dalında zaten eklendiği için genelde gerekmez)
  end

  return out
end

local function match_name_and_prefix_len(rest_inlines)
  local txt = stringify(rest_inlines)
  if txt == "" then return nil end

  local ls = leading_space_len(txt)          -- baştaki boşluklar
  local tail = txt:sub(ls + 1)

  for _, name in ipairs(ALL_NAMES) do
    local pat = "^" .. name:gsub("(%W)","%%%1") .. "%s*:%s*(.*)$"
    local utter = tail:match(pat)
    if utter ~= nil then
      local consumed_in_tail = #tail - #utter           -- "Name : " kısmı
      local total_prefix = ls + consumed_in_tail        -- toplam tüketilecek karakter
      return name, total_prefix
    end
  end
  return nil
end

local function build_output_inlines(anchors, speakerName, utter_inlines, cls)
  local out = pandoc.List()
  for _, a in ipairs(anchors) do out:insert(a) end

  local sp = pandoc.Span(
    { pandoc.Str(speakerName), pandoc.Space(), pandoc.Str(":") },
    pandoc.Attr("", {"speaker", cls or "speaker-unknown"})
  )
  out:insert(sp)
  out:insert(pandoc.Space())

  -- UTTERANCE: orijinal inline’ları KORU (time-badge vb.)
  local ut = pandoc.Span(utter_inlines, pandoc.Attr("", {"utterance"}))
  out:insert(ut)

  return out
end

local function first_texty(inlines)
  local el = inlines[1]
  if not el then return false end
  if el.t == "Str" or el.t == "SoftBreak" or el.t == "Space" then return true end
  if el.t == "RawInline" and (el.format == "html" or el.format == "latex") then return true end
  return false
end

-- --- dönüştürücü ---
local function transform_block(blk)
  if blk.t ~= "Para" and blk.t ~= "Plain" then return nil end
  if already_processed(blk.content) then return nil end

  local anchors, rest = take_leading_anchors(blk.content)
  if #rest == 0 or not first_texty(rest) then
    -- anchor'ları geri koy
    if #anchors > 0 then
      local restored = pandoc.List()
      for _, a in ipairs(anchors) do restored:insert(a) end
      for _, r in ipairs(rest) do restored:insert(r) end
      blk.content = restored
    end
    return nil
  end

  local speakerName, prefix_chars = match_name_and_prefix_len(rest)
  if not speakerName then
    -- eşleşme yok; anchor'ları geri koy
    if #anchors > 0 then
      local restored = pandoc.List()
      for _, a in ipairs(anchors) do restored:insert(a) end
      for _, r in ipairs(rest) do restored:insert(r) end
      blk.content = restored
    end
    return nil
  end

  -- prefix’i inline akışından *karakter bazında* düş → KALAN inline’lar utterance
  local utter_inlines = drop_prefix_chars(rest, prefix_chars)
  -- baştaki tekil Space/SoftBreak/LineBreak kırp
  while #utter_inlines > 0 do
    local t = utter_inlines[1].t
    if t == "Space" or t == "SoftBreak" or t == "LineBreak" then
      table.remove(utter_inlines, 1)
    else
      break
    end
  end

  local cls = nameToClass[speakerName] or "speaker-unknown"
  local new_inlines = build_output_inlines(anchors, speakerName, utter_inlines, cls)

  if blk.t == "Para" then
    return pandoc.Para(new_inlines)
  else
    return pandoc.Plain(new_inlines)
  end
end

return {
  { Para = transform_block, Plain = transform_block }
}

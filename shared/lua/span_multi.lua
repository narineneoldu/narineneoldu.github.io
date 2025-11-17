-- ../shared/lua/span_multi.lua
-- Unified single-pass inline processor:
--   plate / phone / time / date / unit / amount / parenthesis /
--   record number / abbreviation
--
-- This replaces the older family of filters:
--   span_time.lua, span_phone.lua, span_plate.lua, span_date.lua,
--   span_unit.lua, span_amount.lua, span_paranthesis.lua,
--   span_record_number.lua, span_abbr.lua
--
-- The idea:
--   * linearize inline runs into a plain string
--   * run all detectors on that string
--   * merge overlapping hits with priority
--   * rebuild inlines with <span class="..."> wrappers
--   * then run the quote filter to wrap "..." in <span class="quote">

package.path = package.path .. ';../shared/lua/?.lua'

local Inline = require 'inline_utils'
local List   = require 'pandoc.List'

----------------------------------------------------------------
-- GLOBAL CONFIG / TABLES
----------------------------------------------------------------

-- Utility specs:
--  * key   : logical name ("time", "amount", "plate", ...)
--  * pri   : priority when hits overlap (higher = wins)
--  * class : default CSS class for simple spans (optional)
--
-- The Lua module name is derived automatically as: "utils_" .. key
local UTIL_SPECS = {
  -- simple kinds
  { key = "time",        pri = 9, class = "time" },
  { key = "phone",       pri = 8 },               -- istersen buraya da class ekleyebilirsin
  { key = "plate",       pri = 7 },
  { key = "amount",      pri = 6, class = "amount" },

  -- unit, paranthesis sırası ve önceliği:
  { key = "unit",        pri = 5 },               -- 4 minutes gibi şeyler ÖNEMLİ

  { key = "record",      pri = 4, class = "record" },
  { key = "abbr",        pri = 3 },
  { key = "date",        pri = 2, class = "date" },
  { key = "day",         pri = 0, class = "day" },
}

-- Loaded utility modules will be stored here: UTIL[key] = module
local UTIL = {}

-- Detector descriptors: for each spec, how to get its module
local DETECTORS = {}

-- Classes we never want to re-process once already wrapped
-- (i.e. if an inline is already inside one of these, we skip it).
local SKIP_CLASS = {}

-- Merge priority: kind -> numeric priority
local PRIORITY = {}

-- Map from kind/key -> spec (for simple class mapping)
local KIND_SPEC = {}

-- Build DETECTORS, PRIORITY and KIND_SPEC from UTIL_SPECS in one pass
for _, spec in ipairs(UTIL_SPECS) do
  if spec.key then
    -- detectors
    DETECTORS[#DETECTORS + 1] = {
      name = spec.key,
      get  = function() return UTIL[spec.key] end,
    }

    -- priority map
    if spec.pri then
      PRIORITY[spec.key] = spec.pri
    end

    -- kind-to-spec map (used by build_span for simple class assignment)
    KIND_SPEC[spec.key] = spec

    -- existing spans with this key/class should never be re-processed
    SKIP_CLASS[spec.key] = true
    if spec.class then
      SKIP_CLASS[spec.class] = true
    end
  end
end

----------------------------------------------------------------
-- MODULE STATE (dictionaries coming from metadata)
----------------------------------------------------------------

local M = {}

-- Optional dictionaries loaded from document metadata
--   * PLATES: plate text -> tooltip
--   * PHONES: phone key  -> tooltip
--   * ABBR  : abbreviation -> full text
local PLATES = nil
local PHONES = nil
local ABBR   = nil

----------------------------------------------------------------
-- UTILITY LOADING HELPERS
----------------------------------------------------------------

-- Safe require: returns nil on failure instead of throwing
local function safe_require(modname)
  local ok, mod = pcall(require, "utils_" .. modname)
  if ok then return mod end
  return nil
end

-- Initialize a single utility module.
-- Tries "base_modname_en" first if lang == "en", then falls back to base_modname.
local function init_util(lang, base_modname)
  local mod

  if lang == "en" then
    -- Example: utils_time_en, utils_date_en
    mod = safe_require(base_modname .. "_en")
    if mod then
      return mod
    end
  end

  -- Default / TR fallback: utils_time, utils_date, ...
  mod = safe_require(base_modname)
  if not mod then
    io.stderr:write(
      string.format("⚠️  No utility loaded (%s[_en] missing)\n", base_modname)
    )
  end
  return mod
end

-- Initialize all utility modules according to UTIL_SPECS
local function init_all_utils(lang)
  for _, spec in ipairs(UTIL_SPECS) do
    UTIL[spec.key] = init_util(lang, spec.key)
  end
end

----------------------------------------------------------------
-- METADATA HELPERS (for plates / phones / abbreviations)
----------------------------------------------------------------

-- Convert a meta table entry into a plain Lua table of string -> string
local function load_dict(meta, key)
  if not meta then return nil end
  local dict = meta[key] or (meta.metadata and meta.metadata[key])
  if type(dict) ~= "table" then return nil end

  local t = {}
  for k, v in pairs(dict) do
    local kk = pandoc.utils.stringify(k)
    local vv = pandoc.utils.stringify(v)
    if kk ~= "" and vv ~= "" then
      -- normalize whitespace and trim
      kk = kk:gsub("%s+", " "):match("^%s*(.-)%s*$")
      t[kk] = vv
    end
  end
  return next(t) and t or nil
end

-- Meta handler: called once per document
function M.Meta(m)
  if not PLATES then PLATES = load_dict(m, "plates") end
  if not PHONES then PHONES = load_dict(m, "phones") end
  if not ABBR   then ABBR   = load_dict(m, "abbr")   end
end

----------------------------------------------------------------
-- HIT MERGING (resolve overlaps by PRIORITY)
----------------------------------------------------------------

local function merge_hits_from_lists(hit_lists)
  -- Flatten all hit lists into a single array
  local all = {}
  for _, lst in ipairs(hit_lists) do
    for _, h in ipairs(lst) do
      all[#all + 1] = h
    end
  end

  -- Sort by start index, then by priority (descending)
  table.sort(all, function(a, b)
    if a.s == b.s then
      return (PRIORITY[a.kind] or 0) > (PRIORITY[b.kind] or 0)
    else
      return a.s < b.s
    end
  end)

  -- Greedy non-overlapping selection (yüksek öncelikli olanlar zaten başta)
  local out = {}
  for _, h in ipairs(all) do
    local overlap = false
    for _, k in ipairs(out) do
      if not (h.e < k.s or h.s > k.e) then
        overlap = true
        break
      end
    end
    if not overlap then
      out[#out + 1] = h
    end
  end

  return out
end

----------------------------------------------------------------
-- SPAN BUILDING
----------------------------------------------------------------

local function span_with_class(tok, class, attrs)
  return pandoc.Span(
    { pandoc.Str(tok) },
    pandoc.Attr("", { class }, attrs or {})
  )
end

-- Convert a matched token + hit into the appropriate span
local function build_span(tok, hit)
  -- trim surrounding spaces inside the span
  tok = tok:gsub("^%s*(.-)%s*$", "%1")

  -- 1) dictionary-based kinds: plate / phone / abbr
  if hit.kind == "plate" then
    local tip = PLATES and PLATES[tok:gsub("%s+", " ")]
    return span_with_class(tok, "plate",
      tip and { ["data-title"] = tip } or nil
    )

  elseif hit.kind == "phone" then
    local tip = PHONES and PHONES[hit.key]
    return span_with_class(tok, "phone",
      tip and { ["data-title"] = tip } or nil
    )

  elseif hit.kind == "abbr" then
    local title = (ABBR and ABBR[tok]) or tok
    return pandoc.Span(
      { pandoc.Str(tok) },
      pandoc.Attr(
        "",
        { "abbr" },
        {
          { "data-title", title },
          { "tabindex",   "0"    },
          { "role",       "note" },
          { "aria-label", title  },
        }
      )
    )

  -- 2) unit: dynamic class (e.g. "unit", "amount-try", etc.)
  elseif hit.kind == "unit" then
    local cls = hit.class or "unit"
    -- once we create a span with this class, never re-process it
    SKIP_CLASS[cls] = true
    return span_with_class(tok, cls)

  -- 3) simple kinds: use class from KIND_SPEC (time, date, amount, ...)
  else
    local spec = KIND_SPEC[hit.kind]
    if spec and spec.class then
      return span_with_class(tok, spec.class)
    end
  end

  -- If we get here, we do not wrap this token
  return nil
end

----------------------------------------------------------------
-- INLINE PROCESSOR (single pass, all detectors)
----------------------------------------------------------------

local function process_inlines(inlines)
  local out = List:new()
  local i, n = 1, #inlines

  while i <= n do
    if Inline.is_textlike(inlines[i]) then
      -- Collect a contiguous "text-like" run (Str, Space, SoftBreak, etc.)
      local run = List:new()
      local j = i
      while j <= n and Inline.is_textlike(inlines[j]) do
        run:insert(inlines[j])
        j = j + 1
      end

      -- Convert the run to a linear string and a position map
      local text, map = Inline.linearize_run(run)

      -- Run all detectors on the linearized text
      local hit_lists = {}
      for _, spec in ipairs(DETECTORS) do
        local util = spec.get()
        if util and util.find then
          local hits = util.find(text)
          if hits and #hits > 0 then
            hit_lists[#hit_lists + 1] = hits
          end
        end
      end

      -- Merge hits and rebuild the run with spans
      local hits = {}
      if #hit_lists > 0 then
        hits = merge_hits_from_lists(hit_lists)
      end
      local rebuilt = Inline.rebuild_run(run, text, map, hits, build_span)

      out:extend(rebuilt)
      i = j

    else
      local el = inlines[i]

      -- If this is already a span with one of our classes, do not re-process
      if el.t == "Span" and el.attr and el.attr.classes then
        local skip = false
        for _, cls in ipairs(el.attr.classes) do
          if SKIP_CLASS[cls] then
            skip = true
            break
          end
        end
        if skip then
          out:insert(el)
          i = i + 1
          goto continue
        end
      end

      -- Recursively process nested inline content (e.g. inside links/spans)
      if el.content and type(el.content) == "table" then
        el.content = process_inlines(el.content)
      end

      out:insert(el)
      i = i + 1
    end
    ::continue::
  end

  return out
end

----------------------------------------------------------------
-- QUOTE FILTER
-- Wraps " ... " segments in <span class="quote">,
-- without touching:
--   * existing .quote / .time / .time-badge spans
--   * bold/italic structure
----------------------------------------------------------------

local function quote_has_class(attr, names)
  if not attr or not attr.classes then return false end
  for _, c in ipairs(attr.classes) do
    for __, n in ipairs(names) do
      if c == n then return true end
    end
  end
  return false
end

local function quote_process_inlines(inlines)
  local out       = List:new()
  local buf       = List:new()  -- buffer for content inside quotes
  local in_quote  = false

  local function flush_buffer(as_span)
    if #buf == 0 then return end
    if as_span then
      out:insert(pandoc.Span(buf, pandoc.Attr('', {'quote'})))
    else
      for _, x in ipairs(buf) do out:insert(x) end
    end
    buf = List:new()
  end

  local function emit(el)
    if in_quote then buf:insert(el) else out:insert(el) end
  end

  for _, el in ipairs(inlines) do
    local t = el.t

    -- Do not descend into Strong / Emph; keep them as-is
    if t == 'Strong' or t == 'Emph' then
      emit(el)

    -- Do not touch existing .quote / .time-badge / .time spans
    elseif t == 'Span' and quote_has_class(el.attr, {'quote', 'time-badge', 'time'}) then
      emit(el)

    -- Pandoc "Quoted" inline: wrap it as a single <span.quote>
    elseif t == 'Quoted' then
      emit(pandoc.Span({ el }, pandoc.Attr('', {'quote'})))

    -- Recurse into Span content
    elseif t == 'Span' then
      local new_content = quote_process_inlines(el.content)
      emit(pandoc.Span(new_content, el.attr))

    -- Recurse into Link content, keep target/title/attributes
    elseif t == 'Link' then
      local new_content = quote_process_inlines(el.content)
      emit(pandoc.Link(new_content, el.target, el.title, el.attr))

    -- Handle plain strings to detect " characters and manage quote state
    elseif t == 'Str' then
      local s = el.text or ""
      if s:find('"', 1, true) == nil then
        emit(el)
      else
        local i, n = 1, #s
        while i <= n do
          local qpos = s:find('"', i, true)
          if not qpos then
            local tail = s:sub(i)
            if #tail > 0 then emit(pandoc.Str(tail)) end
            break
          end
          -- text before the quote
          if qpos > i then emit(pandoc.Str(s:sub(i, qpos - 1))) end
          -- the quote character itself
          emit(pandoc.Str('"'))
          -- toggle quote state
          in_quote = not in_quote
          -- if we just CLOSED a quote, flush the buffer as a single span
          if not in_quote then
            flush_buffer(true)
          end
          i = qpos + 1
        end
      end

    else
      -- Other inline types: SmallCaps, Strikeout, Superscript, etc. stay as-is
      emit(el)
    end
  end

  -- If we ended inside an open quote, flush without wrapping in a span
  if in_quote then flush_buffer(false) end
  return out
end

local function quote_process_block(b)
  -- Do not touch headers
  if b.t == 'Header' then return nil end

  if b.t == 'Para' then
    return pandoc.Para(quote_process_inlines(b.content))
  elseif b.t == 'Plain' then
    return pandoc.Plain(quote_process_inlines(b.content))
  end
  return nil
end

local QuoteFilter = {
  Para  = quote_process_block,
  Plain = quote_process_block,
}

----------------------------------------------------------------
-- PARENTHESIS FILTER (UTF-8 safe)
-- Wraps (...) in <span class="paranthesis"> ... </span>
-- İçerideki span'lere / Türkçe karakterlere dokunmadan sadece dıştan sarar.
----------------------------------------------------------------

local function paren_process_inlines(inlines)
  local out      = List:new()
  local buf      = List:new()
  local in_paren = false

  local function flush_buf_as_is()
    for _, x in ipairs(buf) do
      out:insert(x)
    end
    buf = List:new()
  end

  local function flush_buf_as_span()
    if #buf == 0 then return end
    out:insert(pandoc.Span(buf, pandoc.Attr("", { "paranthesis" })))
    buf = List:new()
  end

  for _, el in ipairs(inlines) do
    if el.t == "Str" then
      local s = el.text or ""
      local n = #s
      local p = 1

      while p <= n do
        -- sıradaki "(" veya ")" pozisyonunu bul
        local q = s:find("[()]", p)
        if not q then
          -- artık parantez yok, kalan her şeyi tek parça bırak
          local tail = s:sub(p)
          if tail ~= "" then
            local str = pandoc.Str(tail)
            if in_paren then
              buf:insert(str)
            else
              out:insert(str)
            end
          end
          break
        end

        -- paranteze kadar olan kısmı olduğu gibi aktar
        if q > p then
          local prefix = s:sub(p, q - 1)
          if prefix ~= "" then
            local str = pandoc.Str(prefix)
            if in_paren then
              buf:insert(str)
            else
              out:insert(str)
            end
          end
        end

        -- şimdi tek karakterlik parantez
        local ch = s:sub(q, q)
        if ch == "(" then
          if in_paren then
            -- zaten parantez içindeysek, sadece buff'a ekle
            buf:insert(pandoc.Str(ch))
          else
            -- yeni bir parantez bölgesi başlat
            in_paren = true
            buf:insert(pandoc.Str(ch))
          end
        elseif ch == ")" then
          if in_paren then
            buf:insert(pandoc.Str(ch))
            -- parantez bölgesini span olarak sar
            flush_buf_as_span()
            in_paren = false
          else
            -- eşleşmeyen kapanış parantezi: olduğu gibi bırak
            out:insert(pandoc.Str(ch))
          end
        end

        p = q + 1
      end

    else
      -- Str olmayan inline'lar (Span, Link, Emph, vs.)
      if in_paren then
        buf:insert(el)
      else
        out:insert(el)
      end
    end
  end

  -- eğer parantez hiç kapanmadıysa, buffer'ı span'siz bırak
  if in_paren and #buf > 0 then
    flush_buf_as_is()
  end

  return out
end

local function paren_process_block(b)
  if b.t == "Para" then
    return pandoc.Para(paren_process_inlines(b.content))
  elseif b.t == "Plain" then
    return pandoc.Plain(paren_process_inlines(b.content))
  end
  return nil
end

local ParenFilter = {
  Para  = paren_process_block,
  Plain = paren_process_block,
}
----------------------------------------------------------------
-- PANDOC ENTRY POINT
----------------------------------------------------------------

function M.Pandoc(doc)
  -- Detect language from document metadata
  local lang = pandoc.utils.stringify(doc.meta.lang or "")
  init_all_utils(lang)

  local PhoneUtil = UTIL.phone
  local AbbrUtil  = UTIL.abbr

  if PhoneUtil and PHONES and PhoneUtil.set_dict then
    PhoneUtil.set_dict(PHONES)
  end

  if AbbrUtil and ABBR and AbbrUtil.set_dict then
    AbbrUtil.set_dict(ABBR)
  end

  -- Sadece paragraf benzeri blokların içindeki inlineları işle,
  -- Header içini olduğu gibi bırak
  local spanFilter = {
    Para = function(p)
      p.content = process_inlines(p.content)
      return p
    end,
    Plain = function(p)
      p.content = process_inlines(p.content)
      return p
    end,
    Header = function(h)
      -- başlıklarda hiçbir şey yapma
      return h
    end,
  }

  return doc:walk(spanFilter)
end

----------------------------------------------------------------
-- EXPORT
----------------------------------------------------------------

return {
  M,           -- 1) unit/time/abbr vs. hepsi
  ParenFilter, -- 2) sonradan (...) sarmalayan filter
  QuoteFilter, -- 3) en son "..." için quote span'i
}

-- ../shared/lua/span_multi.lua
-- Unified single-pass inline processor:
--   plate / phone / time / date / unit / amount / parenthesis /
--   record number / abbreviation / refs
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
  { key = "phone",       pri = 7 },
  { key = "plate",       pri = 6 },
  { key = "unit",        pri = 5 },
  { key = "abbr",        pri = 4 },
  { key = "time",        pri = 3, class = "time" },
  { key = "record",      pri = 2, class = "record" },
  { key = "date",        pri = 1, class = "date" },
  { key = "day",         pri = 0, class = "day" },
  { key = "participant", pri = 8 },
  { key = "refs",        pri = 20 },
}

-- Loaded utility modules will be stored here: UTIL[key] = module
local UTIL       = {}
local DETECTORS  = {}
local SKIP_CLASS = {}
local PRIORITY   = {}
local KIND_SPEC  = {}

-- Refs util, global scope so build_span görebilsin
local REFS_UTIL  = nil

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

-- existing spans we *never* want to touch
SKIP_CLASS["speaker"] = true -- speaker/utterance vs
SKIP_CLASS["span-multi-skip"] = true -- navigation envelope ve benzeri alanlar

local function has_skip_class(el)
  if not (el.attr and el.attr.classes) then
    return false
  end
  for _, cls in ipairs(el.attr.classes) do
    if SKIP_CLASS[cls] then
      return true
    end
  end
  return false
end

----------------------------------------------------------------
-- MODULE STATE (dictionaries coming from metadata)
----------------------------------------------------------------
local M = {}

local function load_skip_paths(meta)
  SKIP_PATHS = {}
  if not meta then return end

  local raw = meta["span-multi-skip"] or (meta.metadata and meta.metadata["span-multi-skip"])
  if type(raw) ~= "table" then return end

  for _, item in ipairs(raw) do
    local s = pandoc.utils.stringify(item)
    if s ~= "" then
      -- normalize slashes; assume paths in yaml are like "blog/..."
      s = s:gsub("\\", "/")
      SKIP_PATHS[s] = true
    end
  end
end

function M.Meta(m)
  load_skip_paths(m)
end

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
    mod = safe_require(base_modname .. "_en")
    if mod then
      return mod
    end
  end

  mod = safe_require(base_modname)
  if not mod then
    io.stderr:write(
      string.format("⚠️  No utility loaded (utils_%s missing)\n", base_modname)
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
    if a.s ~= b.s then
      return a.s < b.s
    end

    local pa = PRIORITY[a.kind] or 0
    local pb = PRIORITY[b.kind] or 0
    if pa ~= pb then
      return pa > pb
    end

    local len_a = (a.e - a.s)
    local len_b = (b.e - b.s)
    return len_a > len_b
  end)

  -- Greedy non-overlapping selection
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
    local attrs = nil
    if hit.label and hit.label ~= "" then
      attrs = { ["data-title"] = hit.label }
    end
    return span_with_class(tok, "plate", attrs)

  elseif hit.kind == "phone" then
    local attrs = nil
    if hit.label and hit.label ~= "" then
      attrs = { ["data-title"] = hit.label }
    end
    return span_with_class(tok, "phone", attrs)

  elseif hit.kind == "abbr" then
    local title = hit.label or tok
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
    SKIP_CLASS[cls] = true
    return span_with_class(tok, cls)

  elseif hit.kind == "participant" then
    local group = hit.group or "unknown"
    local attrs = {}

    SKIP_CLASS["participant"] = true
    SKIP_CLASS[group]         = true

    if hit.label and hit.label ~= "" then
      attrs[#attrs + 1] = { "data-title", hit.label }
    end

    return pandoc.Span(
      { pandoc.Str(tok) },
      pandoc.Attr("", { "participant", group }, attrs)
    )

  -- 3) refs: {text}[n], word[n], [n] → delegasyon utils_refs.build'e
  elseif hit.kind == "refs" then
    if REFS_UTIL and REFS_UTIL.build then
      return REFS_UTIL.build(tok, hit)
    else
      return nil
    end

  -- 4) simple kinds: use class from KIND_SPEC (time, date, day, record, ...)
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
      ----------------------------------------------------------------
      -- TEXTLIKE RUN: Str / Space / SoftBreak → utils_* çalışır
      ----------------------------------------------------------------
      local run = List:new()
      local j = i
      while j <= n and Inline.is_textlike(inlines[j]) do
        run:insert(inlines[j])
        j = j + 1
      end

      local text, map = Inline.linearize_run(run)

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

      local hits = {}
      if #hit_lists > 0 then
        hits = merge_hits_from_lists(hit_lists)
      end
      local rebuilt = Inline.rebuild_run(run, text, map, hits, build_span)

      out:extend(rebuilt)
      i = j

    else
      local el = inlines[i]

      ----------------------------------------------------------------
      -- NEW: NEVER process inside links → no utils_* under <a>
      ----------------------------------------------------------------
      if el.t == "Link" then
        -- Do NOT recurse into el.content
        out:insert(el)
        i = i + 1
        goto continue
      end

      ----------------------------------------------------------------
      -- Skip-class spans (örn. span-multi-skip, participant vs.)
      ----------------------------------------------------------------
      if (el.t == "Span") and has_skip_class(el) then
        out:insert(el)
        i = i + 1
        goto continue
      end

      ----------------------------------------------------------------
      -- Other containers: recurse into content
      ----------------------------------------------------------------
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
--   * existing .quote / .time spans
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
  local buf       = List:new()
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

    if t == 'Strong' or t == 'Emph' then
      emit(el)

    elseif t == 'Span' and quote_has_class(el.attr, {'quote', 'time'}) then
      emit(el)

    elseif t == 'Quoted' then
      emit(pandoc.Span({ el }, pandoc.Attr('', {'quote'})))

    elseif t == 'Span' then
      local new_content = quote_process_inlines(el.content)
      emit(pandoc.Span(new_content, el.attr))

    elseif t == 'Link' then
      local new_content = quote_process_inlines(el.content)
      emit(pandoc.Link(new_content, el.target, el.title, el.attr))

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
          if qpos > i then emit(pandoc.Str(s:sub(i, qpos - 1))) end
          emit(pandoc.Str('"'))
          in_quote = not in_quote
          if not in_quote then
            flush_buffer(true)
          end
          i = qpos + 1
        end
      end

    else
      emit(el)
    end
  end

  if in_quote then flush_buffer(false) end
  return out
end

local function quote_process_block(b)
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
        local q = s:find("[()]", p)
        if not q then
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

        local ch = s:sub(q, q)
        if ch == "(" then
          if in_paren then
            buf:insert(pandoc.Str(ch))
          else
            in_paren = true
            buf:insert(pandoc.Str(ch))
          end
        elseif ch == ")" then
          if in_paren then
            buf:insert(pandoc.Str(ch))
            flush_buf_as_span()
            in_paren = false
          else
            out:insert(pandoc.Str(ch))
          end
        end

        p = q + 1
      end

    else
      if in_paren then
        buf:insert(el)
      else
        out:insert(el)
      end
    end
  end

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
-- HELPERS: decide whether to skip this document entirely
----------------------------------------------------------------

local function meta_requests_skip(meta)
  if not meta then return false end
  local flag = meta["disable-spanning"]
  if not flag then return false end

  local s = pandoc.utils.stringify(flag):lower()
  return (s == "true" or s == "yes" or s == "on" or s == "1")
end

-- Mark all inlines under Div#quarto-navigation-envelope so that
-- span_multi detectors (all utils_*) never touch its text.
local function mark_quarto_navigation_envelope(el)
  if el.t == "Div" and el.attr and el.attr.identifier == "quarto-navigation-envelope" then
    if el.content then
      for i, b in ipairs(el.content) do
        if b.t == "Para" or b.t == "Plain" then
          -- Tüm inline içeriği tek bir Span içine alıyoruz
          local span = pandoc.Span(
            b.content,
            pandoc.Attr("", { "span-multi-skip" })
          )
          if b.t == "Para" then
            el.content[i] = pandoc.Para({ span })
          else
            el.content[i] = pandoc.Plain({ span })
          end
        end
      end
    end
    -- Div’yi kendisiyle değiştiriyoruz (sadece içeriği modifiye ettik)
    return el
  end
  return nil
end

----------------------------------------------------------------
-- PANDOC ENTRY POINT
----------------------------------------------------------------

function M.Pandoc(doc)
  if meta_requests_skip(doc.meta) then
    return doc
  end

  local input = (quarto and quarto.doc and quarto.doc.input_file) or ""
  if type(input) == "string" and input ~= "" and SKIP_PATHS then
    local norm = input:gsub("\\", "/")
    if SKIP_PATHS[norm] then
      return doc
    end
  end

  local lang = pandoc.utils.stringify(doc.meta.lang or "")
  init_all_utils(lang)

  local PhoneUtil       = UTIL.phone
  local PlateUtil       = UTIL.plate
  local AbbrUtil        = UTIL.abbr
  local ParticipantUtil = UTIL.participant
  local RefsUtil        = UTIL.refs

  if PhoneUtil and PhoneUtil.set_dict then
    PhoneUtil.set_dict(doc.meta)
  end

  if PlateUtil and PlateUtil.set_dict then
    PlateUtil.set_dict(doc.meta)
  end

  if AbbrUtil and AbbrUtil.set_dict then
    AbbrUtil.set_dict(doc.meta)
  end

  if ParticipantUtil and ParticipantUtil.set_dict then
    ParticipantUtil.set_dict(doc.meta)
  end

  -- Inline refs: scan external-refs block and build ref table
  if RefsUtil and RefsUtil.init then
    RefsUtil.init(doc)
  end
  -- make it visible to build_span
  REFS_UTIL = RefsUtil

  -- external-refs div'lerini çıktıdan kaldır
  local function drop_external_refs_div(el)
    if el.t == "Div" and el.attr and el.attr.classes then
      for _, cls in ipairs(el.attr.classes) do
        if cls == "external-refs" then
          return pandoc.Null()  -- bu Div hiç yokmuş gibi davran
        end
      end
    end
    return nil
  end

  -- 1) external-refs Div'lerini tamamen kaldır
  doc = doc:walk({ Div = drop_external_refs_div })

  -- 2) navigation envelope (quarto-navigation-envelope) içindeki tüm metni
  --    span-multi-skip ile işaretle → bütün utils_* burayı görmez
  doc = doc:walk({ Div = mark_quarto_navigation_envelope })

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
      return h
    end,
  }

  doc = doc:walk(spanFilter)

  ----------------------------------------------------------------
  -- BURADAN SONRASI: Dış bağlantılar bölümünü ekleme
  --  * utils_refs.build_section(meta) hala { Header, OrderedList } döndürüyor
  --  * Biz bunu <div id="external-links-appendix"> içine alıyoruz
  --  * Header'ı gerçek <h2> olmaktan çıkarıp TOC'ye girmesini engelliyoruz
  ----------------------------------------------------------------
    if RefsUtil and RefsUtil.build_section then
    local extra_blocks = RefsUtil.build_section(doc.meta)

    if extra_blocks then
      -- Assumption: { Header, OrderedList } from utils_refs.build_section
      local hdr = extra_blocks[1]
      local lst = extra_blocks[2]

      -- Convert Header to a visual title (out of TOC)
      local heading_block
      if hdr and hdr.t == "Header" then
        heading_block = pandoc.Para({
          pandoc.Strong(hdr.content)
        })
      else
        heading_block = hdr
      end

      local container_blocks = {}

      if heading_block then
        container_blocks[#container_blocks + 1] = heading_block
      end
      if lst then
        container_blocks[#container_blocks + 1] = lst
      end

      if #container_blocks > 0 then
        local div = pandoc.Div(
          container_blocks,
          pandoc.Attr("external-links-appendix", { "default" })
        )

        -- Append external-links container at the end of the main content
        doc.blocks[#doc.blocks + 1] = div

                ----------------------------------------------------------------
        -- If there are more than 10 external refs, inject JS that:
        --  * hides items after the 10th and shows a "More..." button
        --  * automatically expands the list when a hidden ref is clicked
        ----------------------------------------------------------------
        local refs_count = 0
        if RefsUtil.count then
          refs_count = RefsUtil.count()
        end

        local limit = 10
        if refs_count > limit then
          local remaining = refs_count - limit
          local lang = pandoc.utils.stringify(doc.meta.lang or "tr"):lower()
          local button_label
          if lang == "en" then
            button_label = string.format("More (%d)...", remaining)
          else
            button_label = string.format("Devamı (%d)...", remaining)
          end

          local js = string.format([[
<script type="text/javascript">
document.addEventListener("DOMContentLoaded", function () {
  var container = document.getElementById("external-links-appendix");
  if (!container) return;

  var list = container.querySelector("ol");
  if (!list) return;

  var items = list.querySelectorAll("li");
  if (!items || items.length <= 10) return;

  var limit = 10;
  var btn = null;

  // Initially hide items after the 10th
  for (var i = limit; i < items.length; i++) {
    items[i].style.display = "none";
  }

  // Create the "More..." button
  btn = document.createElement("button");
  btn.type = "button";
  btn.id = "external-links-more";
  btn.className = "external-links-more btn btn-outline-primary";
  btn.textContent = "%s";

  btn.addEventListener("click", function () {
    // Show all remaining items when the button is clicked
    for (var i = limit; i < items.length; i++) {
      items[i].style.display = "";
    }
    if (btn.parentNode) {
      btn.parentNode.removeChild(btn);
    }
  });

  container.appendChild(btn);

  // Smart behavior: when a ref like [15] is clicked, expand if needed
  document.addEventListener("click", function (ev) {
    var node = ev.target;
    if (!node) return;

    // If the target is a text node, go up to its element parent
    if (node.nodeType === 3) {
      node = node.parentElement;
    }

    var link = null;

    // Prefer Element.closest when available
    if (node.closest) {
      link = node.closest("a.external-ref");
    } else {
      // Fallback traversal for older browsers
      var cur = node;
      while (cur) {
        if (
          cur.tagName &&
          cur.tagName.toLowerCase() === "a" &&
          typeof cur.className === "string" &&
          cur.className.indexOf("external-ref") !== -1
        ) {
          link = cur;
          break;
        }
        cur = cur.parentElement;
      }
    }

    if (!link) return;

    // Extract hash from href (e.g. "#extref-15")
    var href = link.getAttribute("href") || "";
    var hashIndex = href.indexOf("#");
    if (hashIndex < 0) return;

    var hash = href.slice(hashIndex);
    if (!hash || hash.indexOf("#extref-") !== 0) {
      return;
    }

    var targetId = hash.slice(1); // remove leading "#"
    var targetEl = document.getElementById(targetId);
    if (!targetEl) return;

    // If the target lives inside a hidden <li>, expand the list first
    if (items && items.length > limit) {
      var li = targetEl;
      while (li && li.tagName && li.tagName.toLowerCase() !== "li") {
        li = li.parentElement;
      }

      if (li && li.style.display === "none") {
        for (var i = limit; i < items.length; i++) {
          items[i].style.display = "";
        }
        if (btn && btn.parentNode) {
          btn.parentNode.removeChild(btn);
        }
      }
    }

    // Smoothly scroll to the target block
    try {
      targetEl.scrollIntoView({ behavior: "smooth", block: "start" });
    } catch (e) {
      // Fallback for very old browsers
      targetEl.scrollIntoView(true);
    }

    // Prevent the default anchor jump (we already scrolled)
    ev.preventDefault();
  });
});
</script>
]], button_label)

          doc.blocks[#doc.blocks + 1] = pandoc.RawBlock("html", js)
        end
      end
    end
  end

  return doc
end

----------------------------------------------------------------
-- EXPORT
----------------------------------------------------------------

return {
  M,           -- main span_multi filter
  ParenFilter, -- (...) paranthesis wrapper
  QuoteFilter, -- "..." quote span wrapper
}

-- ../shared/lua/utils_refs.lua
-- Detect inline reference patterns like:
--   {some text}[1]
--   word[1]
--   [1]
-- and turn them into "refs" hits for span_multi.lua.
--
-- It also parses an `external-refs` block in the document to
-- build a reference table (id -> { url, label, text }) and
-- can build a "External links" / "Dış bağlantılar" section,
-- and can build the actual inlines for these refs.

local utils = require "pandoc.utils"

local M = {}

-- REFS_MAP["1"] = { url = "...", label = "...", text = "..." }
local REFS_MAP  = {}
-- REFS_LIST is ordered, for building the bottom section
-- REFS_LIST[1] = { id = "1", url = "...", label = "...", text = "..." }
local REFS_LIST = {}

-- REF_BACK_IDS["1"] = "extrefref1"  -- inline geri dönüş anchor ID'si
local REF_BACK_IDS = {}

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

----------------------------------------------------------------------
-- Parsing external-refs block
----------------------------------------------------------------------

local function parse_ref_line(raw)
  -- Strip inline comments like: " ...  # comment"
  local line = raw:gsub("%s+#.*$", "")
  line = trim(line)

  if line == "" then
    return nil
  end

  -- Strip numeric prefix: "1. " / "2. " etc.
  line = line:gsub("^%s*%d+%.%s*", "")
  line = trim(line)

  if line == "" then
    return nil
  end

  -- Split by '|'
  local parts = {}
  for part in line:gmatch("[^|]+") do
    parts[#parts + 1] = trim(part)
  end

  local url, label, text_field

  if #parts == 1 then
    -- Only URL
    url = parts[1]

  elseif #parts == 2 then
    -- LABEL | URL
    label = parts[1]
    url   = parts[2]

  else
    -- LABEL | TEXT | URL (veya daha fazla, en son her zaman URL)
    label      = parts[1]
    text_field = parts[2]
    url        = parts[#parts]
  end

  if not url or url == "" then
    error("external-refs: every line must have a URL as the last field; offending line: " .. raw)
  end

  -- Post-process: "_" label'ı "yok" kabul et
  if label ~= nil and label == "" then
    label = nil
  end
  if text_field ~= nil and text_field == "" then
    text_field = nil
  end
  if label == "_" then
    label = nil
  end

  return {
    url   = url,
    label = label,
    text  = text_field,
  }
end

local function inlines_start_with_bar(inlines)
  for _, inl in ipairs(inlines) do
    if inl.t == "Space" or inl.t == "SoftBreak" then
      -- skip
    elseif inl.t == "Str" then
      local txt = inl.text or ""
      io.stderr:write("DEBUG: first inline Str text: '" .. txt .. "'\n")
      -- leading whitespace + '|'
      if txt:match("^%s*|") then
        return true
      else
        return false
      end
    else
      -- first anlamlı inline Str değilse, artık "| ..." durumu yok say
      return false
    end
  end
  return false
end

local function block_starts_with_bar(blk)
  -- Plain / Para
  if blk.t == "Plain" or blk.t == "Para" then
    return inlines_start_with_bar(blk.content or {})

  -- LineBlock: her satır bir inline list
  elseif blk.t == "LineBlock" then
    local lines = blk.content or {}
    for _, line in ipairs(lines) do
      if inlines_start_with_bar(line) then
        return true
      end
    end
    return false
  else
    return false
  end
end

-- Scan the document blocks for a Div with class "external-refs"
-- and build REFS_MAP / REFS_LIST.
local function scan_external_refs(doc)
  REFS_MAP      = {}
  REFS_LIST     = {}
  REF_BACK_IDS  = {}

  for _, blk in ipairs(doc.blocks) do
    if blk.t == "Div" and blk.attr and blk.attr.classes then
      local has_class = false
      for _, cls in ipairs(blk.attr.classes) do
        if cls == "external-refs" then
          has_class = true
          break
        end
      end

      if has_class then
        for _, inner in ipairs(blk.content) do
          if inner.t == "OrderedList" or inner.t == "BulletList" then
            for _, item in ipairs(inner.content) do
              local tmp = {}
              for _, ib in ipairs(item) do
                tmp[#tmp + 1] = utils.stringify(ib)
              end
              local line  = table.concat(tmp, " ")
              local entry = parse_ref_line(line)
              if entry then
                local id = tostring(#REFS_LIST + 1)
                entry.id = id
                REFS_LIST[#REFS_LIST + 1] = entry
                REFS_MAP[id] = entry
              end
            end
          else
            local line  = utils.stringify(inner)
            local entry = parse_ref_line(line)
            if entry then
              local id = tostring(#REFS_LIST + 1)
              entry.id = id
              REFS_LIST[#REFS_LIST + 1] = entry
              REFS_MAP[id] = entry
            end
          end
        end
      end
    end
  end
end

----------------------------------------------------------------------
-- Public init: called from span_multi.Pandoc(doc)
----------------------------------------------------------------------

function M.init(doc)
  scan_external_refs(doc)
end

-- For span_multi's hit creation: get ref info by id
function M.get(id)
  return REFS_MAP[id]
end

----------------------------------------------------------------------
-- Hit finder on linearized text
----------------------------------------------------------------------

local function find_hits(textline)
  if not REFS_MAP or next(REFS_MAP) == nil then
    return {}
  end

  local hits = {}

  ------------------------------------------------------------
  -- 1) BRACE MODE: {some text}[n]
  ------------------------------------------------------------
  local pos = 1
  while true do
    local s, e, brace, num = textline:find("(%b{})%[(%d+)%]", pos)
    if not s then break end

    local ref = REFS_MAP[num]
    if ref then
      local brace_text = brace:sub(2, -2)

      hits[#hits + 1] = {
        s          = s,
        e          = e,
        kind       = "refs",
        id         = num,
        mode       = "brace",
        url        = ref.url,
        label      = ref.label,
        text       = ref.text,
        brace_text = brace_text,
      }
    end

    pos = e + 1
  end

  ------------------------------------------------------------
  -- 2) SUFFIX MODE: word[n]
  ------------------------------------------------------------
  pos = 1
  while true do
    local pattern = "([%wÇĞİÖŞÜçğıöşü_%-]+)%[(%d+)%]"
    local s, e, word, num = textline:find(pattern, pos)
    if not s then break end

    local ref = REFS_MAP[num]
    if ref then
      hits[#hits + 1] = {
        s         = s,
        e         = e,
        kind      = "refs",
        id        = num,
        mode      = "suffix",
        url       = ref.url,
        label     = ref.label,
        text      = ref.text,
        word_text = word,
      }
    end

    pos = e + 1
  end

  ------------------------------------------------------------
  -- 3) SOLO MODE: [n]
  ------------------------------------------------------------
  pos = 1
  while true do
    local s, e, num = textline:find("%[(%d+)%]", pos)
    if not s then break end

    local ref = REFS_MAP[num]
    if ref then
      hits[#hits + 1] = {
        s    = s,
        e    = e,
        kind = "refs",
        id   = num,
        mode = "solo",
        url   = ref.url,
        label = ref.label,
        text  = ref.text,
      }
    end

    pos = e + 1
  end

  return hits
end

function M.find(text)
  return find_hits(text)
end

----------------------------------------------------------------------
-- External links section builder: "Dış bağlantılar" / "External links"
----------------------------------------------------------------------

-- Helper: create external link with optional CSS class and id
-- with target/_blank, rel/noopener
local function external_link(contents, url, class, id)
  local classes = {}
  if class and class ~= "" then
    classes = { class }
  end

  local attr = pandoc.Attr(
    id or "",
    classes,
    {
      { "target", "_blank" },
      { "rel",    "noopener noreferrer" },
    }
  )
  return pandoc.Link(contents, url, "", attr)
end

function M.build_section(meta)
  if #REFS_LIST == 0 then
    return nil
  end

  -- Section title: allow override via meta["external-refs-title"], default "Dış bağlantılar"
  local title = "Dış bağlantılar"
  if meta and meta["external-refs-title"] then
    local t = utils.stringify(meta["external-refs-title"])
    if t ~= "" then
      title = t
    end
  end

  title = title .. " (" .. tostring(#REFS_LIST) .. ")"

  local items = {}

  for _, entry in ipairs(REFS_LIST) do
    local display = entry.text or entry.label or entry.url

    local inlines = {
      external_link({ pandoc.Str(display) }, entry.url),
    }

    -- Geri dönüş oku (↩︎), ilk görünen inline sup ID'sine dönsün
    local back_id = REF_BACK_IDS[entry.id]
    if back_id then
      inlines[#inlines + 1] = pandoc.Space()
      inlines[#inlines + 1] = pandoc.Link(
        { pandoc.Str("↩︎") },
        "#" .. back_id,
        "",
        pandoc.Attr(
          "",
          { "footnote-back" },
          { { "role", "doc-backlink" } }
        )
      )
    end

    local para = pandoc.Plain(inlines)
    local div  = pandoc.Div({ para }, pandoc.Attr("extref-" .. entry.id))
    items[#items + 1] = { div }
  end

  -- Başlığa da sabit bir id verelim (isteğe bağlı)
  local header = pandoc.Header(
    2,
    { pandoc.Str(title) },
    pandoc.Attr(
      "external-links",
      { "anchored", "quarto-appendix-heading", "no-toc" }
    )
  )
  local list   = pandoc.OrderedList(items)

  return { header, list }
end

----------------------------------------------------------------------
-- Build the actual inlines for a refs hit
--
-- Called from span_multi.build_span(tok, hit):
--   * hit.kind == "refs"
--   * hit.mode in {"brace","suffix","solo"}
--
-- İSTENEN DAVRANIŞ:
--  1) Superscript [n] external link'in İÇİNDE olmayacak.
--  2) Superscript'e tıklayınca Dış bağlantılar kısmındaki #extref-n
--     anchor'ına gidecek.
--  3) Dış bağlantılar'daki her madde sonunda, inline sup id'sine geri
--     götüren bir ↩︎ linki olacak (REF_BACK_IDS ile).
----------------------------------------------------------------------
function M.build(tok, hit)
  local url = hit.url
  if not url or url == "" then
    return nil
  end

  local id    = hit.id
  local label = hit.label
  local text  = hit.text
  local sup_str = "[" .. tostring(id or "") .. "]"

  -- For classification we rely on hit.text vs hit.label
  -- text  → ref-text
  -- label → ref-label
  -- none  → ref-number

  local function fallback_display()
    return text or label or url
  end

  -- Main link in brace/suffix; class is passed in
  local function make_main_link(main, class)
    return external_link({ pandoc.Str(main) }, url, class)
  end

  -- Superscript ref link (footnote-like, goes to bottom list)
  local function make_sup_ref(cls)
    local target = "#extref-" .. id
    local ref_id = "extref" .. id

    -- Only record the *first* occurrence as the primary back target
    if not REF_BACK_IDS[id] then
      REF_BACK_IDS[id] = ref_id
    end

    local attr = pandoc.Attr(
      ref_id,
      { cls },
      {
        { "role",               "doc-noteref" },
        { "data-original-href", target        },
        { "aria-expanded",      "false"       },
      }
    )

    local sup = pandoc.Superscript({ pandoc.Str(sup_str) })
    return pandoc.Link({ sup }, target, "", attr)
  end

  local sup_ref = make_sup_ref("external-ref")
  ------------------------------------------------------------------
  -- BRACE MODE: {haberde böyle}[2]
  --   <span>
  --     <a class="ref-brace">haberde böyle</a>
  --     <a class="external-ref-ref"><sup>[2]</sup></a>
  --   </span>
  ------------------------------------------------------------------
  if hit.mode == "brace" then
    local main = hit.brace_text or fallback_display()
    return pandoc.Span({
      make_main_link(main, "ref-brace"),
      sup_ref,
    })

  ------------------------------------------------------------------
  -- SUFFIX MODE: haberde[1]
  --   <span>
  --     <a class="ref-suffix">haberde</a>
  --     <a class="external-ref-ref"><sup>[1]</sup></a>
  --   </span>
  ------------------------------------------------------------------
  elseif hit.mode == "suffix" then
    local main = hit.word_text or fallback_display()
    return pandoc.Span({
      make_main_link(main, "ref-suffix"),
      sup_ref,
    })

  ------------------------------------------------------------------
  -- SOLO MODE: [n]
  ------------------------------------------------------------------
  else
    return make_sup_ref("external-ref ref-number")
  end
end

-- Return total number of external refs
function M.count()
  return #REFS_LIST
end

return M

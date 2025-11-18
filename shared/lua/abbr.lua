-- ===========================================================
--  Bottom-of-page abbr definitions
--  Supports:
--    * single word    → ceberrut
--    * multi-word     → evlad-u iyal
--    * word variants  → rabin → rabinler / rabinin / rabine ...
-- ===========================================================

local ABBR = {}
local ABBR_PAT = {}   -- regex patterns

--------------------------------------------------------------
-- Load metadata-based abbr (if any)
--------------------------------------------------------------
local function metaAbbrToString(metaVal)
  return pandoc.utils.stringify(metaVal)
end

local function loadMetaAbbr(meta)
  local m = meta and meta.abbr
  if not m or m.t ~= "MetaMap" then return end
  for key, val in pairs(m.c) do
    ABBR[key] = metaAbbrToString(val)
  end
end

--------------------------------------------------------------
-- Parse a definition line: "[foo bar]: explanation"
--------------------------------------------------------------
local function parseAbbrLine(line)
  line = line:gsub("^%s+", ""):gsub("%s+$", "")

  -- * optional
  local key, def = line:match("^%*?%[([^%]]+)%]%s*:%s*(.+)$")
  if key and def then
    ABBR[key] = def
    return true
  end
  return false
end

--------------------------------------------------------------
-- Remove bottom abbr paragraph
--------------------------------------------------------------
local function handleAbbrPara(para)
  local txt = pandoc.utils.stringify(para)
  local found = false

  for line in txt:gmatch("[^\n]+") do
    if parseAbbrLine(line) then
      found = true
    end
  end

  if found then
    return {}   -- remove whole paragraph
  else
    return para
  end
end

--------------------------------------------------------------
-- Build regex patterns for all keys
-- Handles:
--    * multi words: "evlad%-u%s+iyal"
--    * prefix forms: "rabin" → match "rabin%w*"
--------------------------------------------------------------
local function buildPatterns()
  ABBR_PAT = {}

  for key, def in pairs(ABBR) do
    local patt

    if key:find("%s") then
      -- multi word → match exact phrase (spaces → %s+)
      patt = key:gsub(" ", "%s+")
      patt = patt:gsub("%-", "%%-")  -- escape hyphen
      patt = "%f[%a]" .. patt .. "%f[%A]"
    else
      -- single word → prefix matching (rabin → rabinxxx)
      patt = "%f[%a]" .. key .. "%w*%f[%A]"
    end

    table.insert(ABBR_PAT, { patt = patt, key = key, def = def })
  end
end

--------------------------------------------------------------
-- Replace text node segments matching abbr patterns
--------------------------------------------------------------
local function transformStr(el)
  local txt = el.text
  local orig = txt

  for _, item in ipairs(ABBR_PAT) do
    local patt = item.patt
    local key  = item.key
    local def  = item.def

    txt = txt:gsub(patt, function(matched)
      return string.format(
        '<abbr data-title="%s" tabindex="0" role="note" aria-label="%s">%s</abbr>',
        def, def, matched
      )
    end)
  end

  if txt ~= orig then
    return pandoc.RawInline("html", txt)
  else
    return el
  end
end

--------------------------------------------------------------
-- Main
--------------------------------------------------------------
function Pandoc(doc)
  ABBR = {}
  loadMetaAbbr(doc.meta)

  -- Step 1: collect abbr definitions from bottom-of-page
  local newBlocks = {}
  for _, blk in ipairs(doc.blocks) do
    if blk.t == "Para" then
      local res = handleAbbrPara(blk)
      if res.t or #res > 0 then
        table.insert(newBlocks, res)
      end
    else
      table.insert(newBlocks, blk)
    end
  end
  doc.blocks = newBlocks

  -- Step 2: build regex patterns
  buildPatterns()

  -- Step 3: replace inside all inline nodes
  doc = doc:walk({ Str = transformStr })

  return doc
end

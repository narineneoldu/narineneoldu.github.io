-- reading_time.lua
-- Compute approximate reading time based on syllable count.
-- Only counts text in doc.blocks (ignores doc.meta completely).

local M = {}
-- local LOG = io.open("reading-time-debug.log", "w")
----------------------------------------------------------------------
-- Config from metadata (hece-süre)
----------------------------------------------------------------------

local LANG                 = "tr"   -- default language
local SECONDS_PER_SYLLABLE = 0.2   -- default; can be overridden from meta

-- Read config from document metadata
local function load_config(meta)
  -- For example:
  -- metadata:
  --   reading-time:
  --     seconds-per-syllable: 0.28
  local rt = meta["reading-time"]
  if rt and rt["seconds-per-syllable"] then
    local v = tonumber(pandoc.utils.stringify(rt["seconds-per-syllable"]))
    if v and v > 0 then
      SECONDS_PER_SYLLABLE = v
    end
  end
end

----------------------------------------------------------------------
-- Syllable counting helpers
----------------------------------------------------------------------

local UTF8_CP = "[%z\1-\127\194-\244][\128-\191]*"

-- Turkish-ish vowels; adjust as needed
local VOWELS = {
  ["a"] = true, ["e"] = true, ["ı"] = true, ["i"] = true,
  ["o"] = true, ["ö"] = true, ["u"] = true, ["ü"] = true,
  ["â"] = true, ["î"] = true, ["û"] = true,
  ["A"] = true, ["E"] = true, ["I"] = true, ["İ"] = true,
  ["O"] = true, ["Ö"] = true, ["U"] = true, ["Ü"] = true,
}

local function load_config(meta)

  -- Read language from _quarto.yml → lang:
  if meta.lang then
    LANG = pandoc.utils.stringify(meta.lang)
  end

  -- (senin mevcut reading-time config kısmı aşağıda devam eder)
  local rt = meta["reading-time"]
  if rt and rt["seconds-per-syllable"] then
    local v = tonumber(pandoc.utils.stringify(rt["seconds-per-syllable"]))
    if v and v > 0 then
      SECONDS_PER_SYLLABLE = v
    end
  end
end

local function is_vowel(ch)
  return VOWELS[ch] or false
end

-- return true if token contains at least one vowel
local function has_vowel(tok)
  for ch in tok:gmatch(UTF8_CP) do
    if VOWELS[ch] then
      return true
    end
  end
  return false
end

-- Count syllables in a word-like token without digits.
-- Heuristic: count transitions from non-vowel to vowel.
local function syllables_for_word(tok)
  -- if LOG then
    -- LOG:write(string.format("'%s'\n", tok))
    -- io.stderr:write(string.format("[reading-time] token: '%s'\n", tok))
  -- end
  local syllables = 0
  local prev_vowel = false
  local saw_letter = false

  for ch in tok:gmatch(UTF8_CP) do
    local v = is_vowel(ch)
    if v and not prev_vowel then
      syllables = syllables + 1
    end
    if ch:match("%a") then
      saw_letter = true
    end
    prev_vowel = v
  end

  -- If we saw letters but no vowel (rare abbreviations), count as 1
  if saw_letter and syllables == 0 then
    syllables = 1
  end

  return syllables
end

----------------------------------------------------------------------
-- Walk ONLY doc.blocks (ignore doc.meta)
----------------------------------------------------------------------
-- Count syllables in an inline list
local function count_inlines(inlines)
  local total = 0

  for _, el in ipairs(inlines) do
    if el.t == "Str" then
      -- io.stderr:write(string.format("[reading-time]   Str text: '%s'\n", el.text))
      -- Split on spaces / punctuation into tokens
      for tok in el.text:gmatch("%S+") do
        total = total + syllables_for_word(tok)
      end

    elseif el.t == "Span" or el.t == "Emph" or el.t == "Strong"
       or el.t == "Link" or el.t == "Code" or el.t == "Quoted" then
      -- io.stderr:write(string.format("[reading-time] inline: %s\n", el))

      -- Recursively count inside nested inline containers
      if el.c then
        total = total + count_inlines(el.c)
      elseif el.content then
        total = total + count_inlines(el.content)
      end
    end
  end

  return total
end

-- Count words by scanning %S+ tokens (ignores numbers)
local function count_words_in_inlines(inlines)
  local total = 0
  for _, el in ipairs(inlines) do
    if el.t == "Str" then
      for tok in el.text:gmatch("%S+") do
        -- count a word only if it contains at least one vowel
        if has_vowel(tok) then
            total = total + 1
        end
      end
    elseif el.t == "Span" or el.t == "Emph" or el.t == "Strong"
       or el.t == "Link" or el.t == "Code" or el.t == "Quoted" then
      if el.c then
        total = total + count_words_in_inlines(el.c)
      elseif el.content then
        total = total + count_words_in_inlines(el.content)
      end
    end
  end
  return total
end

-- Special handling for quarto-meta-markdown: only count 1st and 5th Span inside
local function count_quarto_meta_div(block)
  local total = 0

  -- Expect a single Para/Plain inside the Div
  if not (block.content and #block.content > 0) then
    return 0
  end

  local para = block.content[1]
  if not (para.t == "Para" or para.t == "Plain") then
    return 0
  end

  local span_idx = 0
  local target_indices = { [1] = true, [5] = true }

  for _, inline in ipairs(para.c) do
    if inline.t == "Span" then
      span_idx = span_idx + 1

      if target_indices[span_idx] then
        local inlines = inline.c or inline.content
        if inlines then
          total = total + count_inlines(inlines)
        end
      end

      -- We do not care about spans after the 5th one
      if span_idx >= 5 then
        break
      end
    end
  end

  return total
end

local function count_words_quarto_meta_div(block)
  local total = 0

  if not (block.content and #block.content > 0) then
    return 0
  end

  local para = block.content[1]
  if not (para.t == "Para" or para.t == "Plain") then
    return 0
  end

  local span_idx = 0
  local target_indices = { [1] = true, [5] = true }

  for _, inline in ipairs(para.c) do
    if inline.t == "Span" then
      span_idx = span_idx + 1

      if target_indices[span_idx] then
        local inlines = inline.c or inline.content
        if inlines then
          total = total + count_words_in_inlines(inlines)
        end
      end

      if span_idx >= 5 then
        break
      end
    end
  end

  return total
end

-- Count syllables inside a single block (para, header, list, etc)
local function count_block(block)
  local total = 0
  local n = 0
  if block.c then n = #block.c end
  -- io.stderr:write(string.format("[reading-time] count_block: type %s, n: %d, attr: %s\n", block.t, n, block.attr))
  if block.t == "Para" or block.t == "Plain" or block.t == "Header" then
    total = total + count_inlines(block.c)

    elseif block.t == "Div" and block.attr and block.attr.identifier == "quarto-meta-markdown" then
      -- Only count 5th Span inside quarto-meta-markdown
      total = total + count_quarto_meta_div(block)

    elseif block.t == "BlockQuote" or block.t == "Div" or block.t == "Figure" then
      -- Recurse into nested blocks
      if block.content then
        for _, b in ipairs(block.content) do
          total = total + count_block(b)
        end
      end

  elseif block.t == "BulletList" or block.t == "OrderedList" then
    -- Each item is a list of blocks
    for _, items in ipairs(block.c) do
      for _, b in ipairs(items) do
        total = total + count_block(b)
      end
    end

  elseif block.t == "Table" then
    -- Very rough: count only caption + body cells
    if block.caption and block.caption.long then
      total = total + count_inlines(block.caption.long)
    end
    if block.bodies then
      for _, body in ipairs(block.bodies) do
        for _, row in ipairs(body.body) do
          for _, cell in ipairs(row) do
            for _, b in ipairs(cell) do
              total = total + count_block(b)
            end
          end
        end
      end
    end
  end

  return total
end

local function count_words_in_block(block)
  local total = 0

  if block.t == "Para" or block.t == "Plain" or block.t == "Header" then
    total = total + count_words_in_inlines(block.c)

    elseif block.t == "Div" and block.attr and block.attr.identifier == "quarto-meta-markdown" then
      -- Only count 5th Span inside quarto-meta-markdown
      total = total + count_words_quarto_meta_div(block)

    elseif block.t == "BlockQuote" or block.t == "Div" or block.t == "Figure" then
      if block.content then
        for _, b in ipairs(block.content) do
          total = total + count_words_in_block(b)
        end
      end

  elseif block.t == "BulletList" or block.t == "OrderedList" then
    for _, items in ipairs(block.c) do
      for _, b in ipairs(items) do
        total = total + count_words_in_block(b)
      end
    end

  elseif block.t == "Table" then
    if block.caption and block.caption.long then
      total = total + count_words_in_inlines(block.caption.long)
    end
    if block.bodies then
      for _, body in ipairs(block.bodies) do
        for _, row in ipairs(body.body) do
          for _, cell in ipairs(row) do
            for _, b in ipairs(cell) do
              total = total + count_words_in_block(b)
            end
          end
        end
      end
    end
  end

  return total
end

local function count_words_in_document(doc)
  local total = 0
  for _, blk in ipairs(doc.blocks) do
    if blk.t == "Div" and blk.attr and blk.attr.classes then
      local skip = false
      for _, cls in ipairs(blk.attr.classes) do
        if cls == "external-refs" then
          skip = true
          break
        end
      end
      if skip then goto continue end
    end
    total = total + count_words_in_block(blk)
    ::continue::
  end
  return total
end

-- Count syllables only in doc.blocks
local function count_syllables_in_document(doc)
  local total = 0

  for _, blk in ipairs(doc.blocks) do
    -- Example: if you want to skip certain Divs (like external-refs), you can do:
    local id = nil
    if blk.t == "Div" and blk.attr then
      id = blk.attr.identifier or nil
      if blk.attr.classes then
        local skip = false

        -- NEW: skip by identifier
        if id == "quarto-navigation-envelope" then
          skip = true
        end

        -- Existing class-based skipping
        for _, cls in ipairs(blk.attr.classes) do
          if cls == "external-refs" then
            skip = true
            break
          end
        end

        if skip then goto continue end
      end
    end

    -- io.stderr:write(
    --   string.format("[reading-time] block id: %s, type: %s, attr: %s\n",
    --     id, blk.t,  blk.attr))

    -- if LOG then
    --   LOG:write(
    --     string.format("[reading-time] block id: %s, type: %s, attr: %s\n",
    --       id, blk.t,  blk.attr))
    --   io.stderr:write(string.format("[reading-time] token: '%s'\n", tok))
    -- end

    total = total + count_block(blk)
    ::continue::
  end

  return total
end

----------------------------------------------------------------------
-- Pandoc entry point
----------------------------------------------------------------------

function M.Pandoc(doc)
  load_config(doc.meta)

  -- if LOG then
    -- LOG:write(string.format("=== START %s ===\n", pandoc.utils.stringify(doc.meta.title) or "UNKNOWN"))
  -- end

  local total_syllables = count_syllables_in_document(doc)
  local total_seconds   = total_syllables * SECONDS_PER_SYLLABLE
  local minutes_raw = total_seconds / 60
  local minutes = math.floor(minutes_raw + 0.5)
  local hours = 0
  if minutes >= 60 then
    hours = math.floor(minutes / 60)
    minutes = minutes % 60
  end

  -- Store a human-readable label in metadata.
  -- Use a separate key to avoid clashing with configuration.
  local label

  if LANG == "tr" then
    if hours > 0 then
      if minutes > 0 then
        label = string.format("~ %d sa %d dk", hours, minutes)
      else
        label = string.format("~ %d sa", hours)
      end
    else
      label = string.format("~ %d dk", minutes)
    end

  else
    -- English fallback
    if hours > 0 then
      if minutes > 0 then
        label = string.format("~ %d h %d min", hours, minutes)
      else
        label = string.format("~ %d h", hours)
      end
    else
      label = string.format("~ %d min", minutes)
    end
  end

  local total_words = count_words_in_document(doc)
  local label_words = string.format("~ %d", total_words)
  doc.meta["reading-time-words"] = pandoc.MetaString(label_words)
  doc.meta["reading-time-estimate"] = pandoc.MetaString(label)

  -- io.stderr:write(
  --   string.format("[reading-time] %s (%d words, %d syllables)\n",
  --     label, total_words, total_syllables))

  -- Expose as metadata so you can use in templates / shortcodes
  doc.meta["reading-time-syllables"] = pandoc.MetaString(tostring(total_syllables))
  -- Also expose raw seconds if you want to use it in templates
  doc.meta["reading-time-seconds"] = pandoc.MetaString(
    string.format("%.0f", total_seconds)
  )

  if LOG then LOG:close() end
  return doc
end

return M

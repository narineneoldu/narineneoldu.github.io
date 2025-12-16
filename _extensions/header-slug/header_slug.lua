-- header_slug.lua
-- Slug generator with TR override + Latin folding for European languages.

local used_ids = {}

-- Character map
local fold = {
  -- a
  ["á"]="a",["à"]="a",["â"]="a",["ä"]="a",["ã"]="a",["å"]="a",["ā"]="a",["ă"]="a",["ą"]="a",
  ["Á"]="a",["À"]="a",["Â"]="a",["Ä"]="a",["Ã"]="a",["Å"]="a",["Ā"]="a",["Ă"]="a",["Ą"]="a",
  -- c
  ["ç"]="c",["ć"]="c",["č"]="c",["Ç"]="c",["Ć"]="c",["Č"]="c",
  -- d
  ["ď"]="d",["đ"]="d",["Ď"]="d",["Đ"]="d",
  -- e
  ["é"]="e",["è"]="e",["ê"]="e",["ë"]="e",["ē"]="e",["ė"]="e",["ę"]="e",
  ["É"]="e",["È"]="e",["Ê"]="e",["Ë"]="e",["Ē"]="e",["Ė"]="e",["Ę"]="e",
  -- g
  ["ğ"]="g",["ģ"]="g",["Ğ"]="g",["Ģ"]="g",
  -- i
  ["í"]="i",["ì"]="i",["î"]="i",["ï"]="i",["ī"]="i",["İ"]="i",
  ["Í"]="i",["Ì"]="i",["Î"]="i",["Ï"]="i",["Ī"]="i",
  ["ı"]="i", ["I"]="i",
  -- l
  ["ł"]="l",["Ł"]="l",
  -- n
  ["ñ"]="n",["ń"]="n",["ň"]="n",["Ñ"]="n",["Ń"]="n",["Ň"]="n",
  -- o
  ["ó"]="o",["ò"]="o",["ô"]="o",["ö"]="o",["õ"]="o",["ø"]="o",["ō"]="o",
  ["Ó"]="o",["Ò"]="o",["Ô"]="o",["Ö"]="o",["Õ"]="o",["Ø"]="o",["Ō"]="o",
  -- r
  ["ř"]="r",["Ř"]="r",
  -- s
  ["ś"]="s",["š"]="s",["ş"]="s",["Ś"]="s",["Š"]="s",["Ş"]="s",
  -- t
  ["ť"]="t",["Ţ"]="t",["ţ"]="t",["Ť"]="t",
  -- u
  ["ú"]="u",["ù"]="u",["û"]="u",["ü"]="u",["ū"]="u",
  ["Ú"]="u",["Ù"]="u",["Û"]="u",["Ü"]="u",["Ū"]="u",
  -- y
  ["ý"]="y",["ÿ"]="y",["Ý"]="y",
  -- z
  ["ź"]="z",["ž"]="z",["ż"]="z",["Ź"]="z",["Ž"]="z",["Ż"]="z",

  -- ligatures / special
  ["ß"]="ss",["ẞ"]="ss",
  ["æ"]="ae",["Æ"]="ae",
  ["œ"]="oe",["Œ"]="oe",
  ["þ"]="th",["Þ"]="th",
  ["ð"]="d", ["Ð"]="d",

-- Greek (basic)
["Α"]="a",["Β"]="v",["Γ"]="g",["Δ"]="d",["Ε"]="e",["Ζ"]="z",["Η"]="i",["Θ"]="th",
["Ι"]="i",["Κ"]="k",["Λ"]="l",["Μ"]="m",["Ν"]="n",["Ξ"]="x",["Ο"]="o",["Π"]="p",
["Ρ"]="r",["Σ"]="s",["Τ"]="t",["Υ"]="y",["Φ"]="f",["Χ"]="ch",["Ψ"]="ps",["Ω"]="o",
["α"]="a",["β"]="v",["γ"]="g",["δ"]="d",["ε"]="e",["ζ"]="z",["η"]="i",["θ"]="th",
["ι"]="i",["κ"]="k",["λ"]="l",["μ"]="m",["ν"]="n",["ξ"]="x",["ο"]="o",["π"]="p",
["ρ"]="r",["σ"]="s",["ς"]="s",["τ"]="t",["υ"]="y",["φ"]="f",["χ"]="ch",["ψ"]="ps",
["ω"]="o",

-- Cyrillic (Russian basic)
["А"]="a",["Б"]="b",["В"]="v",["Г"]="g",["Д"]="d",["Е"]="e",["Ё"]="e",["Ж"]="zh",
["З"]="z",["И"]="i",["Й"]="i",["К"]="k",["Л"]="l",["М"]="m",["Н"]="n",["О"]="o",
["П"]="p",["Р"]="r",["С"]="s",["Т"]="t",["У"]="u",["Ф"]="f",["Х"]="kh",["Ц"]="ts",
["Ч"]="ch",["Ш"]="sh",["Щ"]="shch",["Ы"]="y",["Э"]="e",["Ю"]="yu",["Я"]="ya",
["Ь"]="",["Ъ"]="",
["а"]="a",["б"]="b",["в"]="v",["г"]="g",["д"]="d",["е"]="e",["ё"]="e",["ж"]="zh",
["з"]="z",["и"]="i",["й"]="i",["к"]="k",["л"]="l",["м"]="m",["н"]="n",["о"]="o",
["п"]="p",["р"]="r",["с"]="s",["т"]="t",["у"]="u",["ф"]="f",["х"]="kh",["ц"]="ts",
["ч"]="ch",["ш"]="sh",["щ"]="shch",["ы"]="y",["э"]="e",["ю"]="yu",["я"]="ya",
["ь"]="",["ъ"]="",
}

-- Characters to remove completely (apostrophes/quotes etc.)
local strip_chars = {
  ["'"]=true, ["’"]=true, ["‘"]=true, ["´"]=true, ["`"]=true,
  ["“"]=true, ["”"]=true,
  ["…"]=true,
}

-- Build a fast ASCII lower table (avoid locale issues for A-Z only).
local function ascii_lower_byte(b)
  -- 'A'..'Z' => +32
  if b >= 65 and b <= 90 then return b + 32 end
  return b
end

-- Decode one UTF-8 codepoint starting at byte index i.
-- Returns (char, next_i). Falls back to single-byte on invalid sequences.
local function utf8_next(s, i)
  local b1 = string.byte(s, i)
  if not b1 then return nil, i end

  -- ASCII
  if b1 < 0x80 then
    return string.sub(s, i, i), i + 1
  end

  -- 2-byte sequence
  if b1 >= 0xC2 and b1 < 0xE0 then
    local b2 = string.byte(s, i + 1)
    if b2 and b2 >= 0x80 and b2 < 0xC0 then
      return string.sub(s, i, i + 1), i + 2
    end
    return string.sub(s, i, i), i + 1
  end

  -- 3-byte sequence
  if b1 >= 0xE0 and b1 < 0xF0 then
    local b2 = string.byte(s, i + 1)
    local b3 = string.byte(s, i + 2)
    if b2 and b3 and b2 >= 0x80 and b2 < 0xC0 and b3 >= 0x80 and b3 < 0xC0 then
      return string.sub(s, i, i + 2), i + 3
    end
    return string.sub(s, i, i), i + 1
  end

  -- 4-byte sequence
  if b1 >= 0xF0 and b1 < 0xF5 then
    local b2 = string.byte(s, i + 1)
    local b3 = string.byte(s, i + 2)
    local b4 = string.byte(s, i + 3)
    if b2 and b3 and b4
      and b2 >= 0x80 and b2 < 0xC0
      and b3 >= 0x80 and b3 < 0xC0
      and b4 >= 0x80 and b4 < 0xC0 then
      return string.sub(s, i, i + 3), i + 4
    end
    return string.sub(s, i, i), i + 1
  end

  -- Invalid leading byte; consume one.
  return string.sub(s, i, i), i + 1
end

-- Returns true if byte is ASCII alnum or underscore.
local function is_word_byte(b)
  -- 0-9
  if b >= 48 and b <= 57 then return true end
  -- A-Z / a-z
  if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) then return true end
  -- underscore
  return b == 95
end

-- Returns true if char should be treated as a separator (collapses into '-').
local function is_separator_char(ch, b)
  -- Fast ASCII checks first
  if b then
    -- whitespace
    if b == 9 or b == 10 or b == 11 or b == 12 or b == 13 or b == 32 then return true end
    -- common punctuation as separators
    if b == 45 or b == 46 or b == 44 or b == 58 or b == 59 or b == 47 or b == 92 then return true end
    -- parentheses/brackets/braces
    if b == 40 or b == 41 or b == 91 or b == 93 or b == 123 or b == 125 then return true end
    return false
  end
  -- Non-ASCII: treat as separator only if you explicitly want to.
  return false
end

local function slugify(s)
  if not s or s == "" then return "" end

  local out = {}
  local out_len = 0
  local prev_dash = true -- avoid leading '-'

  local i = 1
  local n = #s

  while i <= n do
    local ch, next_i = utf8_next(s, i)
    if not ch then break end

    -- ASCII fast path
    if #ch == 1 then
      local b = string.byte(ch, 1)

      -- Strip quotes/apostrophes/etc.
      if strip_chars[ch] then
        -- skip
      elseif is_separator_char(ch, b) then
        if not prev_dash then
          out_len = out_len + 1
          out[out_len] = "-"
          prev_dash = true
        end
      elseif is_word_byte(b) then
        -- Keep ASCII word chars; lower-case A-Z only
        out_len = out_len + 1
        out[out_len] = string.char(ascii_lower_byte(b))
        prev_dash = false
      else
        -- Drop other ASCII punctuation/symbols
      end

    else
      -- Non-ASCII: strip or fold, otherwise keep as-is
      if strip_chars[ch] then
        -- skip
      else
        local rep = fold[ch]
        if rep ~= nil then
          -- If rep == "" -> delete (e.g., soft/hard sign)
          if rep ~= "" then
            -- rep can be multi-char (ASCII); emit lower for A-Z only
            for j = 1, #rep do
              local rb = string.byte(rep, j)
              out_len = out_len + 1
              out[out_len] = string.char(ascii_lower_byte(rb))
            end
            prev_dash = false
          end
        else
          -- Unknown Unicode: keep the original character
          out_len = out_len + 1
          out[out_len] = ch
          prev_dash = false
        end
      end
    end

    i = next_i
  end

  -- Trim trailing dash
  if out_len > 0 and out[out_len] == "-" then
    out[out_len] = nil
    out_len = out_len - 1
  end

  return table.concat(out, "", 1, out_len)
end

local function make_unique_id(base)
  if base == "" then return base end
  local count = used_ids[base]
  if not count then
    used_ids[base] = 1
    return base
  end
  count = count + 1
  used_ids[base] = count
  return string.format("%s-%d", base, count)
end

return {
  -- Reset per-document state to avoid cross-run leakage.
  Pandoc = function(doc)
    used_ids = {}
    return doc
  end,

  Header = function(h)
    local text = pandoc.utils.stringify(h.content or {})
    if not text or text == "" then return h end

    local base = slugify(text)
    if base == "" then return h end

    h.identifier = make_unique_id(base)
    return h
  end
}

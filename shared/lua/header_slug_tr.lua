-- header-slug-tr.lua
-- Slug generator with proper Turkish transliteration + apostrophe removal.

local used_ids = {}

-- Turkish character map
local tr_map = {
  ["ç"] = "c", ["Ç"] = "c",
  ["ğ"] = "g", ["Ğ"] = "g",
  ["ı"] = "i", ["I"] = "i",
  ["İ"] = "i",
  ["ö"] = "o", ["Ö"] = "o",
  ["ş"] = "s", ["Ş"] = "s",
  ["ü"] = "u", ["Ü"] = "u",
  ["â"] = "a", ["Â"] = "a",
  ["û"] = "u", ["Û"] = "u",
  ["î"] = "i", ["Î"] = "i",
}

-- Apostrophes to remove completely
local apostrophes = {
  ["'"] = true,      -- ASCII apostrophe
  ["’"] = true,      -- RIGHT SINGLE QUOTE (U+2019)
  ["‘"] = true,      -- LEFT SINGLE QUOTE (U+2018)
  ["´"] = true,      -- ACUTE
  ["`"] = true,      -- grave
  ["…"] = true,      -- ellipsis (U+2026)
  ["“"] = true,
  ["”"] = true,
}

local function transliterate_tr(s)
  if not s or s == "" then return s end

  -- First remove apostrophes
  for apo, _ in pairs(apostrophes) do
    s = s:gsub(apo, "")
  end

  -- Convert Turkish characters
  for from, to_ in pairs(tr_map) do
    s = s:gsub(from, to_)
  end

  return s
end

local function slugify_tr(s)
  if not s or s == "" then return "" end

  s = transliterate_tr(s)
  s = s:lower()
  s = s:gsub("%s+", "-")
  s = s:gsub("[^%w%-]", "")
  s = s:gsub("%-+", "-")
  s = s:gsub("^%-+", ""):gsub("%-+$", "")

  return s
end

local function make_unique_id(base)
  if base == "" then return base end
  local count = used_ids[base]
  if not count then
    used_ids[base] = 1
    return base
  else
    count = count + 1
    used_ids[base] = count
    return string.format("%s-%d", base, count)
  end
end

return {
  Header = function(h)
    local text = pandoc.utils.stringify(h.content or {})
    if not text or text == "" then return h end

    local slug = slugify_tr(text)
    -- io.stderr:write("Generated slug: " .. slug .. "\n")
    if slug == "" then return h end

    slug = make_unique_id(slug)
    h.identifier = slug

    return h
  end,
}

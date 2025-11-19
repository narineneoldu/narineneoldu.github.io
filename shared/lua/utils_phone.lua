-- ../shared/lua/utils_phone.lua
-- Sözlük tabanlı telefon numarası tespiti.
--
-- Public API:
--   M.set_dict(meta)
--   M.find(text) ->
--       { { s = i1, e = j1, kind = "phone", key = "...", label = "..."? }, ... }
--
--  * meta.phones: key = numara string'i, value = tooltip / açıklama

local M = {}

-- İçeride cache’lenecek sözlük (numara -> tooltip)
local PHONE_DICT = nil

local function normalize_spaces(s)
  s = s:gsub("%s+", " ")
  s = s:match("^%s*(.-)%s*$") or s
  return s
end

local function load_phone_dict_from_meta(meta)
  if not meta then return nil end

  local dict = meta.phones or (meta.metadata and meta.metadata.phones)
  if type(dict) ~= "table" then
    return nil
  end

  local t = {}
  for k, v in pairs(dict) do
    local kk = pandoc.utils.stringify(k)
    local vv = pandoc.utils.stringify(v)
    if kk ~= "" and vv ~= "" then
      kk = normalize_spaces(kk)
      t[kk] = vv
    end
  end

  return next(t) and t or nil
end

-- Dışarıdan bir kere set edilecek
function M.set_dict(meta)
  PHONE_DICT = load_phone_dict_from_meta(meta)
end

local function find_hits(text)
  local phone_dict = PHONE_DICT
  if not phone_dict or next(phone_dict) == nil then
    return {}
  end

  local hits = {}

  for num, label in pairs(phone_dict) do
    local start = 1
    while true do
      local s, e = text:find(num, start, true) -- plain search
      if not s then break end
      hits[#hits + 1] = {
        s     = s,
        e     = e,
        kind  = "phone",
        key   = num,
        label = label, -- tooltip (optional)
      }
      start = e + 1
    end
  end

  return hits
end

function M.find(text)
  return find_hits(text)
end

return M

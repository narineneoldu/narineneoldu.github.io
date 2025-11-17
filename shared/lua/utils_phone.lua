-- ../shared/lua/utils_phone.lua
-- Sözlük tabanlı telefon numarası tespiti.
--
-- Public API:
--   M.set_dict(phone_dict)
--   M.find_phones(text) ->
--       { { s = i1, e = j1, kind = "phone", key = "..." }, ... }
--
--  * phone_dict: Meta'den gelen düz tablo; key = numara string'i.

local M = {}

-- İçeride cache’lenecek sözlük
local PHONE_DICT = nil

-- Dışarıdan bir kere set edilecek
function M.set_dict(dict)
  if type(dict) == "table" and next(dict) ~= nil then
    PHONE_DICT = dict
  else
    PHONE_DICT = nil
  end
end

local function find_hits(text)
  local phone_dict = PHONE_DICT
  if not phone_dict or next(phone_dict) == nil then
    return {}
  end

  local hits = {}

  for num, _ in pairs(phone_dict) do
    local start = 1
    while true do
      local s, e = text:find(num, start, true) -- plain search
      if not s then break end
      hits[#hits + 1] = {
        s    = s,
        e    = e,
        kind = "phone",
        key  = num,
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

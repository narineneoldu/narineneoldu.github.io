-- ../shared/lua/utils_plate.lua
-- TR plaka tespiti.
--
-- Public API:
--   M.set_dict(meta)
--   M.find(text) -> { { s = i1, e = j1, kind = "plate", label = "..."? }, ... }

local M = {}

-- Optional tooltip dictionary loaded from document metadata:
--   PLATES["34 ABC 123"] = "Nevzat Bahtiyar'ın aracı"
local PLATES = nil

-- Aynı validasyon: 01..81, Q/W yok, numara uzunlukları vb.
local function valid_plate_parts(il, letters, digits)
  local n = tonumber(il)
  if not n or n < 1 or n > 81 then return false end
  if letters:match("[QW]") then return false end

  local L, D = #letters, #digits
  local ok_len =
      (L == 1 and (D == 4 or D == 5))
   or (L == 2 and (D == 3 or D == 4))
   or (L == 3 and (D == 2 or D == 3))

  if not ok_len then return false end
  if digits:match("^0+$") then return false end
  return true
end

-- Trim + iç boşlukları tek space'e çek
local function normalize_spaces(s)
  s = s:gsub("%s+", " ")
  s = s:match("^%s*(.-)%s*$") or s
  return s
end

-- plates sözlüğünü meta'dan oku
local function load_plates_from_meta(meta)
  if not meta then return nil end

  local dict = meta.plates or (meta.metadata and meta.metadata.plates)
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

function M.set_dict(meta)
  PLATES = load_plates_from_meta(meta)
end

local function find_hits(text)
  -- 34 AB 1234 vb.
  local PAT = '%f[%d](%d%d)%s+([A-Z][A-Z]?[A-Z]?)%s+(%d%d%d?%d?%d?)%f[%D]'
  local hits = {}
  local i = 1

  while true do
    local a, b, il, letters, digits = text:find(PAT, i)
    if not a then break end

    if valid_plate_parts(il, letters, digits) then
      local plate_text = text:sub(a, b)

      -- Tooltip: meta.plates içinden varsa al
      local label = nil
      if PLATES then
        local key = normalize_spaces(plate_text)
        label = PLATES[key]
      end

      hits[#hits + 1] = {
        s     = a,
        e     = b,
        kind  = "plate",
        label = label, -- nil olabilir
      }
      i = b + 1
    else
      i = a + 1
    end
  end

  return hits
end

function M.find(text)
  return find_hits(text)
end

return M

-- ../shared/lua/utils_plate.lua
-- TR plaka tespiti.
--
-- Public API:
--   M.find_plates(text) -> { { s = i1, e = j1, kind = "plate" }, ... }

local M = {}

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

local function find_hits(text)
  -- 34 AB 1234 vb.
  local PAT = '%f[%d](%d%d)%s+([A-Z][A-Z]?[A-Z]?)%s+(%d%d%d?%d?%d?)%f[%D]'
  local hits = {}
  local i = 1

  while true do
    local a, b, il, letters, digits = text:find(PAT, i)
    if not a then break end

    if valid_plate_parts(il, letters, digits) then
      hits[#hits + 1] = { s = a, e = b, kind = "plate" }
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

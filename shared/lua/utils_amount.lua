-- ../shared/lua/utils_amount.lua
-- TR amounts: "48.000,00 TL", "1200 TL", "1.200 TL", "45.673,84 TL", "45.673,84 TL’den" vb.
-- Sadece düz string üzerinde çalışır.
-- Public API:
--   M.find_amounts(text) -> { { s = i1, e = j1, kind = "amount" }, ... }

local M = {}

-- NBSP (U+00A0) — TL öncesinde kullanılabiliyor
local NBSP = "\194\160"

-- Miktar desenleri:
--  - ondalıklı: 1.234,56   (en az bir rakam, opsiyonel binlik . , ardından virgül+2 hane)
--  - tam sayı : 1.234  veya 1200  (rakam ve noktalar; sonda nokta olmasın)
local PAT_DEC = '(%f[%d]%d[%d%.]*,%d%d)%s*TL'  -- ondalıklı
local PAT_INT = '(%f[%d]%d[%d%.]*)%s*TL'       -- ondalıksız

local function find_amounts(text)
  -- NBSP → normal boşluk: indexler değişmiyor, sadece karakter kodu değişiyor.
  local s = text:gsub(NBSP, " ")

  local hits = {}
  local i, n = 1, #s

  while i <= n do
    local a1, b1, num1 = s:find(PAT_DEC, i)
    local a2, b2, num2 = s:find(PAT_INT, i)

    local a, b, num, is_dec

    if a1 and (not a2 or a1 <= a2) then
      a, b, num, is_dec = a1, b1, num1, true
    elseif a2 then
      a, b, num, is_dec = a2, b2, num2, false
      -- ondalıksız olanın sonu nokta ile bitmesin (örn. "1.200." gibi)
      if num:sub(-1) == '.' then
        i = a + 1
        goto continue
      end
    else
      break
    end

    -- s ve text aynı uzunlukta ve indexler bire bir, o yüzden a,b doğrudan kullanılabilir.
    hits[#hits+1] = {
      s    = a,
      e    = b,
      kind = "amount",
    }

    i = b + 1
    ::continue::
  end

  return hits
end

function M.find(text)
  return find_amounts(text)
end

return M

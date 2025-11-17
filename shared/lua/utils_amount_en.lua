-- ../shared/lua/utils_amount_en.lua
-- EN amounts: "TRY 48,000.00", "TRY 1,200", "TRY 1200"
-- Sadece düz string üzerinde çalışır.
-- Public API:
--   M.find_amounts(text) -> { { s = i1, e = j1, kind = "amount" }, ... }

local M = {}

local NBSP  = "\194\160"      -- U+00A0
local NNBSP = "\226\128\175"  -- U+202F
local SP    = "[%s\194\160\226\128\175]+"  -- space / NBSP / NNBSP

-- Tüm kalıbı tek capture olarak almak için desenler:
--  - ondalıklı:  TRY 48,000.00
--  - tam sayı :  TRY 1,200  veya TRY 1200  (sonu virgül olmasın)
local PAT_DEC = '(%f[%a][Tt][Rr][Yy]' .. SP .. '%d[%d,]*%.%d%d)' -- ondalıklı
local PAT_INT = '(%f[%a][Tt][Rr][Yy]' .. SP .. '%d[%d,]*)'      -- tam sayı

local function find_amounts(text)
  -- NBSP/NNBSP → normal boşluk; uzunluk değişmediği için indexler korunur
  local s = text:gsub(NBSP, " "):gsub(NNBSP, " ")

  local hits = {}
  local i, n = 1, #s

  while i <= n do
    local a1, b1, grp1 = s:find(PAT_DEC, i)
    local a2, b2, grp2 = s:find(PAT_INT, i)

    local a, b, grp, is_dec

    if a1 and (not a2 or a1 <= a2) then
      -- ondalıklı: TRY 48,000.00
      a, b, grp, is_dec = a1, b1, grp1, true
    elseif a2 then
      -- tam sayı: TRY 1,200 / TRY 1200
      -- Sayı kısmını çek, sonu virgül ise (ör. "TRY 1,200,") bu eşleşmeyi atla
      local num = grp2:match("(%d[%d,]*)$") or ""
      if num:sub(-1) == "," then
        i = a2 + 1
        goto continue
      end
      a, b, grp, is_dec = a2, b2, grp2, false
    else
      break
    end

    -- s ve text aynı uzunlukta, dolayısıyla a,b doğrudan text index'i
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

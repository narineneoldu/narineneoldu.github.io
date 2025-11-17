-- ../shared/lua/utils_para.lua
-- Parantez içlerini tespit eder: "(...)" blokları
-- Sadece düz string üzerinde çalışır.
-- Public API:
--   M.find_paras(text) -> { { s = i1, e = j1, kind = "paranthesis" }, ... }

local M = {}

local function find_paras(text)
  local hits = {}
  local in_paren = false
  local start_i = nil
  local len = #text

  for i = 1, len do
    local ch = text:sub(i, i)

    if ch == "(" then
      -- Daha önce açılmamışsa yeni bir blok başlat
      if not in_paren then
        in_paren = true
        start_i = i
      end

    elseif ch == ")" then
      if in_paren and start_i then
        -- "(...)" aralığını hit olarak kaydet
        hits[#hits+1] = {
          s    = start_i,
          e    = i,
          kind = "paranthesis",
        }
        in_paren = false
        start_i  = nil
      end
    end
  end

  -- Satır sonuna kadar kapanmamış parantez varsa yok sayıyoruz (span_para.lua’da da
  -- parametre kapanmazsa span’a çevirmeden döküyorduk)

  return hits
end

function M.find(text)
  return find_paras(text)
end

return M

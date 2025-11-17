-- ../shared/lua/utils_quote.lua
-- Çift tırnak içi parçaları (tırnak DAHİL) tespit eder.
-- Public API:
--   M.find(text) -> { { s = i1, e = j1, kind = "quote" }, ... }

local M = {}

local function find_quotes(text)
  local hits = {}

  if not text or text == "" then
    return hits
  end

  local n          = #text
  local i          = 1
  local in_quote   = false
  local start_pos  = nil

  while i <= n do
    local qpos = text:find('"', i, true)  -- düz double-quote
    if not qpos then
      break
    end

    if not in_quote then
      -- Açılış tırnağı
      in_quote  = true
      start_pos = qpos
    else
      -- Kapanış tırnağı: start_pos .. qpos aralığını hit olarak kaydet
      hits[#hits + 1] = {
        s    = start_pos,
        e    = qpos,
        kind = "quote",
      }
      in_quote  = false
      start_pos = nil
    end

    i = qpos + 1
  end

  -- Eğer tek tırnakla bitmişse (eşleşmemiş), yok sayıyoruz.
  return hits
end

function M.find(text)
  return find_quotes(text)
end

return M

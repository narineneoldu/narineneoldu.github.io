-- ../shared/lua/utils_time.lua
-- Saat ibarelerini tespit eder (HH:MM ve HH:MM:SS).
--
-- Public API:
--   M.find_times(text) ->
--       { { s = i1, e = j1, kind = "time", time_kind = "hhmm" | "hhmmss" }, ... }

local M = {}

-- frontier pattern'lar (span_time.lua ile aynı mantık)
local PAT_HHMMSS = '%f[%d]%d%d:%d%d:%d%d%f[%D]'
local PAT_HHMM   = '%f[%d]%d%d:%d%d%f[%D]'

local function find_next_time(s, i)
  local a1, b1 = s:find(PAT_HHMMSS, i)
  local a2, b2 = s:find(PAT_HHMM,   i)
  if a1 and (not a2 or a1 <= a2) then
    return a1, b1, "hhmmss"
  elseif a2 then
    return a2, b2, "hhmm"
  end
  return nil
end

local function find_hits(text)
  local hits = {}
  if not text:find(":", 1, true) then
    return hits
  end

  local i, n = 1, #text
  while i <= n do
    local a, b, kind = find_next_time(text, i)
    if not a then break end
    hits[#hits + 1] = {
      s         = a,
      e         = b,
      kind      = "time",
      time_kind = kind,
    }
    i = b + 1
  end

  return hits
end

function M.find(text)
  return find_hits(text)
end

return M

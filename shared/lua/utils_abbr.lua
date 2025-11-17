-- ../shared/lua/utils_abbr.lua
-- Abbreviation detection on plain strings using an external dictionary.
--
-- Public API:
--   M.set_dict(abbr_dict)
--   M.find_abbr(text) ->
--       { { s = i1, e = j1, kind = "abbr" }, ... }
--
--  * abbr_dict: plain Lua table, key -> full text (tooltip/title)
--  * "(KEY)" form is **not** marked as abbr (same as abbr.lua).

local M = {}

-- Meta'dan gelen sözlük burada cache'lenecek
local ABBR_DICT = nil

function M.set_dict(dict)
  if type(dict) == "table" and next(dict) ~= nil then
    ABBR_DICT = dict
  else
    ABBR_DICT = nil
  end
end

-- Internal: build keys sorted by length (longest first)
local function sorted_keys(dict)
  local keys = {}
  for k, _ in pairs(dict) do
    if type(k) == "string" and k ~= "" then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys, function(a, b) return #a > #b end)
  return keys
end

local function find_hits(text)
  local abbr_dict = ABBR_DICT
  if not abbr_dict or next(abbr_dict) == nil then
    return {}
  end

  local keys = sorted_keys(abbr_dict)
  if #keys == 0 then return {} end

  local hits = {}
  local i, n = 1, #text

  while i <= n do
    local matched = false

    -- 0) "(KEY)" formu: atla, işaretleme
    if text:sub(i,i) == "(" then
      for _, key in ipairs(keys) do
        local klen = #key
        if (i + klen + 1) <= n
           and text:sub(i+1, i+klen) == key
           and text:sub(i+klen+1, i+klen+1) == ")"
        then
          i = i + klen + 2
          matched = true
          break
        end
      end
    end

    -- 1) Düz KEY formu
    if not matched then
      for _, key in ipairs(keys) do
        local s1, e1 = text:find(key, i, true)
        if s1 == i then
          hits[#hits+1] = {
            s    = s1,
            e    = e1,
            kind = "abbr",
            -- istersen key de koyarsın:
            -- key  = key,
          }
          i = e1 + 1
          matched = true
          break
        end
      end
    end

    -- 2) Hiç eşleşme yoksa bir UTF-8 karakter ilerle
    if not matched then
      local nxt = utf8.offset(text, 2, i)
      local j = nxt and (nxt - 1) or n
      i = j + 1
    end
  end

  return hits
end

function M.find(text)
  return find_hits(text)
end

return M

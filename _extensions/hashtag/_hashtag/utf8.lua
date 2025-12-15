--[[
# _hashtag/utf8.lua

Minimal UTF-8 helpers for environments where Lua string indexing is byte-based.

Responsibilities:
  - Iterate UTF-8 characters (as substrings) from a byte index
  - Get the last UTF-8 character in a string
  - Get the UTF-8 character that ends at a specific byte position

Notes:
  - These helpers do not validate UTF-8 correctness; they assume valid input.
  - They are designed to be small and dependency-free.

Exports:
  - next_char(s, i) -> (char, next_index)
  - last_char(s) -> char|nil
  - char_before_byte(s, byte_pos) -> char|nil
]]

local M = {}

--[[
Return the UTF-8 character starting at byte index i, and the next byte index.

Parameters:
  s (string): UTF-8 string
  i (number): 1-based byte index

Returns:
  (string|nil, number|nil): (char, next_index)
]]
function M.next_char(s, i)
  local b = string.byte(s, i)
  if not b then return nil, nil end

  local len = 1
  if b >= 0xF0 then
    len = 4
  elseif b >= 0xE0 then
    len = 3
  elseif b >= 0xC0 then
    len = 2
  end

  return s:sub(i, i + len - 1), i + len
end

--[[
Return the last UTF-8 character in a string.

Parameters:
  s (string): UTF-8 string

Returns:
  string|nil: last character substring, or nil if empty
]]
function M.last_char(s)
  if not s or s == "" then return nil end

  local i = 1
  local last = nil
  while i <= #s do
    local ch
    ch, i = M.next_char(s, i)
    if not ch then break end
    last = ch
  end
  return last
end

--[[
Return the UTF-8 character that ends at byte_pos (inclusive).

Example:
  - If byte_pos points to the last byte of a multi-byte char, this returns that char.
  - If byte_pos points to a continuation byte inside a char, this returns nil.

Parameters:
  s (string): UTF-8 string
  byte_pos (number): 1-based byte index (inclusive)

Returns:
  string|nil: character substring, or nil if not aligned
]]
function M.char_before_byte(s, byte_pos)
  if not s or byte_pos < 1 then return nil end

  local k = 1
  while k <= byte_pos do
    local ch, nextk = M.next_char(s, k)
    if not ch or not nextk then break end

    -- nextk is the first byte after this char; nextk-1 is the last byte of this char
    if nextk - 1 == byte_pos then
      return ch
    end

    k = nextk
  end

  return nil
end

return M

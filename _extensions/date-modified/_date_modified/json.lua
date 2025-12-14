-- json.lua
-- Minimal JSON encode/decode for Lua tables.
-- Supports: nil, boolean, number, string, arrays, and object tables (string keys).

local json = {}

------------------------------------------------------------
-- ENCODE
------------------------------------------------------------

local function escape_str(s)
  s = s:gsub('\\', '\\\\')
       :gsub('"', '\\"')
       :gsub('\b', '\\b')
       :gsub('\f', '\\f')
       :gsub('\n', '\\n')
       :gsub('\r', '\\r')
       :gsub('\t', '\\t')
  return s
end

local function encode_value(v)
  local t = type(v)

  if t == "nil" then
    return "null"

  elseif t == "boolean" or t == "number" then
    return tostring(v)

  elseif t == "string" then
    return '"' .. escape_str(v) .. '"'

  elseif t == "userdata" then
    -- For Pandoc userdata (e.g., Meta* values) fall back to tostring().
    -- This avoids json.encode errors if a userdata sneaks into the table.
    return '"' .. escape_str(tostring(v)) .. '"'

  elseif t == "table" then
    -- Decide array vs object by inspecting keys
    local is_array = true
    local max_idx = 0
    for k, _ in pairs(v) do
      if type(k) ~= "number" then
        is_array = false
        break
      end
      if k > max_idx then
        max_idx = k
      end
    end

    if is_array then
      -- Encode as JSON array
      local parts = {}
      for i = 1, max_idx do
        parts[i] = encode_value(v[i])  -- no table.insert
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      -- Encode as JSON object
      local parts = {}
      local idx = 1
      for k, val in pairs(v) do
        local key = tostring(k)
        parts[idx] = encode_value(key) .. ":" .. encode_value(val)
        idx = idx + 1
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end

  else
    error("json.encode: unsupported type: " .. t)
  end
end

function json.encode(v)
  return encode_value(v)
end

------------------------------------------------------------
-- DECODE
------------------------------------------------------------

local function create_context(str)
  return { s = str, i = 1, len = #str }
end

local function skip_ws(ctx)
  local s, i, len = ctx.s, ctx.i, ctx.len
  while i <= len do
    local c = s:sub(i, i)
    if c ~= " " and c ~= "\t" and c ~= "\n" and c ~= "\r" then
      break
    end
    i = i + 1
  end
  ctx.i = i
end

local function peek(ctx)
  return ctx.s:sub(ctx.i, ctx.i)
end

local function next_char(ctx)
  local c = ctx.s:sub(ctx.i, ctx.i)
  ctx.i = ctx.i + 1
  return c
end

local function parse_string(ctx)
  local s, i, len = ctx.s, ctx.i, ctx.len
  local buf = {}

  -- assume current char is the opening quote
  local quote = next_char(ctx)

  while ctx.i <= len do
    local c = next_char(ctx)
    if c == '"' then
      break
    elseif c == "\\" then
      local esc = next_char(ctx)
      if esc == "b" then
        table.insert(buf, "\b")
      elseif esc == "f" then
        table.insert(buf, "\f")
      elseif esc == "n" then
        table.insert(buf, "\n")
      elseif esc == "r" then
        table.insert(buf, "\r")
      elseif esc == "t" then
        table.insert(buf, "\t")
      elseif esc == '"' or esc == "\\" or esc == "/" then
        table.insert(buf, esc)
      elseif esc == "u" then
        -- Very simple \uXXXX handling: skip four hex chars and ignore unicode.
        local hex = s:sub(ctx.i, ctx.i + 3)
        ctx.i = ctx.i + 4
        table.insert(buf, "?")
      else
        table.insert(buf, esc)
      end
    else
      table.insert(buf, c)
    end
  end

  return table.concat(buf)
end

local function parse_number(ctx)
  local s, i, len = ctx.s, ctx.i, ctx.len
  local start = i

  while i <= len do
    local c = s:sub(i, i)
    if not c:match("[%d%+%-%eE%.]") then
      break
    end
    i = i + 1
  end

  local num_str = s:sub(start, i - 1)
  ctx.i = i
  local num = tonumber(num_str)
  if not num then
    error("json.decode: invalid number '" .. num_str .. "'")
  end
  return num
end

local function parse_literal(ctx, literal, value)
  local s, i = ctx.s, ctx.i
  if s:sub(i, i + #literal - 1) ~= literal then
    error("json.decode: expected '" .. literal .. "'")
  end
  ctx.i = i + #literal
  return value
end

local parse_value

local function parse_array(ctx)
  -- assume current char is '['
  next_char(ctx) -- skip '['
  skip_ws(ctx)

  local arr = {}

  if peek(ctx) == "]" then
    next_char(ctx) -- skip ']'
    return arr
  end

  while true do
    local v = parse_value(ctx)
    table.insert(arr, v)
    skip_ws(ctx)

    local c = peek(ctx)
    if c == "]" then
      next_char(ctx)
      break
    elseif c == "," then
      next_char(ctx)
      skip_ws(ctx)
    else
      error("json.decode: expected ',' or ']' in array")
    end
  end

  return arr
end

local function parse_object(ctx)
  -- assume current char is '{'
  next_char(ctx) -- skip '{'
  skip_ws(ctx)

  local obj = {}

  if peek(ctx) == "}" then
    next_char(ctx)
    return obj
  end

  while true do
    skip_ws(ctx)
    if peek(ctx) ~= '"' then
      error("json.decode: expected string key")
    end
    local key = parse_string(ctx)
    skip_ws(ctx)
    if next_char(ctx) ~= ":" then
      error("json.decode: expected ':' after object key")
    end
    skip_ws(ctx)
    local val = parse_value(ctx)
    obj[key] = val
    skip_ws(ctx)

    local c = peek(ctx)
    if c == "}" then
      next_char(ctx)
      break
    elseif c == "," then
      next_char(ctx)
      skip_ws(ctx)
    else
      error("json.decode: expected ',' or '}' in object")
    end
  end

  return obj
end

parse_value = function(ctx)
  skip_ws(ctx)
  local c = peek(ctx)

  if c == "{" then
    return parse_object(ctx)
  elseif c == "[" then
    return parse_array(ctx)
  elseif c == '"' then
    return parse_string(ctx)
  elseif c == "-" or c:match("%d") then
    return parse_number(ctx)
  elseif c == "t" then
    return parse_literal(ctx, "true", true)
  elseif c == "f" then
    return parse_literal(ctx, "false", false)
  elseif c == "n" then
    return parse_literal(ctx, "null", nil)
  else
    error("json.decode: unexpected character '" .. c .. "'")
  end
end

function json.decode(str)
  local ctx = create_context(str)
  local ok, result = pcall(parse_value, ctx)
  if not ok then
    return nil, result
  end
  return result
end

return json

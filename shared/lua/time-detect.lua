-- time-detect.lua
-- HH:MM ve HH:MM:SS kalıplarını <span class="time-badge">...</span> ile sarar.

local List = require 'pandoc.List'

-- frontier-safe desenler: başında/sonunda rakam olmasın
local PAT_HHMMSS = '%f[%d]%d%d:%d%d:%d%d%f[%D]'
local PAT_HHMM   = '%f[%d]%d%d:%d%d%f[%D]'

-- Metinde i konumundan itibaren bir sonraki zamanı bul (önce HH:MM:SS, yoksa HH:MM)
local function find_next_time(s, i)
  local a1, b1 = s:find(PAT_HHMMSS, i)
  local a2, b2 = s:find(PAT_HHMM,   i)
  if a1 and (not a2 or a1 <= a2) then
    return a1, b1, 'hhmmss'
  elseif a2 then
    return a2, b2, 'hhmm'
  else
    return nil
  end
end

-- Str -> inline list: metni parçalayıp time-badge ekle
local function split_str_with_times(text)
  if not text:find(':', 1, true) then return nil end -- hızlı kaçış

  local out = List:new()
  local i, n = 1, #text
  while i <= n do
    local a, b = find_next_time(text, i)
    if not a then
      out:insert(pandoc.Str(text:sub(i)))
      break
    end
    if a > i then
      out:insert(pandoc.Str(text:sub(i, a-1)))
    end
    local tok = text:sub(a, b)
    out:insert(pandoc.Span({ pandoc.Str(tok) }, pandoc.Attr('', {'time-badge'})))
    i = b + 1
  end
  return out
end

-- HTML (RawInline/RawBlock) içinde de sar (gerekirse)
local function html_wrap_times(s)
  if not s:find(':', 1, true) then return s end
  if s:match('class="[^"]*time%-badge') then return s end -- idempotent koruma
  s = s:gsub('('..PAT_HHMMSS..')', '<span class="time-badge">%1</span>')
  s = s:gsub('('..PAT_HHMM..')',   '<span class="time-badge">%1</span>')
  return s
end

-- ---- Element handler’ları ----
function Str(el)
  local repl = split_str_with_times(el.text)
  if repl then return repl end
  return nil
end

function RawInline(el)
  if el.format == 'html' then
    el.text = html_wrap_times(el.text)
    return el
  end
  return nil
end

function RawBlock(el)
  if el.format == 'html' then
    el.text = html_wrap_times(el.text)
    return el
  end
  return nil
end

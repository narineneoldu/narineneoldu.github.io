-- ../shared/lua/span_unit_en.lua
-- EN units: day, month, year, hour, minute, second (plural optional)
-- Supports: ranges (X–Y, X with/and Y), "half (+ a/an) + unit", hyphenated forms
--           "41-second", "19-day", "half-hour", "half-day"
-- Guards:   HH:MM minutes & dd.mm.yyyy dates

local List = require 'pandoc.List'

-- -------- run -> plain text + map ----------
local function linearize(run)
  local buf, map, pos = {}, {}, 0
  for i, el in ipairs(run) do
    if el.t == "Str" then
      local s = el.text
      for k = 1, #s do
        pos = pos + 1
        buf[pos] = s:sub(k,k)
        map[pos] = { ix = i, off = k }
      end
    elseif el.t == "Space" or el.t == "SoftBreak" then
      pos = pos + 1
      buf[pos] = " "
      map[pos] = { ix = i, off = 0 }
    end
  end
  return table.concat(buf), map
end

-- -------- rebuild from hits ----------
local function rebuild(run, text, map, hits)
  if #hits == 0 then return run end
  table.sort(hits, function(a,b) return a.s<b.s or (a.s==b.s and a.e<b.e) end)

  local out, pos = List:new(), 1

  local function emit_plain(a,b)
    if b < a then return end
    local i = a
    while i <= b do
      local m = map[i]
      if not m then
        i = i + 1
      elseif m.off == 0 then
        out:insert(pandoc.Space()); i = i + 1
      else
        local ix, soff = m.ix, m.off
        local j, eoff = i, soff
        while j+1 <= b and map[j+1] and map[j+1].ix == ix and map[j+1].off == eoff+1 do
          j = j + 1; eoff = eoff + 1
        end
        out:insert(pandoc.Str(run[ix].text:sub(soff, eoff))); i = j + 1
      end
    end
  end

  for _, h in ipairs(hits) do
    if pos < h.s then emit_plain(pos, h.s - 1) end
    local parts, i = {}, h.s
    while i <= h.e do
      local m = map[i]
      if m and m.off == 0 then
        parts[#parts+1] = " "; i = i + 1
      elseif m then
        local ix, soff = m.ix, m.off
        local j, eoff = i, soff
        while j+1 <= h.e and map[j+1] and map[j+1].ix == ix and map[j+1].off == eoff+1 do
          j = j + 1; eoff = eoff + 1
        end
        parts[#parts+1] = run[ix].text:sub(soff, eoff); i = j + 1
      else
        i = i + 1
      end
    end
    out:insert(pandoc.Span({ pandoc.Str(table.concat(parts)) }, pandoc.Attr("", { h.class })))
    pos = h.e + 1
  end
  if pos <= #text then emit_plain(pos, #text) end
  return out
end

-- -------- patterns & helpers ----------
local NUM    = "%d+[.,]?%d*"
local DASHES = { "-", "\226\128\147", "\226\128\148", "\226\128\146", "\226\128\145", "\226\136\146", "x" }
local SP     = "[%s\194\160\226\128\175]+"
local BND    = "%f[%A]"   -- non-letter frontier

-- HH:MM guard (avoid treating the MM of HH:MM as minutes)
local function is_after_HHMM(s, start_idx)
  local L = math.max(1, start_idx - 5)
  local left = s:sub(L, start_idx - 1)
  return left:match("%d%d?%s*:%s*$") ~= nil
end

-- dd.mm.yyyy guard
local function inside_date_ddmmyyyy(s, a, b)
  local L = math.max(1, a - 5)
  local p, q = s:find("%d%d?%.%d%d?%.%d%d%d%d", L)
  while p do
    if not (q < a or p > b) then return true end
    p, q = s:find("%d%d?%.%d%d?%.%d%d%d%d", q + 1)
  end
  return false
end

local function include_left_space(s, i)
  if i > 1 then
    local prev = s:sub(i-1, i-1)
    if prev:match("[%s\194\160\226\128\175]") then return i - 1 end
  end
  return i
end

local function overlaps(a,b,r) return not (b < r.s or a > r.e) end

-- English units (plural optional)
local EN_UNITS = {
  { pat = "[Dd]ay[s]?",        class = "day"        },
  { pat = "[Mm]onth[s]?",      class = "month"      },
  { pat = "[Yy]ear%-old",      class = "year-old"   },
  { pat = "[Yy]ear[s]?",       class = "year"       },
  { pat = "[Hh]our[s]?",       class = "hour"       },
  { pat = "[Mm]inute[s]?",     class = "minute"     },
  { pat = "[Ss]econd[s]?",     class = "second"     },
  { pat = "[Ww]eek[s]?",       class = "week"       },
  { pat = "[Mm]eter[s]?",      class = "meter"      },
  { pat = "[Kk]ilometer[s]?",  class = "meter"      },
  { pat = "km",                class = "meter"      },
  { pat = "[Cc]entimeter[s]?", class = "centimeter" },
  { pat = "cm",                class = "centimeter" },
  { pat = "[Kk]ilogram[s]?",   class = "kilogram"   },
  { pat = "kg",                class = "kilogram"   },
}

local HALF_TOKS = { "half", "Half" }

local function push_hit(hits, s, i, j, class)
  if not inside_date_ddmmyyyy(s,i,j) and not is_after_HHMM(s,i) then
    i = include_left_space(s,i)
    for _, r in ipairs(hits) do if overlaps(i,j,r) then return end end
    hits[#hits+1] = { s = i, e = j, class = class }
  end
end

local function hits_with_token(s, token, class, hits)
  -- half + unit
  for _, H in ipairs(HALF_TOKS) do
    -- "half unit"
    for a,b in s:gmatch("()"..H..SP..token..BND.."()") do push_hit(hits, s, a, b-1, class) end
    -- "half a/an unit"
    for a,b in s:gmatch("()"..H..SP.."[Aa]n?"..SP..token..BND.."()") do push_hit(hits, s, a, b-1, class) end
    -- hyphenated: "half-unit" / "half–unit"
    for _, D in ipairs(DASHES) do
      for a,b in s:gmatch("()"..H.."%s*"..D.."%s*"..token..BND.."()") do push_hit(hits, s, a, b-1, class) end
    end
  end

  -- verbal range: "X with/and Y unit"
  for _, CC in ipairs({ "with", "and" }) do
    for a,b in s:gmatch("()"..NUM..SP..CC..SP..NUM..SP..token..BND.."()") do
      push_hit(hits, s, a, b-1, class)
    end
  end

  -- dashed range: "X–Y unit"
  for _, D in ipairs(DASHES) do
    for a,b in s:gmatch("()"..NUM.."%s*"..D.."%s*"..NUM..SP..token..BND.."()") do
      push_hit(hits, s, a, b-1, class)
    end
  end

  -- single: "NUM unit"
  for a,b in s:gmatch("()"..NUM..SP..token..BND.."()") do
    push_hit(hits, s, a, b-1, class)
  end

  -- hyphenated single: "NUM-unit" (e.g., 41-second, 19-day)
  for _, D in ipairs(DASHES) do
    for a,b in s:gmatch("()"..NUM.."%s*"..D.."%s*"..token..BND.."()") do
      push_hit(hits, s, a, b-1, class)
    end
  end
end

local function has_trace(text)
  return (
    text:find("[Dd]ay") or text:find("[Mm]onth") or text:find("[Yy]ear") or
    text:find("[Hh]our") or text:find("[Mm]inute") or text:find("[Ss]econd") or
    text:find("[Ww]eek") or text:find("[Mm]eter") or text:find("cm") or
    text:find("[Kk]ilometer") or text:find("[Cc]entimeter") or
    text:find("[Yy]ear%-old")
  )
end

local function find_hits(text)
  if not has_trace(text) then return {} end
  local hits = {}
  for _, u in ipairs(EN_UNITS) do
    hits_with_token(text, u.pat, u.class, hits)
  end

  table.sort(hits, function(a,b) return a.s<b.s or (a.s==b.s and a.e<b.e) end)
  local out = {}
  for _, h in ipairs(hits) do
    local keep = true
    for _, k in ipairs(out) do
      if overlaps(h.s,h.e,k) then
        if (h.e - h.s) <= (k.e - k.s) then keep = false end
      end
    end
    if keep then out[#out+1] = h end
  end
  return out
end

-- -------- Inlines ----------
local function is_textlike(el) return el.t=="Str" or el.t=="Space" or el.t=="SoftBreak" end
local function Inlines(inlines)
  local out, i, n = List:new(), 1, #inlines
  while i <= n do
    if is_textlike(inlines[i]) then
      local run, j = List:new(), i
      while j <= n and is_textlike(inlines[j]) do run:insert(inlines[j]); j = j + 1 end
      local text, map = linearize(run)
      local hits = find_hits(text)
      out:extend(rebuild(run, text, map, hits))
      i = j
    else
      local el = inlines[i]
      if el.content and type(el.content) == "table" then el.content = Inlines(el.content) end
      out:insert(el); i = i + 1
    end
  end
  return out
end

return { { Inlines = Inlines } }

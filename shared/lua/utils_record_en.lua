-- ../shared/lua/utils_record_number_en.lua
-- English record / article / section numbers after legal labels.
-- Examples:
--   "Article 5", "Art. 12", "Section 3(a)", "Case No. 2024/9732", "Law No. 3713"
--
-- Public API:
--   M.find_record_numbers(text) -> { { s = i1, e = j1, kind = "record_number" }, ... }

local M = {}

-- space, NBSP (00A0), NNBSP (202F)
local SP = "[%s\194\160\226\128\175]+"

-- ---- helpers ----

local function is_url_context(s, lpos)
  local from = math.max(1, lpos - 12)
  return s:sub(from, lpos):find("://") ~= nil
end

-- Labels that can precede the number (all lowercase; we lowercase input)
local LABELS = {
  "no",
  "no.",
  "number",
  "law no",
  "case no",
  "decision no",
  "article",
  "art",
  "art.",
  "section",
  "sec",
  "sec.",
  "subsection",
  "paragraph",
  "para",
  "para.",
  "clause",
  "numbered",
}

-- Check if the text immediately *before* lpos ends with one of LABELS
local function has_preceding_keyword(text, lpos)
  local head = text:sub(1, lpos - 1)

  -- Trim trailing SP (space / NBSP / NNBSP)
  head = head:gsub("(" .. SP .. ")$", "")
  -- Trim trailing punctuation: . , ; : ) ]
  head = head:gsub("[%.:,;%)%]]+$", "")
  -- Trim possible spaces again
  head = head:gsub("(" .. SP .. ")$", "")

  head = head:lower()

  for _, kw in ipairs(LABELS) do
    local pat = kw:gsub("%.", "%%.") .. "$"
    if head:find(pat) then
      return true
    end
  end

  return false
end

-- ---- main detector ----

local function find_hits(text)
  local hits = {}

  -- 1) General numeric token: "81/1", "2024/9732", "12-3", "37." etc.
  --    We do NOT include the trailing '.' in the span.
  for lpos, tok, dot, rpos in
    text:gmatch("()%f[%d](%d[%w%-/⁄∕]*)(%.?)()")
  do
    if not is_url_context(text, lpos)
       and has_preceding_keyword(text, lpos) then

      local e_core = lpos + #tok - 1
      hits[#hits+1] = { s = lpos, e = e_core }
    end
  end

  -- 2) Special case: "Section 5(a)" -> only "5" as record number
  for lpos, num in text:gmatch("()%f[%d](%d+)%(") do
    if not is_url_context(text, lpos)
       and has_preceding_keyword(text, lpos) then

      local e_core = lpos + #num - 1
      hits[#hits+1] = { s = lpos, e = e_core }
    end
  end

  -- Deduplicate overlaps (keep earlier / shorter first, same as TR util)
  table.sort(hits, function(a, b)
    return a.s < b.s or (a.s == b.s and a.e < b.e)
  end)

  local out = {}
  for _, h in ipairs(hits) do
    local keep = true
    for _, k in ipairs(out) do
      if not (h.e < k.s or h.s > k.e) then
        keep = false
        break
      end
    end
    if keep then
      out[#out+1] = h
    end
  end

  return out
end

-- ---- Public API ----

function M.find(text)
  local raw = find_hits(text)
  local out = {}

  for _, h in ipairs(raw) do
    out[#out+1] = {
      s    = h.s,
      e    = h.e,
      kind = "record",
    }
  end

  return out
end

return M

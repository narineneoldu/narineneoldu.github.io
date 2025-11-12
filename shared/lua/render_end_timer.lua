-- ../shared/lua/render_foot.lua
-- Per-page: measure render time, append to lang-specific temp file, set footer meta.

-- local t0 = os.clock()  -- high-resolution seconds (float)
if _G.__QRT_FOOT_DONE then return { } end

local t0 = _G.__QRT_T0 or os.clock()

local DEFAULT_MAX_LEN = 68

local function read_maxlen(lang)
  -- her zaman proje kökünden oku
  local root = os.getenv("QUARTO_PROJECT_DIR") or pandoc.system.get_working_directory() or "."
  local path = root .. "/.qrender-time-" .. lang .. ".json"

  local f = io.open(path, "r")
  if not f then
    return DEFAULT_MAX_LEN  -- dosya yoksa varsayılan döner
  end

  local s = f:read("*a")
  f:close()

  local m = s:match([["max%-length"%s*:%s*(%d+)]])
  if m then
    return tonumber(m)
  else
    return DEFAULT_MAX_LEN
  end
end

local function project_relative(abs)
  local root = os.getenv("QUARTO_PROJECT_DIR")
  if not (abs and root) then return abs end
  root = root:gsub("[/\\]$","")
  abs  = abs:gsub("^" .. root .. "[/\\]?", "")
  return abs
end

local function norm_join(base, rel)
  if not rel or rel == "" then return nil end
  if rel:match("^/") or rel:match("^%a:[/\\]") then return rel end
  return (base:gsub("[/\\]$","")) .. "/" .. rel
end

function get_source_path(rel)
  if rel == nil then rel = true end
  local src
  local cwd = pandoc.system.get_working_directory()

  -- 1) Quarto env var (preferred)
  local envsrc = os.getenv("QUARTO_INPUT_FILE")
  if envsrc and envsrc ~= "" then
    src = norm_join(cwd, envsrc)

  else
    -- 2) Derive from output_file
    local out = (PANDOC_STATE and PANDOC_STATE.output_file) or ""
    if out ~= "" then
      local path = out
      if path:match("[/\\]index%.html$") then
        path = path:gsub("index%.html$", "index.qmd")
      else
        path = path:gsub("%.[^./\\]+$", ".qmd")
      end
      src = norm_join(cwd, path)
    else
      -- 3) Fallback: first input
      local first = (PANDOC_STATE and PANDOC_STATE.input_files and PANDOC_STATE.input_files[1]) or nil
      if first and first ~= "" then
        src = norm_join(cwd, first)
      end
    end
  end

  -- ✅ Eğer rel=true ise project_relative uygula
  if rel and src then
    src = project_relative(src)
  end

  return src
end

local function label_for_lang(lang)
  if lang and lang:match("^tr") then return "Derleme süresi" end
  return "Render time"
end

local function unit_for_lang(lang, unit)
  if lang and lang:match("^tr") and unit == "sec" then return "s" end
  return unit
end

-- --- module table ---
local M = {}

function M.Pandoc(doc)
  _G.__QRT_FOOT_DONE = true
  local t0 = _G.__QRT_T0 or os.clock()
  local rel = get_source_path()
  local dt = os.clock() - t0          -- seconds (float)
  local ms = dt * 1000.0              -- milliseconds (float)
  local lang = (doc.meta.lang and pandoc.utils.stringify(doc.meta.lang)) or "en"

  -- Write to a temp, lang-specific tsv at project root:
  -- format: "<fname>\t<ms with 3 decimals>\n"
  local tmp = (lang:match("^tr") and ".qrender-time.tmp-tr.tsv" or ".qrender-time.tmp-en.tsv")
  local f = io.open(tmp, "a")
  if f then
    f:write(string.format("%s\t%.3f\n", rel, ms))
    f:close()
  else
    io.stderr:write("cannot open " .. tmp .. "\n")
  end

  -- Footer meta (HTML)
  local unit = "ms"
  local display = string.format("%.0f", ms)
  if ms >= 1000 then
    unit = "sec"
    display = string.format("%.3f", dt)
  end

  local maxlen = read_maxlen(lang) + 10
  -- print(maxlen)
  -- Print to console
  io.stderr:write(string.format("\27[A\27[%dG⏱️  \27[36m%s %s\27[0m\n", maxlen, display, unit))

  unit = unit_for_lang(lang, unit)
  local html = string.format(
    '<span class="footer-render"><span class="footer-render-label">%s</span><span class="footer-render-value">⏱️ %s %s</span></span>',
    label_for_lang(lang), display, unit
  )
  doc.meta["render-time-footer"] = pandoc.MetaString(html)

  return doc
end

return M

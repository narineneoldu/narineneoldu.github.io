-- ../shared/lua/render_end_timer.lua
-- Per-page: measure render time, compare with previous JSON, keep value stable if diff is small.

if _G.__QRT_FOOT_DONE then return { } end

local t0 = _G.__QRT_T0 or os.clock()
local DEFAULT_MAX_LEN = 68

-- Küçük yardımcılar ---------------------------------------------------------

local function project_root()
  return os.getenv("QUARTO_PROJECT_DIR")
      or pandoc.system.get_working_directory()
      or "."
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

-- Şu anki giriş QMD yolunu (proje köküne göre) bul
function get_source_path(rel)
  if rel == nil then rel = true end
  local src
  local cwd = pandoc.system.get_working_directory()

  local envsrc = os.getenv("QUARTO_INPUT_FILE")
  if envsrc and envsrc ~= "" then
    src = norm_join(cwd, envsrc)
  else
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
      local first = (PANDOC_STATE and PANDOC_STATE.input_files
                     and PANDOC_STATE.input_files[1]) or nil
      if first and first ~= "" then
        src = norm_join(cwd, first)
      end
    end
  end

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

local function lang_code(lang)
  if lang and lang:match("^tr") then return "tr" end
  return "en"
end

-- JSON içindeki özel karakterleri Lua pattern için kaçır
local function escape_lua_pattern(s)
  return s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

-- .qrender-time-XX.json içinden önceki ms değerini oku
local function read_prev_ms(lang, rel_qmd)
  local code = lang_code(lang)       -- "tr" / "en"
  local root = project_root()
  local path = root .. "/.qrender-time-" .. code .. ".json"

  local f = io.open(path, "r")
  if not f then return nil end

  local s = f:read("*a")
  f:close()

  -- Dosya içindeki "files" bölümünde: "rel_path": 123.456
  -- rel_qmd POSIX formda (emit_render_json.py de öyle yazıyor)
  local key = escape_lua_pattern(rel_qmd)
  local pattern = '"' .. key .. '"%s*:%s*([%d%.]+)'

  local ms_str = s:match(pattern)
  if not ms_str then return nil end

  local ms = tonumber(ms_str)
  return ms
end

-- max-length için (önceden yaptığın gibi)
local function read_maxlen(lang)
  local code = lang_code(lang)
  local root = project_root()
  local path = root .. "/.qrender-time-" .. code .. ".json"

  local f = io.open(path, "r")
  if not f then
    return DEFAULT_MAX_LEN
  end
  local s = f:read("*a")
  f:close()

  local m = s:match([["max%-length"%s*:%s*(%d+)]])
  return m and tonumber(m) or DEFAULT_MAX_LEN
end

-- ---------------------------------------------------------------------------

local M = {}

function M.Pandoc(doc)
  _G.__QRT_FOOT_DONE = true

  local t0 = _G.__QRT_T0 or os.clock()
  local rel = get_source_path(true)          -- ör: "trial/judgment.qmd"
  local dt  = os.clock() - t0                -- saniye (float)
  local ms  = dt * 1000.0                    -- ms
  local lang = (doc.meta.lang and pandoc.utils.stringify(doc.meta.lang)) or "en"
  local code = lang_code(lang)

  -- Eski süreyi JSON’dan bul
  local prev_ms = nil
  if rel then
    prev_ms = read_prev_ms(lang, rel)
  end

  -- Fark küçükse eski ms’i kullan (hem JSON’a yazarken hem footer’da)
  local THRESH_MS_ORDER = 100    -- Eşik ms
  local THRESH_MS = 5 * THRESH_MS_ORDER  -- Threshold milliseconds
  local eff_ms = ms
  if prev_ms and math.abs(ms - prev_ms) < THRESH_MS then
    eff_ms = prev_ms
  end

  -- ROUNDING
  local eff_ms_org = eff_ms
  eff_ms = math.floor((eff_ms / THRESH_MS_ORDER) + 0.5) * THRESH_MS_ORDER

  local eff_dt_org = eff_ms_org / 1000.0
  local eff_dt = eff_ms / 1000.0

  -- tmp tsv’ye (emit_render_json.py için) effective değeri yaz
  local tmp = (code == "tr" and ".qrender-time.tmp-tr.tsv"
                             or ".qrender-time.tmp-en.tsv")

  local f = io.open(tmp, "a")
  if f then
    f:write(string.format("%s\t%.3f\n", rel or "?", eff_ms))
    f:close()
  else
    io.stderr:write("cannot open " .. tmp .. "\n")
  end

  -- HTML eff_ms üzerinden yaz
  local unit = "ms"
  local display = string.format("%.0f", eff_ms)
  if eff_ms >= 1000 then
    unit = "s"
    display = string.format("%.1f", eff_dt)
  end

  -- Konsol'da eff_ms_org üzerinden yaz
  local unit = "ms"
  local display_console = string.format("%4.0f", eff_ms_org)
  if eff_ms_org >= 1000 then
    unit = "s"
    display_console = string.format("%4.1f", eff_dt_org)
  end

  local maxlen = read_maxlen(lang) + 10
  io.stderr:write(string.format(
    "\27[A\27[%dG⏱️  \27[36m%s %s\27[0m\n",
    maxlen, display_console, unit
  ))

  unit = unit_for_lang(lang, unit)

  local html = string.format(
    '<span class="footer-render"><span class="footer-render-label">%s</span><span class="footer-render-value">⏱️ %s %s</span></span>',
    label_for_lang(lang), display, unit
  )

  doc.meta["render-time-footer"] = pandoc.MetaString(html)
  return doc
end

return M

-- ../shared/lua/lastmod.lua
-- Git son commit zamanını kullanır; bulunamazsa "şimdi"ye düşer.

local DEFAULT_URL = "https://github.com/narineneoldu/narineneoldu.github.io"

local MONTHS = {
  tr = {"Oca","Şub","Mar","Nis","May","Haz","Tem","Ağu","Eyl","Eki","Kas","Ara"},
  en = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}
}

local function trim(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end

local function git_last_commit_repo(root_dir)
  if not root_dir or root_dir == "" then return nil end
  local cmd = 'git -C "' .. root_dir:gsub('"','\\"') .. '" log -1 --format=%cI 2>/dev/null'
  local p = io.popen(cmd); if not p then return nil end
  local s = p:read("*l"); p:close()
  return (s and s ~= "") and (s:gsub("^%s+",""):gsub("%s+$","")) or nil
end

-- Kaynak dosya yolunu bul (project-relative değil; git'e geçilecek)
local function get_source_path()
  local src = os.getenv("QUARTO_INPUT_FILE")
  if not src or src == "" then
    local out = (PANDOC_STATE and PANDOC_STATE.output_file) or ""
    if out ~= "" then
      if out:match("[/\\]index%.html$") then
        src = out:gsub("index%.html$", "index.qmd")
      else
        src = out:gsub("%.[^./\\]+$", ".qmd")
      end
    end
  end
  -- Pandoc çalışma dizini (absolute)
  local cwd = pandoc.system.get_working_directory() or "."
  if src and not src:match("^/") and not src:match("^%a:[/\\]") then
    src = cwd .. "/" .. src
  end
  return src
end

-- Dosyanın son commit zamanını ISO-8601 olarak döndür (örn. 2024-08-21T12:34:56+03:00)
local function git_last_commit_iso(abs_path)
  if not abs_path then return nil end
  -- Çoğu ortamda çalışır; Windows’ta da git bash/WSL altında yürür.
  local cmd = 'git log -1 --format=%cI -- "' .. abs_path:gsub('"','\\"') .. '" 2>/dev/null'
  local p = io.popen(cmd)
  if not p then return nil end
  local s = p:read("*l"); p:close()
  if s and s ~= "" then return trim(s) end
  return nil
end

-- ISO’dan (YYYY-MM-DDTHH:MM...) gün/ay/yıl/saat/dak çıkart (TZ ofsetini önemsemiyoruz)
local function parse_iso_ymdhm(iso)
  local y, m, d, hh, mm = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d)")
  if not y then return nil end
  return tonumber(y), tonumber(m), tonumber(d), tonumber(hh), tonumber(mm)
end

local M = {}

function M.Meta(m)
  local lang = pandoc.utils.stringify(m["lang"] or "tr")

  -- Kaynağı bul ve git’ten ISO zamanı al; yoksa şimdi
  local src_abs   = get_source_path()

  local project_root = (os.getenv("QUARTO_PROJECT_DIR") or pandoc.system.get_working_directory() or ".")
  project_root = project_root:gsub("[/\\]+$","")

  local is_root_index = (src_abs and src_abs:gsub("[/\\]+$",""):match("[/\\]index%.qmd$"))
                     and (src_abs:gsub("[/\\]index%.qmd$","") == project_root)

  local iso_git = nil
  if is_root_index then
    -- ANA SAYFA: repo’nun en son commit’i
    iso_git = git_last_commit_repo(project_root)
  else
    -- diğer sayfalar: dosya bazlı commit
    iso_git = git_last_commit_iso(src_abs)
  end

  local iso_final = iso_git or os.date("!%Y-%m-%dT%H:%M:%SZ")

  -- İnsan-dostu tarih/saat
  local y, mon, d, hh, mm = parse_iso_ymdhm(iso_final)  -- TZ ofseti gösterilmiyor
  local month_name = (lang == "en") and MONTHS.en[(mon or os.date("!%m")+0)] or MONTHS.tr[(mon or os.date("!%m")+0)]
  local date_human
  if lang == "en" then
    date_human = string.format("%s %02d, %04d", month_name, d or os.date("!%d")+0, y or os.date("!%Y")+0)
  else
    date_human = string.format("%02d %s %04d", d or os.date("!%d")+0, month_name, y or os.date("!%Y")+0)
  end
  local time_human = string.format("%02d:%02d", hh or os.date("!%H")+0, mm or os.date("!%M")+0)

  -- SEO meta (Google: itemprop="dateModified")
  m["date-modified"] = pandoc.MetaString(iso_final)

  -- repo-url -> commits link
  local base_repo = pandoc.utils.stringify(m["repo-url"] or DEFAULT_URL)
  base_repo = base_repo:gsub("/+$","")
  local href = base_repo .. "/commits/main/"

  -- Footer HTML
  local label = (lang == "en") and "Updated on" or "Güncelleme:"
  local hour_lbl = (lang == "en") and "at" or ""  -- TR’de “, HH:MM” yeterli
  local sep = (lang == "en") and (" " .. hour_lbl .. " ") or ", "

  local html = string.format(
    '<span class="footer-updated">%s<br><a href="%s" target="_blank" rel="noopener">%s%s%s</a></span>',
    label, href, date_human, sep, time_human
  )
  m["last-updated-footer"] = pandoc.MetaString(html)

  return m
end

return M

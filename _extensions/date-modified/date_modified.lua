--[[
  date_modified.lua

  Quarto / Pandoc Lua filter that derives an accurate "last modified" timestamp
  for each page and injects:

    1. SEO-friendly <meta> tags into the HTML <head>:
         - <meta itemprop="dateModified" ...>
         - <meta property="article:modified_time" ...>
         - <meta name="dcterms.modified" ...>

    2. A localized HTML snippet exposed as `m["modification-date"]` that:
         - Renders a label (e.g. "Güncelleme" / "Updated"), unless hidden.
         - Renders a human-readable UTC date (and optionally time).
         - Optionally wraps the date value in a link to the file’s GitHub
           commit history.

  Timestamp source strategy:
    - If `use_mtime` is true:
        always use filesystem mtime + a small JSON state file
        (`.quarto/date-modified.json`) to derive a stable UTC ISO 8601 timestamp.

    - If `use_mtime` is false (default):
        * Prefer Git:
            - For the project root `index.qmd`: use the latest commit in the repo.
            - For other pages: use the last commit that touched the source file.
        * If Git lookup fails (or Git is not available), fall back to mtime + state.

  Configuration (global via _quarto.yml, under `metadata:`):

    metadata:
      date-modified-config:
        use-mtime: false      # if true: always use mtime+state, ignore Git
        hide-time: false      # if true: hide time part; show only date
        repo-url: ""          # explicit repo URL; if empty, try Git remote
        repo-branch: "main"   # branch to use in commit-history links
        hide-label: false     # if true: do not render label
        hide-link: true       # if true: do not generate a GitHub history link

  The resulting footer HTML has the form:

      <span class="date-modified">
        <span class="date-modified-label">Güncelleme</span>
        <span class="date-modified-value">09 Ara 2025 14:32 UTC</span>
      </span>

  or, when links are enabled:

      <span class="date-modified">
        <span class="date-modified-label">Güncelleme</span>
        <span class="date-modified-value">
          <a href="https://github.com/.../commits/main/path/to/file.qmd" target="_blank" rel="noopener">
            09 Ara 2025 14:32 UTC
          </a>
        </span>
      </span>
]]

local deps      = require("deps")
local json      = require("json")
local language  = require("language")

------------------------------------------------------------
-- Configuration and constants
------------------------------------------------------------

--- Default configuration for date-modified behavior.
--  Values may be overridden from Quarto metadata:
--    metadata:
--      date-modified-config: { ... }
local DEFAULT_CONFIG = {
  -- Strategy switches
  use_mtime    = false,  -- if true: always use mtime+state, ignore Git
  hide_time    = false,  -- if true: hide time component (only date)

  -- Repository / link behavior
  repo_url     = "",     -- can be overridden from metadata
  repo_branch  = "main", -- branch used in GitHub history URLs
  hide_label   = false,  -- if true: hide label
  hide_link    = false,  -- if true: do not render link, only plain text

  -- Optional overrides for date/time formatting;
  -- if nil, values from language file will be used.
  date_format  = nil,
  time_format  = nil,
}

------------------------------------------------------------
-- Generic utilities (strings, shell)
------------------------------------------------------------

--- Trim leading and trailing whitespace from a string.
-- @param s string: input string
-- @return string: trimmed string
local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Return the Git repository top-level directory for a given working directory.
-- Uses `git -C <dir> rev-parse --show-toplevel`.
-- @param root_dir string|nil: directory inside the repo (defaults to CWD)
-- @return string|nil: absolute path to Git top-level, or nil on failure
local function git_toplevel(root_dir)
  local base = root_dir or pandoc.system.get_working_directory() or "."
  local cmd = 'git -C "' .. base:gsub('"', '\\"') .. '" rev-parse --show-toplevel 2>/dev/null'
  local p = io.popen(cmd)
  if not p then return nil end
  local s = p:read("*l")
  p:close()
  return (s and s ~= "") and trim(s) or nil
end

------------------------------------------------------------
-- Git helpers (timestamps, remote URL)
------------------------------------------------------------

--- Get the latest commit ISO 8601 date-time for the whole repository.
-- Runs: `git -C <root_dir> log -1 --format=%cI`
-- @param root_dir string: path to repo root
-- @return string|nil: ISO-8601 timestamp (with offset) or nil on failure
local function git_last_commit_repo(root_dir)
  if not root_dir or root_dir == "" then return nil end
  local cmd = 'git -C "' .. root_dir:gsub('"', '\\"') .. '" log -1 --format=%cI 2>/dev/null'
  local p = io.popen(cmd)
  if not p then return nil end
  local s = p:read("*l")
  p:close()
  return (s and s ~= "") and trim(s) or nil
end

--- Get the latest commit ISO 8601 date-time for a given file.
-- Runs: `git log -1 --format=%cI -- "<abs_path>"`
-- @param abs_path string: absolute file path
-- @return string|nil: ISO-8601 timestamp (with offset) or nil on failure
local function git_last_commit_iso(root_dir, abs_path)
  if not root_dir or root_dir == "" then return nil end
  if not abs_path or abs_path == "" then return nil end

  local cmd =
    'git -C "' .. root_dir:gsub('"', '\\"') .. '" log -1 --format=%cI -- "' ..
    abs_path:gsub('"', '\\"') .. '" 2>/dev/null'

  local p = io.popen(cmd)
  if not p then return nil end
  local s = p:read("*l")
  p:close()
  return (s and s ~= "") and trim(s) or nil
end

--- Retrieve the `remote.origin.url` from Git configuration.
-- Runs: `git -C <root_dir> config --get remote.origin.url`
-- @param root_dir string: path to repo root
-- @return string|nil: raw remote URL or nil on failure
local function git_remote_origin(root_dir)
  if not root_dir or root_dir == "" then return nil end
  local cmd = 'git -C "' .. root_dir:gsub('"', '\\"') .. '" config --get remote.origin.url 2>/dev/null'
  local p = io.popen(cmd)
  if not p then return nil end
  local s = p:read("*l")
  p:close()
  return (s and s ~= "") and trim(s) or nil
end

--- Normalize a Git remote URL to a clean https://github.com/... form.
-- Handles patterns like:
--   * git@github.com:user/repo.git
--   * https://github.com/user/repo(.git)?
-- Other URLs are returned unchanged.
-- @param url string: remote URL
-- @return string|nil: normalized GitHub URL or nil if input is empty
local function normalize_github_url(url)
  if not url or url == "" then return nil end
  url = trim(url)

  -- git@github.com:user/repo.git
  local user, repo = url:match("^git@github%.com:([^/]+)/([^%.]+)%.git$")
  if user and repo then
    return string.format("https://github.com/%s/%s", user, repo)
  end

  -- https://github.com/user/repo(.git)?
  local path = url:match("^https://github%.com/([^%s]+)")
  if path then
    path = path:gsub("%.git$", "")
    return "https://github.com/" .. path
  end

  return url
end

------------------------------------------------------------
-- Path and ISO timestamp parsing
------------------------------------------------------------

--- Resolve the current page's source `.qmd` absolute path.
-- Priority order:
--   1) Environment variable QUARTO_INPUT_FILE (if set).
--   2) PANDOC_STATE.output_file, mapped from .html to .qmd.
-- The result is normalized to an absolute path using the working directory.
-- @return string|nil: absolute path to source .qmd or nil if not inferable
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

  local cwd = pandoc.system.get_working_directory() or "."
  if src and not src:match("^/") and not src:match("^%a:[/\\]") then
    src = cwd .. "/" .. src
  end
  return src
end

--- Parse an ISO-like datetime (YYYY-MM-DDTHH:MM...) into basic components.
-- Time zone offset is ignored; only Y/M/D/H/M are extracted.
-- @param iso string: ISO-like timestamp
-- @return number?, number?, number?, number?, number?:
--         year, month, day, hour, minute (or nil on parse failure)
local function parse_iso_ymdhm(iso)
  local y, m, d, hh, mm = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d)")
  if not y then return nil end
  return tonumber(y), tonumber(m), tonumber(d), tonumber(hh), tonumber(mm)
end

--- Normalize an ISO 8601 timestamp to UTC "Z" notation.
-- Accepts:
--   * YYYY-MM-DDTHH:MM:SS±HH:MM
--   * or already-UTC (…Z)
-- If parsing fails, returns the input string untouched.
-- @param iso string: ISO 8601 string with offset or Z
-- @return string: ISO-8601 in UTC (YYYY-MM-DDTHH:MM:SSZ) or original on error
local function iso_to_utc_z(iso)
  if not iso or iso == "" then return nil end
  if iso:match("Z$") then
    return iso
  end

  local y, mo, d, hh, mm, ss, sign, oh, om =
    iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)([%+%-])(%d%d):(%d%d)")

  if not y then
    -- Unexpected format; leave as-is.
    return iso
  end

  y, mo, d   = tonumber(y), tonumber(mo), tonumber(d)
  hh, mm, ss = tonumber(hh), tonumber(mm), tonumber(ss)
  oh, om     = tonumber(oh), tonumber(om)

  local offset = oh * 3600 + om * 60
  if sign == "-" then
    offset = -offset
  end

  local t_local = os.time {
    year  = y,
    month = mo,
    day   = d,
    hour  = hh,
    min   = mm,
    sec   = ss,
  }

  if not t_local then
    return iso
  end

  local t_utc = t_local - offset
  return os.date("!%Y-%m-%dT%H:%M:%SZ", t_utc)
end

------------------------------------------------------------
-- Metadata helpers (reading config from pandoc.Meta)
------------------------------------------------------------

--- Interpret a pandoc Meta value as a boolean, with a default.
-- Accepts MetaBool or string-like "true"/"false"/"1"/"0".
-- @param meta_value any: pandoc Meta value
-- @param default boolean: default to use if not parseable
-- @return boolean: interpreted boolean
local function meta_bool(meta_value, default)
  if not meta_value then return default end
  if type(meta_value) == "table" and meta_value.t == "MetaBool" then
    return meta_value.c
  end
  local s = pandoc.utils.stringify(meta_value)
  if s == "true" or s == "True" or s == "1" then return true end
  if s == "false" or s == "False" or s == "0" then return false end
  return default
end

--- Interpret a pandoc Meta value as a string, with a default.
-- Empty string falls back to default.
-- @param meta_value any: pandoc Meta value
-- @param default string: default string
-- @return string: interpreted string
local function meta_string(meta_value, default)
  if not meta_value then return default end
  local s = pandoc.utils.stringify(meta_value)
  if s == "" then return default end
  return s
end

--- Merge DEFAULT_CONFIG with project-level metadata in `m`.
-- Reads `metadata.date-modified-config` if present and applies overrides.
-- @param m pandoc.Meta: document metadata
-- @return table: effective configuration table
local function read_config(m)
  -- Start with shallow copy of DEFAULT_CONFIG.
  local cfg = {}
  for k, v in pairs(DEFAULT_CONFIG) do
    cfg[k] = v
  end

  -- Optional website-level repo config.
  local website = m["website"]
  if type(website) == "table" then
    cfg.repo_url    = meta_string(website["repo-url"],    cfg.repo_url)
    cfg.repo_branch = meta_string(website["repo-branch"], cfg.repo_branch)
  end

  -- Project-level configuration block:
  --   metadata:
  --     date-modified-config: { ... }
  local dm = m["date-modified-config"]
  if type(dm) == "table" then
    cfg.use_mtime   = meta_bool(dm["use-mtime"],     cfg.use_mtime)
    cfg.hide_time   = meta_bool(dm["hide-time"],     cfg.hide_time)
    cfg.repo_url    = meta_string(dm["repo-url"],    cfg.repo_url)
    cfg.repo_branch = meta_string(dm["repo-branch"], cfg.repo_branch)
    cfg.hide_label  = meta_bool(dm["hide-label"],    cfg.hide_label)
    cfg.hide_link   = meta_bool(dm["hide-link"],     cfg.hide_link)

    -- Optional generic overrides; if not set, language file values are used
    cfg.date_format = meta_string(dm["date-format"], cfg.date_format)
    cfg.time_format = meta_string(dm["time-format"], cfg.time_format)
  end

  return cfg
end

------------------------------------------------------------
-- Date / time formatting helpers (token-based)
------------------------------------------------------------

--- Format a date (year, month, day) according to a token-based pattern.
-- Supported tokens:
--   YYYY: four-digit year
--   MM  : two-digit month
--   DD  : two-digit day
--   MMM : localized month abbreviation, provided by language module
-- @param months table: array[12] of month abbreviations
-- @param y number: year
-- @param mon number: month (1–12)
-- @param d number: day (1–31)
-- @param pattern string: pattern template
-- @return string|nil: formatted date or nil if inputs are missing
local function format_date(months, y, mon, d, pattern)
  if not (y and mon and d) then return nil end

  local has_month_names = (type(months) == "table") and (months[mon] ~= nil)
  local full_name = has_month_names and months[mon] or ""
  local short_name = has_month_names and full_name:sub(1, 3) or ""

  local result = pattern

  -- Yıl her durumda aynı
  result = result:gsub("YYYY", string.format("%04d", y))

  if has_month_names then
    -- Dil dosyasındaki isimleri kullan
    result = result:gsub("MMMM", full_name)
    result = result:gsub("MMM",  short_name)
  else
    -- Ay isimleri yoksa, MMM ve MMMM'u da sayısal aya map et
    local mm_num = string.format("%02d", mon)
    result = result:gsub("MMMM", mm_num)
    result = result:gsub("MMM",  mm_num)
  end

  -- MM ve DD her durumda sayısal
  result = result:gsub("MM", string.format("%02d", mon))
  result = result:gsub("DD", string.format("%02d", d))

  return result
end

--- Format time (hour, minute) according to a token-based pattern.
-- Supported tokens:
--   HH: two-digit hour (00–23)
--   mm: two-digit minute (00–59)
-- @param hh number: hour
-- @param mm number: minute
-- @param pattern string: pattern template
-- @return string|nil: formatted time or nil if inputs are missing
local function format_time(hh, mm, pattern)
  if not (hh and mm) then return nil end
  local result = pattern
  result = result:gsub("HH", string.format("%02d", hh))
  result = result:gsub("mm", string.format("%02d", mm))
  return result
end

------------------------------------------------------------
-- Filesystem mtime + JSON state helpers
------------------------------------------------------------

--- Get filesystem mtime (seconds since epoch) for a path, portable across
-- BSD/macOS and GNU coreutils `stat` variants.
-- @param path string: file path
-- @return number|nil: mtime as integer seconds or nil on failure
local function file_mtime(path)
  if not path or path == "" then return nil end

  -- macOS / BSD: stat -f %m
  local cmd = 'stat -f %m "' .. path:gsub('"', '\\"') .. '" 2>/dev/null'
  local p = io.popen(cmd)
  local s = p and p:read("*l") or nil
  if p then p:close() end
  if s and s ~= "" then
    local t = tonumber(s)
    if t then return t end
  end

  -- GNU coreutils: stat -c %Y
  cmd = 'stat -c %Y "' .. path:gsub('"', '\\"') .. '" 2>/dev/null'
  p = io.popen(cmd)
  s = p and p:read("*l") or nil
  if p then p:close() end
  if s and s ~= "" then
    local t = tonumber(s)
    if t then return t end
  end

  return nil
end

--- Compute the path to the JSON state file under .quarto.
-- @param project_root string: project root directory
-- @return string: absolute path to state file
local function state_path(project_root)
  return project_root .. "/.quarto/date-modified.json"
end

--- Ensure that the `.quarto` directory exists under the project root.
-- Best effort; ignores failures.
-- @param project_root string: project root directory
local function ensure_quarto_dir(project_root)
  local dir = project_root .. "/.quarto"
  os.execute('mkdir -p "' .. dir:gsub('"', '\\"') .. '" 2>/dev/null')
end

--- Load JSON state table from `.quarto/date-modified.json`.
-- On missing or invalid file, returns an empty table.
-- @param project_root string: project root directory
-- @return table: state table indexed by relative path or abs path
local function load_state(project_root)
  ensure_quarto_dir(project_root)
  local path = state_path(project_root)
  local f = io.open(path, "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then
    return {}
  end
  local t, _ = json.decode(content)
  if type(t) ~= "table" then
    return {}
  end
  return t
end

--- Save JSON state table to `.quarto/date-modified.json`.
-- @param project_root string: project root directory
-- @param state table: state table to serialize
local function save_state(project_root, state)
  ensure_quarto_dir(project_root)
  local path = state_path(project_root)
  local f = io.open(path, "w")
  if not f then return end
  f:write(json.encode(state))
  f:close()
end

--- Compute a stable ISO 8601 UTC timestamp from mtime with minimal state caching.
-- For a given file (identified by rel_path or abs_path), this function:
--   * Reads the current mtime from the filesystem.
--   * Looks up the last stored {mtime, iso} in the state file.
--   * If mtime has changed or there is no entry, recomputes ISO and updates state.
--   * Otherwise, reuses the stored ISO value.
-- @param project_root string: project root directory
-- @param rel_path string|nil: project-relative path used as key (preferred)
-- @param abs_path string: absolute file path
-- @return string|nil: ISO-8601 UTC timestamp (YYYY-MM-DDTHH:MM:SSZ) or nil
local function iso_from_mtime(project_root, rel_path, abs_path)
  if not abs_path then return nil end
  local mtime = file_mtime(abs_path)
  if not mtime then return nil end

  local key = rel_path or abs_path
  local state = load_state(project_root)
  local entry = state[key]

  if not entry or entry.mtime ~= mtime then
    local iso = os.date("!%Y-%m-%dT%H:%M:%SZ", mtime)
    state[key] = { mtime = mtime, iso = iso }
    save_state(project_root, state)
    return iso
  else
    return entry.iso
  end
end

local function escape_html(s)
  s = tostring(s or "")
  s = s:gsub("&", "&amp;")
       :gsub("<", "&lt;")
       :gsub(">", "&gt;")
       :gsub('"', "&quot;")
       :gsub("'", "&#39;")
  return s
end

------------------------------------------------------------
-- Main Pandoc filter: Meta
------------------------------------------------------------

--- Pandoc Meta filter that:
--   * Determines the effective config from document metadata.
--   * Chooses a "last modified" timestamp using Git or mtime.
--   * Injects SEO meta tags into `header-includes`.
--   * Exposes an HTML snippet as `m["modification-date"]`.
-- @param m pandoc.Meta: document metadata
-- @return pandoc.Meta: updated metadata with modification-date and header-includes
function Meta(m)
  deps.ensure_html_dependency()

  -- Load language resources (may warn or error as configured).
  local lang_info = language.load(m)

  -- Expose JS i18n data (if present) to the browser as JSON in <head>
  if lang_info.js_data and type(lang_info.js_data) == "table" then
    deps.ensure_i18n_json(m, "date-modified-i18n", lang_info.js_data)
  end

  -- Resolve project root and Git root.
  local project_root = (os.getenv("QUARTO_PROJECT_DIR")
                        or pandoc.system.get_working_directory()
                        or ".")
  project_root = project_root:gsub("[/\\]+$", "")
  local git_root = git_toplevel(project_root) or project_root

  -- Determine the current source file path.
  local src_abs = get_source_path()

  -- Is this the project root index.qmd?
  local is_root_index =
    (src_abs and src_abs:gsub("[/\\]+$", ""):match("[/\\]index%.qmd$"))
    and (src_abs:gsub("[/\\]index%.qmd$", "") == project_root)

  -- Read effective configuration from metadata.
  local cfg = read_config(m)

  -- Git-based timestamp (if not forced to mtime).
  local iso_git = nil
  if not cfg.use_mtime then
    if is_root_index then
      iso_git = git_last_commit_repo(project_root)
    else
      iso_git = git_last_commit_iso(git_root, src_abs)
    end
  end

  -- Compute project-relative path for mtime state key.
  local rel_path
  if src_abs then
    local pr_pattern = "^" .. project_root:gsub("(%W)", "%%%1") .. "[/\\]+"
    rel_path = src_abs:gsub(pr_pattern, "")
    rel_path = rel_path:gsub("\\", "/")
  end

  -- mtime + state is always available as secondary source.
  local iso_mtime = iso_from_mtime(project_root, rel_path, src_abs)

  -- Select final ISO timestamp:
  --   * if use_mtime: always mtime
  --   * else: Git if available (normalized to UTC Z), else mtime
  local iso_final
  if cfg.use_mtime then
    iso_final = iso_mtime
  else
    iso_final = iso_git and iso_to_utc_z(iso_git) or iso_mtime
  end

  -- If we still have no timestamp, bail out and do not fabricate "now".
  if not iso_final then
    return m
  end

  -- Parse ISO timestamp into components (UTC).
  local y, mon, d, hh, mm = parse_iso_ymdhm(iso_final)
  if not (y and mon and d) then
    return m
  end

  -- Build human-readable date and time using language file
  local date_pattern = cfg.date_format
    or lang_info.date_format
    or "MMM DD, YYYY"

  local time_pattern = cfg.time_format
    or lang_info.time_format
    or "HH:mm"

  local months = lang_info.months or {}
  local date_human = format_date(months, y, mon, d, date_pattern) or ""

  -- Optional time component.
  local time_human = nil
  if not cfg.hide_time then
    time_human = format_time(hh, mm, time_pattern)
  end

  local str_date = date_human
  if (not cfg.hide_time) and time_human and time_human ~= "" then
    local sep = " "
    str_date = date_human .. sep .. time_human
  end

  -- Always append explicit UTC suffix.
  local tz_suffix = " UTC"
  str_date = str_date .. tz_suffix
  str_date = escape_html(str_date)

  --------------------------------------------------------
  -- Inject SEO meta tags into <head> via header-includes
  --------------------------------------------------------
  local metas = {
    pandoc.RawBlock("html",
      '<meta itemprop="dateModified" content="' .. iso_final .. '">'),
    pandoc.RawBlock("html",
      '<meta property="article:modified_time" content="' .. iso_final .. '">'),
    pandoc.RawBlock("html",
      '<meta name="dcterms.modified" content="' .. iso_final .. '">'),
  }

  local header = m["header-includes"]
  if not header then
    m["header-includes"] = pandoc.MetaList(metas)
  elseif header.t == "MetaList" then
    for _, blk in ipairs(metas) do
      table.insert(header, blk)
    end
    m["header-includes"] = header
  else
    m["header-includes"] = pandoc.MetaList({
      header,
      table.unpack(metas),
    })
  end

  --------------------------------------------------------
  -- Build GitHub history URL for the current file (optional)
  --------------------------------------------------------
  local base_repo = cfg.repo_url
  local branch    = cfg.repo_branch ~= "" and cfg.repo_branch or "main"

  if (not base_repo or base_repo == "") and git_root then
    local remote = git_remote_origin(git_root)
    base_repo = normalize_github_url(remote or "")
  end

  if base_repo and base_repo ~= "" then
    base_repo = base_repo:gsub("/+$", "")
  end

  local href = nil
  if not cfg.hide_link and base_repo and base_repo ~= "" and src_abs then
    -- Use git_root (repo root) when computing path for GitHub URL.
    local root_for_url = git_root or project_root
    local gr_pattern = "^" .. root_for_url:gsub("(%W)", "%%%1") .. "[/\\]+"
    local rel = src_abs:gsub(gr_pattern, "")
    rel = rel:gsub("\\", "/")

    if rel ~= "" then
      -- Example: https://github.com/.../commits/main/tr/index.qmd
      href = string.format("%s/commits/%s/%s", base_repo, branch, rel)
    else
      href = string.format("%s/commits/%s/", base_repo, branch)
    end
  end

  --------------------------------------------------------
  -- Localized footer HTML snippet (label + value [+ optional link])
  --------------------------------------------------------
  local label = nil
  if not cfg.hide_label then
    label = lang_info.label_updated
    label = label and escape_html(label) or nil
  end

  local html
  if not href or cfg.hide_link then
    -- No link: plain text only.
    if label then
      html = string.format(
        '<span class="date-modified">' ..
          '<span class="date-modified-label">%s</span>' ..
          '<span class="date-modified-value">%s</span>' ..
        '</span>',
        label,
        str_date
      )
    else
      html = string.format(
        '<span class="date-modified">' ..
          '<span class="date-modified-value">%s</span>' ..
        '</span>',
        str_date
      )
    end
  else
    -- With link inside the value span.
    if label then
      html = string.format(
        '<span class="date-modified">' ..
          '<span class="date-modified-label">%s</span>' ..
          '<span class="date-modified-value">' ..
            '<a href="%s" target="_blank" rel="noopener noreferrer">%s</a>' ..
          '</span>' ..
        '</span>',
        label,
        href,
        str_date
      )
    else
      html = string.format(
        '<span class="date-modified">' ..
          '<span class="date-modified-value">' ..
            '<a href="%s" target="_blank" rel="noopener noreferrer">%s</a>' ..
          '</span>' ..
        '</span>',
        href,
        str_date
      )
    end
  end

  -- Expose HTML snippet in metadata for inclusion in footers/layouts.
  m["modification-date"] = pandoc.MetaString(html)

  return m
end

-- Export as a Pandoc filter (list with a single filter table).
return {
  { Meta = Meta }
}

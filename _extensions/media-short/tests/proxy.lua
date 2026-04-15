-- tests/proxy.lua
-- Proxy bootstrap for this extension: add extension root to package.path, then load _testkit.

local function normalize_path(p)
  if not p or p == "" then return p end
  p = p:gsub("/%./", "/")
  p = p:gsub("/%.$", "")
  p = p:gsub("//+", "/")
  return p
end

local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then src = src:sub(2) end
  if not src:match("^/") then
    local cwd = os.getenv("PWD") or "."
    src = cwd .. "/" .. src
  end
  return normalize_path(src:match("^(.*)/[^/]+$") or ".")
end

local TESTS_DIR = script_dir()                  -- .../media-short/tests
local EXT_ROOT  = normalize_path(TESTS_DIR:gsub("/tests$", "")) -- .../media-short

package.path =
  TESTS_DIR .. "/?.lua;" ..
  TESTS_DIR .. "/?/init.lua;" ..
  EXT_ROOT  .. "/?.lua;" ..
  EXT_ROOT  .. "/?/init.lua;" ..
  package.path

require("_testkit")

-- Additional stubs beyond the shared testkit.
-- pandoc.RawBlock is used by media-short shortcodes to wrap HTML strings;
-- tests want to inspect that HTML directly, so we model it as a table
-- whose `.text` field is the raw HTML.
_G.pandoc.RawBlock = _G.pandoc.RawBlock or function(format, text)
  return { t = "RawBlock", format = format, text = text }
end
_G.pandoc.RawInline = _G.pandoc.RawInline or function(format, text)
  return { t = "RawInline", format = format, text = text }
end

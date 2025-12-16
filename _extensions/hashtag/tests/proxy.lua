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

local TESTS_DIR = script_dir()
local EXT_ROOT  = normalize_path(TESTS_DIR:gsub("/tests$", ""))

package.path =
  TESTS_DIR .. "/?.lua;" ..
  TESTS_DIR .. "/?/init.lua;" ..
  EXT_ROOT  .. "/?.lua;" ..
  EXT_ROOT  .. "/?/init.lua;" ..
  package.path

require("_testkit")

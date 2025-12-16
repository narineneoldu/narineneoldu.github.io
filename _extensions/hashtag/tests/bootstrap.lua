-- tests/bootstrap.lua
-- Shared test bootstrap: package.path + minimal stubs for pandoc/quarto/FORMAT.

-- Resolve extension root dir from this file location (works regardless of cwd)
local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then src = src:sub(2) end
  return src:match("^(.*)/[^/]+$") or "."
end

local TESTS_DIR = script_dir()                 -- .../_extensions/hashtag/tests
local EXT_ROOT  = (TESTS_DIR:gsub("/tests$", "")) -- .../_extensions/hashtag

-- Make requires independent of current working directory
package.path =
  EXT_ROOT .. "/tests/?.lua;" ..
  EXT_ROOT .. "/?.lua;" ..
  EXT_ROOT .. "/_hashtag/?.lua;" ..
  package.path

-- Force HTML-ish mode for deps guards
_G.FORMAT = "html"

-- Minimal quarto stub (deps.lua expects these)
_G.quarto = _G.quarto or {}
_G.quarto.doc = _G.quarto.doc or {}
_G.quarto.doc.is_format = _G.quarto.doc.is_format or function(fmt) return fmt == "html" end
_G.quarto.doc.add_html_dependency = _G.quarto.doc.add_html_dependency or function(_) end

-- Minimal pandoc stub (only what's needed by these tests)
_G.pandoc = _G.pandoc or {}
_G.pandoc.utils = _G.pandoc.utils or {}
_G.pandoc.utils.stringify = _G.pandoc.utils.stringify or function(x)
  if x == nil then return "" end
  if type(x) == "string" then return x end
  return tostring(x)
end

-- Minimal List implementation used by scan/filter code
_G.pandoc.List = _G.pandoc.List or {}
function _G.pandoc.List:new()
  local t = {}
  local mt = {
    __index = {
      insert = function(self, v) table.insert(self, v) end,
      -- Minimal walk: applies block handlers top-level only.
      walk = function(self, handlers)
        local out = _G.pandoc.List:new()
        for _, b in ipairs(self) do
          local fn = handlers and handlers[b.t]
          local replaced = fn and fn(b) or nil
          out:insert(replaced or b)
        end
        return out
      end
    }
  }
  return setmetatable(t, mt)
end

-- Also expose a dot-call constructor for convenience/compatibility
_G.pandoc.List.new = _G.pandoc.List.new or function()
  return _G.pandoc.List:new()
end

-- AST constructors used in tests
_G.pandoc.Str = _G.pandoc.Str or function(s) return { t = "Str", text = s } end
_G.pandoc.Space = _G.pandoc.Space or function() return { t = "Space" } end
_G.pandoc.Emph = _G.pandoc.Emph or function(content) return { t = "Emph", content = content } end
_G.pandoc.Strong = _G.pandoc.Strong or function(content) return { t = "Strong", content = content } end
_G.pandoc.Quoted = _G.pandoc.Quoted or function(qt, content) return { t = "Quoted", quotetype = qt, content = content } end
_G.pandoc.Span = _G.pandoc.Span or function(content, attr)
  return { t = "Span", content = content, attr = attr or { classes = {} } }
end
_G.pandoc.Link = _G.pandoc.Link or function(content, target, title, attr)
  return { t = "Link", content = content, target = target, title = title or "", attr = attr }
end

_G.pandoc.Attr = _G.pandoc.Attr or function(id, classes, attrs)
  return { identifier = id or "", classes = classes or {}, attributes = attrs or {} }
end

_G.pandoc.Para = _G.pandoc.Para or function(content) return { t = "Para", content = content } end
_G.pandoc.Plain = _G.pandoc.Plain or function(content) return { t = "Plain", content = content } end
_G.pandoc.Div = _G.pandoc.Div or function(content, attr)
  return { t = "Div", content = content, attr = attr or { classes = {} } }
end

return {
  EXT_ROOT = EXT_ROOT,
  TESTS_DIR = TESTS_DIR,
}

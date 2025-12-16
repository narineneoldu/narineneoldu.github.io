-- _testkit/bootstrap.lua
-- Shared test bootstrap: package.path + minimal stubs for pandoc/quarto/FORMAT.

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
-- Minimal pandoc.utils.stringify implementation for tests.
-- Flattens inline structures (Str/Space and common containers) into plain text.
_G.pandoc.utils.stringify = _G.pandoc.utils.stringify or function(x)
  if x == nil then return "" end
  if type(x) == "string" then return x end
  if type(x) ~= "table" then return tostring(x) end

  local out = {}
  local n = 0

  local function push(s)
    if not s or s == "" then return end
    n = n + 1
    out[n] = s
  end

  local function walk(el)
    if el == nil then return end
    if type(el) == "string" then
      push(el)
      return
    end
    if type(el) ~= "table" then
      push(tostring(el))
      return
    end

    if el.t == "Str" then
      push(el.text or "")
      return
    end

    if el.t == "Space" or el.t == "SoftBreak" or el.t == "LineBreak" then
      push(" ")
      return
    end

    -- Containers with .content (Span/Emph/Strong/Quoted/Link, etc.)
    if el.content and type(el.content) == "table" then
      for _, c in ipairs(el.content) do walk(c) end
      return
    end

    -- If called with a list of inlines directly
    for _, c in ipairs(el) do walk(c) end
  end

  walk(x)

  local s = table.concat(out, "", 1, n)
  s = s:gsub("%s+", " ")
  return s
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
  TESTKIT_DIR = TESTKIT_DIR,
  EXTENSIONS_ROOT = EXTENSIONS_ROOT,
}

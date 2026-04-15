-- tests/test_jump_shortcode.lua
-- Golden-file snapshot tests for the {{< jump >}} shortcode.
--
-- These tests lock down the exact HTML emitted by shortcode-jump.lua so that
-- future refactors of the media-short extension cannot silently break the
-- timejump anchors that are scattered throughout trial testimony pages.
--
-- If you intentionally change the emitted HTML, update the matching
-- golden/jump/*.html file in the same commit.

require("proxy")
local lu = require("luaunit")

-- Stub deps module so `require("_media_short.deps_jump")` does not try to
-- call quarto.doc.add_html_dependency during test runs.
package.preload["_media_short.deps_jump"] = function()
  return { ensure_plyr = function() end }
end

local jump_mod = require("shortcode-jump")
local jump = jump_mod.jump

------------------------------------------------------------
-- Golden-file helpers
------------------------------------------------------------

local function script_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then src = src:sub(2) end
  if not src:match("^/") then
    local cwd = os.getenv("PWD") or "."
    src = cwd .. "/" .. src
  end
  return src:match("^(.*)/[^/]+$") or "."
end

local TESTS_DIR  = script_dir()
local GOLDEN_DIR = TESTS_DIR .. "/golden/jump"

local function read_golden(name)
  local path = GOLDEN_DIR .. "/" .. name
  local f = assert(io.open(path, "r"), "missing golden file: " .. path)
  local s = f:read("*a")
  f:close()
  -- Strip a single trailing newline so tests can store files with a final
  -- newline (POSIX text-file convention) while the shortcode emits none.
  if s:sub(-1) == "\n" then s = s:sub(1, -2) end
  return s
end

local function jump_html(args, kwargs)
  -- Real shortcodes are invoked as (args, kwargs, meta, raw_args, context).
  -- None of the extra params are read by jump_shortcode, so empty tables /
  -- nil are safe here.
  local block = jump(args or {}, kwargs or {}, {}, {}, nil)
  assert(block and block.text, "jump shortcode returned no RawBlock")
  return block.text
end

------------------------------------------------------------
-- Test cases
------------------------------------------------------------

TestJumpShortcode = {}

function TestJumpShortcode:test_named_kwargs_form()
  local out = jump_html({}, {
    id    = "mindvortex",
    start = "01:23",
    text  = "Bölüm #1",
  })
  lu.assertEquals(out, read_golden("named.html"))
end

function TestJumpShortcode:test_positional_form_matches_named()
  -- Positional args are the legacy form: {{< jump mindvortex "01:23" "Bölüm #1" >}}.
  -- Output must be byte-identical to the named form to avoid surprises when
  -- mixing styles in the same document.
  local out = jump_html({ "mindvortex", "01:23", "Bölüm #1" }, {})
  lu.assertEquals(out, read_golden("named.html"))
end

function TestJumpShortcode:test_text_optional()
  -- Omitting `text` should still produce a valid anchor; label falls back
  -- to the bracketed timestamp alone.
  local out = jump_html({}, { id = "player-a", start = "10:00" })
  lu.assertEquals(out, read_golden("no_text.html"))
end

function TestJumpShortcode:test_quotes_stripped_from_args()
  -- User may write {{< jump id="p1" start="00:45" text="Buraya bak" >}} and
  -- Quarto can hand us values with or without the surrounding quotes; the
  -- shortcode strips ASCII and smart quotes from id/start (but not text).
  local out = jump_html({}, {
    id    = '"p1"',
    start = "'00:45'",
    text  = "Buraya bak",
  })
  local expected = read_golden("no_text.html")
    :gsub("player%-a", "p1")
    :gsub("10:00", "00:45")
    :gsub("%[00:45%]", "[00:45] Buraya bak")
  lu.assertEquals(out, expected)
end

function TestJumpShortcode:test_missing_id_emits_comment()
  -- Graceful failure mode: an HTML comment instead of a broken link.
  local out = jump_html({}, { start = "01:00" })
  lu.assertEquals(out, read_golden("missing_id.html"))
end

function TestJumpShortcode:test_missing_start_emits_comment()
  local out = jump_html({}, { id = "player" })
  lu.assertEquals(out, read_golden("missing_id.html"))
end

os.exit(lu.LuaUnit.run())

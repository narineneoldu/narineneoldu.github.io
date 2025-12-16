-- _testkit/init.lua
-- Unified test entrypoint: bootstrap + LuaUnit preload.

local C = {
  reset  = "\27[0m",
  yellow = "\27[33m",
  purple = "\27[35m",
  blue   = "\27[34m",
  green  = "\27[32m",
  red    = "\27[31m",
}

require("_testkit.bootstrap")

-- Make `require("luaunit")` resolve to our vendored copy if no other LuaUnit is installed.
package.preload["luaunit"] = package.preload["luaunit"] or function()
  return require("_testkit.luaunit")
end

local luaunit = require("_testkit.luaunit")

-- -----------------------------
-- Output styling configuration
-- -----------------------------

-- Return true if we should emit ANSI colors.
-- Rules:
--   - NO_COLOR disables colors (standard convention)
--   - CI disables colors (many CI logs don't render well)
--   - TERM=dumb disables colors
local function colors_enabled()
  if os.getenv("NO_COLOR") and os.getenv("NO_COLOR") ~= "" then
    return false
  end
  if os.getenv("CI") and os.getenv("CI") ~= "" then
    return false
  end
  local term = os.getenv("TERM")
  if term and term:lower() == "dumb" then
    return false
  end
  return true
end

local USE_COLOR = colors_enabled()

local C = {
  reset  = "\27[0m",
  yellow = "\27[33m",
  purple = "\27[35m",
  blue   = "\27[34m",
  green  = "\27[32m",
  red    = "\27[31m",
}

local function color(code, s)
  if not USE_COLOR then
    return s
  end
  return code .. s .. C.reset
end

-- Unicode icons (always enabled here; add env switch if you ever want)
local ICON = {
  success = ".",   -- keep your dotted progress line
  fail    = "✖",
  error   = "⚠",
  skip    = "⏭",
}

local WIDTH = {
  tests     = 3,  -- up to 999 tests
  successes = 3,
  failures  = 3,
  seconds   = 6,  -- e.g. "0.1234"
}

local function fmt_num(n, width)
  return string.format("%" .. width .. "d", tonumber(n))
end

local function fmt_float(x, width, precision)
  return string.format("%" .. width .. "." .. precision .. "f", tonumber(x))
end

-- Build a colored one-line summary.
-- Build a colored one-line summary (robust to "1 success" vs "2 successes", etc.)
local function colorized_summary(result)
  local line = luaunit.LuaUnit.statusLine(result)

  -- Colorize pieces in-place; keep any extra suffixes LuaUnit may append (skipped/non-selected)
  line = line:gsub("Ran (%d+) (%a+)", function(n, word)
    -- word is "test"/"tests" (or even "tests" for 1 due to LuaUnit formatting)
    return "  " .. color(C.purple, fmt_num(n, WIDTH.tests) .. " " .. word)
  end, 1)

  line = line:gsub("in ([%d%.]+) seconds", function(sec)
    return "in " .. color(C.blue, sec .. " seconds")
  end, 1)

  line = line:gsub("(%d+) success%w*", function(n)
    -- matches "success" or "successes"
    return color(C.green, fmt_num(n, WIDTH.successes) .. " success" .. (tonumber(n) == 1 and "" or "es"))
  end, 1)

  line = line:gsub("(%d+) failure%w*", function(n)
    -- matches "failure" or "failures"
    return color(C.red, fmt_num(n, WIDTH.failures) .. " failure" .. (tonumber(n) == 1 and "" or "s"))
  end, 1)

  line = line:gsub("(%d+) error%w*", function(n)
    -- optional: if LuaUnit includes errors
    return color(C.red, n .. " error" .. (tonumber(n) == 1 and "" or "s"))
  end, 1)

  return line
end

-- ---------------------------------------
-- Patch LuaUnit TextOutput (LuaUnit 3.4)
-- ---------------------------------------

-- In LuaUnit 3.4, the default text output class is stored at luaunit.LuaUnit.outputType
local TextOutput = luaunit.LuaUnit.outputType
if TextOutput and type(TextOutput) == "table" then
  -- Keep originals for fallback behavior if needed
  local original_endTest  = TextOutput.endTest
  local original_endSuite = TextOutput.endSuite

  -- Progress markers (non-verbose mode)
  function TextOutput:endTest(node)
    -- Only style the compact progress line; keep verbose output intact.
    if self.verbosity > luaunit.VERBOSITY_DEFAULT then
      return original_endTest(self, node)
    end

    if node:isSuccess() then
      io.stdout:write(color(C.yellow, ICON.success))
      io.stdout:flush()
      return
    end

    if node:isFailure() then
      io.stdout:write(color(C.red, ICON.fail))
      io.stdout:flush()
      return
    end

    if node:isError() then
      io.stdout:write(color(C.red, ICON.error))
      io.stdout:flush()
      return
    end

    if node:isSkipped() then
      io.stdout:write(color(C.yellow, ICON.skip))
      io.stdout:flush()
      return
    end

    -- Fallback to LuaUnit default if something unexpected happens
    return original_endTest(self, node)
  end

  -- One-line final summary with "- OK" on same line, and colored fields
  function TextOutput:endSuite()
    if self.verbosity > luaunit.VERBOSITY_DEFAULT then
      -- In verbose mode, keep default formatting (it prints headers etc.)
      return original_endSuite(self)
    end

    -- LuaUnit default prints a newline before the summary in non-verbose mode
    print()
    self:displayErroredTests()
    self:displayFailedTests()

    local summary = colorized_summary(self.result)

    local function icons_enabled()
      -- Keep unicode off in CI / dumb terminals to avoid mojibake
      if os.getenv("CI") and os.getenv("CI") ~= "" then return false end
      local term = os.getenv("TERM")
      if term and term:lower() == "dumb" then return false end
      return true
    end

    local USE_ICONS = icons_enabled()

    local ok_tag = USE_ICONS and "✓ OK" or "OK"
    local fail_tag = USE_ICONS and "✖ FAIL" or "FAIL"
    local err_tag  = USE_ICONS and "⚠ ERROR" or "ERROR"

    if self.result.notSuccessCount == 0 then
      print(summary .. " - " .. color(C.green, ok_tag))
    else
      local tag = (self.result.errorCount > 0) and err_tag or fail_tag
      print(summary .. " - " .. color(C.red, tag))
    end
  end
end

return true

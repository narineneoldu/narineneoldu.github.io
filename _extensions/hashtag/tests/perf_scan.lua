-- tests/perf_scan.lua
-- Performance sanity check (not a unit test). Run manually:
--   lua tests/perf_scan.lua

require("tests.bootstrap")

-- Force reload to avoid require cache keeping an old scan.lua in the same Lua process
package.loaded["_hashtag.scan"] = nil
package.loaded["_hashtag.utf8"] = nil

local Hs = require("tests.helpers_scan")
Hs.monkeypatch_core_for_scan()
local scan = require("_hashtag.scan")

print("scan loaded from:", debug.getinfo(scan.process_inlines, "S").source)

local function build_big_str(n_tokens)
  local parts = {}
  for i = 1, n_tokens do
    parts[#parts + 1] = "word"
    if (i % 20) == 0 then
      parts[#parts + 1] = " #Tag" .. tostring(i)
    end
    parts[#parts + 1] = " "
  end
  return table.concat(parts)
end

local cfg = Hs.cfg_span_only()
cfg.hashtag_numbers = 0

local big = build_big_str(50000) -- tune as you like
local inlines = { pandoc.Str(big) }

local t0 = os.clock()
local out = scan.process_inlines(inlines, cfg, {}, false)
local t1 = os.clock()

print(string.format("perf_scan: input_chars=%d elapsed=%.3fs output_text_chars=%d",
  #big, (t1 - t0), #(Hs.flatten_text(out))
))

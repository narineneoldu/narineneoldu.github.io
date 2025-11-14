-- ../shared/lua/init.lua

-- this file's directory (absolute or project-relative)
local this_dir = (debug.getinfo(1, "S").source:match("^@(.*/)")
                 or "./"):gsub("//+", "/")

-- Build package.path relative to this file, so it works from tr/ da çağrılsa
local paths = table.concat({
  this_dir .. "?.lua",
  this_dir .. "modules/?.lua",
  -- istersen ek güvence için bir üst klasöre de bak:
  this_dir .. "../?.lua",
  this_dir .. "../modules/?.lua",
  package.path
}, ";")

package.path = paths

-- Load modules (dosya adları underscore'lı olmalı: render_foot.lua, lastmod.lua)
local filters = {
  require("render_start_timer"),
  require("span_time"),
  require("span_phone"),
  require("hashtag_to_x"),
  require("lastmod"),
  require("span_plate"),
  require("span_amount"),
  require("span_para"),
  require("span_record_number"),
  require("abbr"),
  require("span_date"),
  require("force_link_order"),
  require("short_media"),
  require("span_unit"),
  require("render_end_timer"),
}

return filters

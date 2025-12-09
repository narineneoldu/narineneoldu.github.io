-- _extensions/media-jump/jump.lua
--
-- Usage (named args):
--   {{< jump id="mindvortex" start="01:23" text="Bölüm #1" >}}
--
-- Optional: positional usage da desteklenir:
--   {{< jump mindvortex "01:23" "Bölüm #1" >}}
--
-- Output:
--   <a href="#mindvortex&t=01:23"
--      class="timejump"
--      data-player="mindvortex"
--      data-time="01:23">[01:23] Bölüm #1</a>

local deps = require("deps-jump")


-- Simple helper for RawBlock HTML
local function raw_block(html)
  return pandoc.RawBlock("html", html)
end

local function trim(s)
  if not s then return nil end
  return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Only strip ASCII + smart quotes; keep colons etc.
local function clean_arg(s)
  if not s then return nil end
  s = pandoc.utils.stringify(s)
  s = trim(s)
  -- Remove " ' “ ” ‘ ’ characters
  s = s:gsub('[\"\'“”‘’]', '')
  return trim(s)
end

local function jump_shortcode(args, kwargs, meta, raw_args, context)
  deps.ensure_plyr()
  --------------------------------------------------------------------
  -- 1) id, start, text parametrelerini oku
  --------------------------------------------------------------------
  -- Önce named kwargs, yoksa positional'a düş
  local id =
    (kwargs["id"]    and pandoc.utils.stringify(kwargs["id"]))    or
    (args[1]         and pandoc.utils.stringify(args[1]))         or
    nil

  local start =
    (kwargs["start"] and pandoc.utils.stringify(kwargs["start"])) or
    (args[2]         and pandoc.utils.stringify(args[2]))         or
    nil

  local text =
    (kwargs["text"]  and pandoc.utils.stringify(kwargs["text"]))  or
    (args[3]         and pandoc.utils.stringify(args[3]))         or
    nil

  id    = clean_arg(id)
  start = clean_arg(start)
  text  = text and trim(pandoc.utils.stringify(text)) or nil

  if not id or id == "" or not start or start == "" then
    return raw_block("<!-- jump: missing id or start -->")
  end

  --------------------------------------------------------------------
  -- 2) Label ve href oluştur
  --------------------------------------------------------------------
  local label = "[" .. start .. "]"
  if text and text ~= "" then
    label = label .. " " .. text
  end

  local href = "#" .. id .. "&t=" .. start

  --------------------------------------------------------------------
  -- 3) Son HTML (eski yt_jump ile uyumlu)
  --------------------------------------------------------------------
  local html = string.format(
    '<a href="%s" class="timejump" data-player="%s" data-time="%s">%s</a>',
    href,
    id,
    start,
    label
  )

  -- Block shortcode olduğu için RawBlock döndürüyoruz
  return raw_block(html)
end

return {
  -- {{< jump ... >}}
  jump = jump_shortcode,
}

--[[
  _extensions/media-short/filter-audio.lua

  Implements the {{< audio ... >}} shortcode for Quarto / Pandoc documents.

  Responsibilities:
    - Render local or remote audio URLs as Plyr-compatible <audio> players.
    - Map shortcode keyword arguments (kwargs) into:
        * wrapper attributes (<div class="plyr-wrapper" ...>)
        * js-player attributes (.js-player / <audio> element)
        * inline style properties on the wrapper (width, max-width, etc.)
        * caption text (<p class="media-caption">)
        * Plyr control configuration via data-control-* attributes
    - Share the same metadata defaults mechanism as video players via
      the `plyr-defaults` YAML front matter key.
    - Support control presets (default, shorts) with:
        * built-in defaults
        * document-level metadata defaults (plyr-defaults)
        * shortcode-level overrides
    - Allow passthrough of arbitrary data-* attributes from shortcode
      to the .js-player node.
    - Ensure each audio wrapper has a stable unique ID, detecting duplicates.
    - Support extra CSS classes per player via `class="..."` on the wrapper.
    - Attach VTT subtitles / transcript tracks inferred from the audio URL
      (for local audio) or explicitly provided via the `subtitles` parameter.

  Subtitles behavior:

    - If the shortcode provides `subtitles="..."`, these entries are used
      to generate one or more <track> elements, regardless of whether the
      audio URL is local or remote. In this case, no automatic VTT detection
      is performed.

    - If `subtitles` is not provided and the audio URL points to a local
      file, the filter looks for a VTT file in the same folder whose name
      is derived from the audio filename and document language, e.g.:

        /resources/audio/foo.mp3 + lang "tr"
        -> /resources/audio/foo-tr.vtt

      If that file exists on disk, a single <track> is emitted; otherwise,
      no subtitles are added.

    - When multiple tracks are present, Plyr will expose them via the
      captions menu. The first track is also used as the value of
      data-caption-src on the <audio> element.
]]

local deps = require("_media_short.deps_core")
local plyr_common = require("_media_short.plyr_common")

local raw_block = plyr_common.raw_block
local normalize_string = plyr_common.normalize_string
local normalize_bool = plyr_common.normalize_bool
local kw = plyr_common.kw
local kw_bool = plyr_common.kw_bool
local build_attr = plyr_common.build_attr
local build_style = plyr_common.build_style
local read_meta_defaults = plyr_common.read_plyr_meta_defaults

------------------------------------------------------------
-- Low-level helpers (aligned with filter-video.lua)
------------------------------------------------------------

--- Global per-page ID registry (prevents duplicate wrapper IDs).
local used_ids = {}

--- Deduce MIME type from audio URL extension.
-- Falls back to "audio/mpeg" if no known extension is matched.
-- @param url string
-- @return string
local function deduce_mime_type(url)
  local lower = url:lower()

  if lower:match("%.mp3$") then
    return "audio/mpeg"
  end
  if lower:match("%.m4a$") then
    -- Most browsers accept audio/mp4 for M4A files
    return "audio/mp4"
  end
  if lower:match("%.wav$") then
    return "audio/wav"
  end
  if lower:match("%.ogg$") or lower:match("%.oga$") then
    return "audio/ogg"
  end

  -- Reasonable default for unknown extensions
  return "audio/mpeg"
end

--- Check whether a URL is local (project-relative) rather than remote.
-- Very simple heuristic: anything starting with http:// or https:// is
-- treated as remote.
-- @param url string
-- @return boolean
local function is_local_url(url)
  return not url:match("^https?://")
end

--- Check whether a given filesystem path exists and is readable.
-- Path is interpreted relative to the Quarto project root if available.
-- @param path string (usually something like "/resources/audio/foo-tr.vtt")
-- @return boolean
local function file_exists(path)
  -- Get project root from Quarto, fall back to current working directory
  local project_root = os.getenv("QUARTO_PROJECT_DIR") or pandoc.system.get_working_directory()
  if not project_root then
    return false
  end

  -- Normalize project_root: remove trailing slash
  project_root = project_root:gsub("[/\\]$", "")

  -- Normalize path: ensure it starts with a single "/"
  if not path:match("^/") then
    path = "/" .. path
  end

  local full_path = project_root .. path

  local f = io.open(full_path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

--- Simple string trim helper (remove leading and trailing whitespace).
-- @param s string
-- @return string
local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

------------------------------------------------------------
-- Attribute specification and control presets (audio)
------------------------------------------------------------

-- Map from shortcode kwargs to logical "buckets" and attribute names.
-- bucket = "wrapper"        -> attributes on <div class="plyr-wrapper">
-- bucket = "js"             -> attributes on .js-player / <audio>
-- bucket = "style"          -> inline style on .plyr-wrapper (width, height, ...)
-- bucket = "caption"        -> plain caption text (<p class="media-caption">)
-- bucket = "control"        -> boolean flags for Plyr controls (play, mute, ...)
-- bucket = "control-preset" -> control preset name (default/shorts)
--
-- type   = "string" | "bool"
-- default = default value (used mainly for control flags)
local ATTR_SPEC = {
  -- Wrapper / js / style / caption
  id           = { bucket = "wrapper",        attr = "id",           type = "string" },
  class        = { bucket = "wrapper",        attr = "class",        type = "string" },

  start        = { bucket = "js",             attr = "data-start",   type = "string" },
  autoplay     = { bucket = "js",             attr = "data-autoplay",type = "string" },
  cclang       = { bucket = "js",             attr = "data-cc-lang", type = "string" },

  width        = { bucket = "style",          prop = "width",        type = "string" },
  height       = { bucket = "style",          prop = "height",       type = "string" },
  ["max-width"]  = { bucket = "style",        prop = "max-width",    type = "string" },
  ["max-height"] = { bucket = "style",        prop = "max-height",   type = "string" },

  caption      = { bucket = "caption",        type = "string" },

  -- Control flags (true/false); defaults mirror video defaults.
  play         = { bucket = "control", type = "bool", default = true },
  ["play-large"] = { bucket = "control", type = "bool", default = true },
  progress     = { bucket = "control", type = "bool", default = true },
  ["current-time"] = { bucket = "control", type = "bool", default = true },
  mute         = { bucket = "control", type = "bool", default = true },
  volume       = { bucket = "control", type = "bool", default = true },
  captions     = { bucket = "control", type = "bool", default = true },
  settings     = { bucket = "control", type = "bool", default = true },
  pip          = { bucket = "control", type = "bool", default = true },
  airplay      = { bucket = "control", type = "bool", default = true },
  fullscreen   = { bucket = "control", type = "bool", default = true },

  -- Control preset selector; accepts: "default", "shorts"
  ["controls"] = { bucket = "control-preset", type = "string" },
}

--- Control presets for audio.
-- We reuse the same semantics as video:
--   - default: full UI
--   - shorts: a reduced set (e.g. no progress/settings/fullscreen)
local CONTROL_PRESETS = {
  default = {}, -- will be populated from ATTR_SPEC control defaults
  shorts = {
    progress       = false,
    settings       = false,
    fullscreen     = false,
  },
}

-- Initialize CONTROL_PRESETS.default from ATTR_SPEC control defaults.
for name, spec in pairs(ATTR_SPEC) do
  if spec.bucket == "control" then
    local def = spec.default
    if def == nil then
      def = true
    end
    CONTROL_PRESETS.default[name] = def
  end
end

------------------------------------------------------------
-- MAIN SHORTCODE IMPLEMENTATION
------------------------------------------------------------

--- Main implementation of the {{< audio ... >}} shortcode.
-- Responsibilities:
--   - Parse the audio URL.
--   - Merge defaults from:
--       * built-in defaults (CONTROL_PRESETS.default),
--       * document-level meta (plyr-defaults),
--       * shortcode-level kwargs (highest priority).
--   - Build wrapper, js, style, caption, and control configuration.
--   - Emit final HTML structure including optional VTT subtitle tracks.
local function audio_shortcode(args, kwargs, meta, raw_args, context)
  deps.ensure_plyr()

  ------------------------------------------------------------
  -- 1) URL
  ------------------------------------------------------------
  local url = args[1] and pandoc.utils.stringify(args[1]) or nil
  if not url then
    return raw_block("<!-- audio: missing URL -->")
  end

  ------------------------------------------------------------
  -- 2) Read page-level defaults from metadata
  ------------------------------------------------------------
  local meta_defaults = read_meta_defaults(meta, ATTR_SPEC)

  ------------------------------------------------------------
  -- 3) Collect wrapper/js/style/caption attributes
  --    by merging meta defaults and shortcode kwargs.
  ------------------------------------------------------------
  local wrapper_attrs = {}   -- id, class, ...
  local js_attrs      = {}   -- data-start, data-autoplay, data-cc-lang, ...
  local style_props   = {}   -- width, max-width, ...
  local caption_text  = nil  -- caption string

  for key, spec in pairs(ATTR_SPEC) do
    local bucket = spec.bucket

    if bucket == "wrapper" or bucket == "js" or bucket == "style" or bucket == "caption" then
      local from_meta = meta_defaults[key]
      local from_kw

      if spec.type == "bool" then
        from_kw = kw_bool(kwargs, key)
      else
        from_kw = kw(kwargs, key)
      end

      -- Shortcode overrides metadata; then fall back to metadata
      local value = from_kw
      if value == nil then
        value = from_meta
      end

      if value ~= nil then
        if bucket == "wrapper" and spec.attr then
          wrapper_attrs[spec.attr] = value
        elseif bucket == "js" and spec.attr then
          js_attrs[spec.attr] = value
        elseif bucket == "style" and spec.prop then
          style_props[spec.prop] = value
        elseif bucket == "caption" then
          caption_text = value
        end
      end
    end
  end

  ------------------------------------------------------------
  -- 4) Automatic ID generation + duplicate detection
  ------------------------------------------------------------
  local id = wrapper_attrs["id"]

  if not id then
    -- Derive from filename or use a time-based fallback
    id = url:match("([^/]+)%.") or ("aud" .. tostring(os.time()))
    wrapper_attrs["id"] = id
  end

  if used_ids[id] then
    error("Duplicate audio ID in this page: " .. id)
  else
    used_ids[id] = true
  end

  ------------------------------------------------------------
  -- 5) Control preset and control flags resolution
  ------------------------------------------------------------

  -- 5a) Determine controls preset name: shortcode > meta > "default"
  local preset_name
  if kwargs["controls"] ~= nil then
    preset_name = normalize_string(kwargs["controls"])
  elseif meta_defaults["controls"] ~= nil then
    preset_name = meta_defaults["controls"]
  else
    preset_name = "default"
  end

  if not preset_name or preset_name == "" then
    preset_name = "default"
  end

  local preset = CONTROL_PRESETS[preset_name]
  if not preset then
    error("Unknown controls preset for audio shortcode: " .. preset_name)
  end

  -- 5b) Start from preset flags
  local control_flags = {}
  for name, val in pairs(preset) do
    control_flags[name] = val
  end

  -- Track which control flags were explicitly set by shortcode (for warnings)
  local user_control_overrides = {}

  -- 5c) Apply meta-level overrides for individual controls
  for name, spec in pairs(ATTR_SPEC) do
    if spec.bucket == "control" then
      local v_meta = meta_defaults[name]
      if type(v_meta) == "boolean" then
        control_flags[name] = v_meta
      end
    end
  end

  -- 5d) Apply shortcode-level overrides (highest priority)
  for name, spec in pairs(ATTR_SPEC) do
    if spec.bucket == "control" then
      local v_kw = kw_bool(kwargs, name)
      if v_kw ~= nil then
        control_flags[name] = v_kw
        user_control_overrides[name] = true
      end
    end
  end

  ------------------------------------------------------------
  -- 6) Build wrapper style + ensure wrapper class
  ------------------------------------------------------------
  -- Always include base class "plyr-wrapper", plus any user-provided class.
  local base_wrapper_class = "plyr-wrapper"
  if wrapper_attrs["class"] then
    wrapper_attrs["class"] = base_wrapper_class .. " " .. wrapper_attrs["class"]
  else
    wrapper_attrs["class"] = base_wrapper_class
  end

  local style_attr   = build_style(style_props)
  local wrapper_attr = build_attr(wrapper_attrs) .. style_attr

  ------------------------------------------------------------
  -- 7) Build js-player attributes (from js_attrs + control flags)
  ------------------------------------------------------------
  local js_map = {}

  -- From ATTR_SPEC (start, autoplay, cclang, ...)
  for k, v in pairs(js_attrs) do
    js_map[k] = v
  end

  -- Control overrides as data-control-* (only when different from default)
  for name, spec in pairs(ATTR_SPEC) do
    if spec.bucket == "control" then
      local default_val = spec.default
      if default_val == nil then
        default_val = true
      end

      -- Final value after preset + meta + shortcode
      local final_val = control_flags[name]
      if final_val == nil then
        final_val = default_val
      end

      if final_val ~= default_val then
        -- Only emit attribute if net value differs from default
        local attr_name = "data-control-" .. name
        js_map[attr_name] = final_val and "true" or "false"
      else
        -- If user explicitly set the same value as default, warn
        if user_control_overrides[name] then
          io.stderr:write(
            string.format(
              "audio: parameter '%s' on id '%s' equals its default; you can omit it.\n",
              name,
              id or "unknown"
            )
          )
        end
      end
    end
  end

  -- Passthrough for any other data-* kwargs (not explicitly mapped)
  for key, val in pairs(kwargs) do
    if key:match("^data%-") and js_map[key] == nil then
      js_map[key] = pandoc.utils.stringify(val)
    end
  end

  local js_attr = build_attr(js_map)

  ------------------------------------------------------------
  -- 8) Site language
  ------------------------------------------------------------
  local site_lang = "tr"
  if meta and meta.lang then
    if meta.lang.t == "MetaString" then
      site_lang = meta.lang.text
    elseif meta.lang.t == "MetaInlines" then
      site_lang = pandoc.utils.stringify(meta.lang)
    end
  end

  ------------------------------------------------------------
  -- 9) Subtitles (manual via `subtitles` or auto for local audio)
  ------------------------------------------------------------
  -- subtitles syntax (simple version):
  --   subtitles="/subs/foo-tr.vtt,/subs/foo-en.vtt"
  --
  -- Optionally you can provide language and label:
  --   subtitles="/subs/foo-tr.vtt|tr|Türkçe,/subs/foo-en.vtt|en|English"
  --
  -- If subtitles is provided, it is used as-is (no existence checks).
  -- If not provided and URL is local, we try to auto-detect a single VTT
  -- based on the audio URL and document language.
  local tracks = {}
  local subtitles_raw = kw(kwargs, "subtitles")

  if subtitles_raw and subtitles_raw ~= "" then
    -- Manual subtitles: split by comma, then parse each entry.
    for entry in subtitles_raw:gmatch("[^,]+") do
      local part = trim(entry)
      if part ~= "" then
        local src, lang, label =
          part:match("^([^|]+)|([^|]+)|(.+)$")
          or part:match("^([^|]+)|([^|]+)$")

        if src then
          src = trim(src)
          lang = trim(lang)
          label = label and trim(label) or lang
        else
          -- Only src provided; fall back to site_lang and a generic label.
          src = part
          lang = site_lang
          label = site_lang
        end

        table.insert(tracks, {
          src   = src,
          lang  = lang,
          label = label,
        })
      end
    end
  else
    -- No manual subtitles: auto-detect a single VTT for local audio.
    if is_local_url(url) then
      -- Derive VTT URL from audio URL (same folder)
      --   /resources/audio/foo.mp3 -> /resources/audio/foo-tr.vtt
      local vtt_path = url
        :gsub("%.mp3$", "-" .. site_lang .. ".vtt")
        :gsub("%.m4a$", "-" .. site_lang .. ".vtt")
        :gsub("%.wav$", "-" .. site_lang .. ".vtt")
        :gsub("%.ogg$", "-" .. site_lang .. ".vtt")

      if file_exists(vtt_path) then
        table.insert(tracks, {
          src   = vtt_path,
          lang  = site_lang,
          label = "Transcript",
        })
      end
    end
  end

  ------------------------------------------------------------
  -- 10) Build track HTML (if any) and data-caption-src
  ------------------------------------------------------------
  local tracks_html = ""

  if #tracks > 0 then
    local track_lines = {}
    for idx, t in ipairs(tracks) do
      local src   = t.src
      local lang  = t.lang or site_lang
      local label = t.label or lang

      -- First track is marked as default.
      local default_attr = (idx == 1) and " default" or ""

      table.insert(track_lines,
        '      <track kind="subtitles"' ..
        '             label="' .. label .. '"' ..
        '             srclang="' .. lang .. '"' ..
        '             src="' .. src .. '"' ..
                     default_attr ..
        '             crossorigin="anonymous">'
      )
    end
    tracks_html = table.concat(track_lines, "\n")
  end

  ------------------------------------------------------------
  -- 11) Caption HTML
  ------------------------------------------------------------
  local caption_p =
    caption_text and ('<p class="media-caption">' .. caption_text .. '</p>') or ""

  ------------------------------------------------------------
  -- 12) Final HTML output
  ------------------------------------------------------------
  local mime_type = deduce_mime_type(url)

  local html = table.concat({
    '<div class="media-block media-block-audio">',
    '  <div' .. wrapper_attr .. '>',
    '    <audio class="js-player" controls' ..
            js_attr ..
        ' crossorigin="anonymous">',
    '      <source src="' .. url .. '" type="' .. mime_type .. '">',
    tracks_html,
    '    </audio>',
    '  </div>',
    caption_p,
    '</div>'
  }, "\n")

  return raw_block(html)
end

return {
  -- {{< audio /resources/audio/salim-1-16K.mp3 id="salim" autoplay="true" start="30" >}}
  audio = audio_shortcode,
}

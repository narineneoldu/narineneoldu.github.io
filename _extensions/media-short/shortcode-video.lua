--[[
  _extensions/media-short/filter-video.lua

  Implements the {{< video2 ... >}} shortcode for Quarto / Pandoc documents.

  Responsibilities:
    - Detect the video provider (YouTube, Vimeo, local) from a URL and emit
      Plyr-compatible HTML markup.
    - Map shortcode keyword arguments (kwargs) into:
        * wrapper attributes (<div class="plyr-wrapper" ...>)
        * js-player attributes (.js-player / <video> element)
        * inline style properties on the wrapper (width, max-width, etc.)
        * caption text (<p class="media-caption">)
        * Plyr control configuration (play, fullscreen, etc.) via data-control-*
    - Support control presets (default, shorts) with:
        * built-in defaults
        * document-level metadata defaults (plyr-defaults)
        * shortcode-level overrides
    - Allow passthrough of arbitrary data-* attributes from shortcode to the
      player node.
    - Enforce simple validation (e.g. ratio format) and surface clear error
      messages early.
    - Ensure each video wrapper has a stable unique ID, detecting duplicates.
    - Support extra CSS classes per player via `class="..."` on the wrapper.
    - Provide <noscript> fallbacks for YouTube / Vimeo when JavaScript is disabled.

  Metadata defaults example (YAML front matter):

    plyr-defaults:
      ratio: "16:9"
      controls: "shorts"
      fullscreen: false
      width: "320px"
      class: "my-default-video"
]]

local deps = require("media_short.deps_core")
local plyr_common = require("media_short.plyr_common")

------------------------------------------------------------
-- Low-level helpers
------------------------------------------------------------

local raw_block = plyr_common.raw_block
local normalize_string = plyr_common.normalize_string
local normalize_bool = plyr_common.normalize_bool
local kw = plyr_common.kw
local kw_bool = plyr_common.kw_bool
local build_attr = plyr_common.build_attr
local build_style = plyr_common.build_style
local read_meta_defaults = plyr_common.read_plyr_meta_defaults

--- Global per-page ID registry (prevents duplicate wrapper IDs).
local used_ids = {}

--- Detect provider and embed id from an input URL.
-- Supports:
--   - YouTube watch/embed/short links
--   - Vimeo standard / player URLs
-- Fallback: "local" provider with the original URL.
-- @param url string
-- @return string provider, string embed_id_or_url
local function detect_provider(url)
  url = pandoc.utils.stringify(url)

  -- YouTube variants
  local yt =
    url:match("youtube%.com/watch%?v=([^&]+)") or
    url:match("youtube%.com/shorts/([^?&]+)") or
    url:match("youtube%.com/embed/([^?&]+)") or
    url:match("youtu%.be/([^?&]+)")
  if yt then
    return "youtube", yt
  end

  -- Vimeo variants
  local vimeo =
    url:match("vimeo%.com/(%d+)") or
    url:match("player%.vimeo%.com/video/(%d+)")
  if vimeo then
    return "vimeo", vimeo
  end

  -- Otherwise treat as local video URL
  return "local", url
end

------------------------------------------------------------
-- Attribute specification and control presets
------------------------------------------------------------

-- Map from shortcode kwargs to logical "buckets" and attribute names.
-- bucket = "wrapper"        -> attributes on <div class="plyr-wrapper">
-- bucket = "js"             -> attributes on .js-player / <video>
-- bucket = "style"          -> inline style on .plyr-wrapper (width, height, ...)
-- bucket = "caption"        -> plain caption text (<p class="media-caption">)
-- bucket = "control"        -> boolean flags for Plyr controls (play, fullscreen)
-- bucket = "control-preset" -> control preset name (default/shorts)
--
-- type   = "string" | "bool"
-- default = default value (used mainly for control flags)
-- validate = optional function(v) -> raises error on invalid value
local ATTR_SPEC = {
  -- Wrapper / js / style / caption
  id           = { bucket = "wrapper",        attr = "id",           type = "string" },
  class        = { bucket = "wrapper",        attr = "class",        type = "string" },

  start        = { bucket = "js",             attr = "data-start",   type = "string" },
  autoplay     = { bucket = "js",             attr = "data-autoplay",type = "string" },
  cclang       = { bucket = "js",             attr = "data-cc-lang", type = "string" },
  ratio        = {
    bucket   = "js",
    attr     = "data-ratio",
    type     = "string",
    -- Simple validation: expect "W:H" or "W/H" with integer parts
    validate = function(v)
      if not v:match("^%d+[:/]%d+$") then
        error(
          "Invalid ratio '" .. v ..
          "' for video2 shortcode. Expected format like '16:9' or '9:16'.")
      end
    end
  },

  width        = { bucket = "style",          prop = "width",        type = "string" },
  height       = { bucket = "style",          prop = "height",       type = "string" },
  ["max-width"]  = { bucket = "style",        prop = "max-width",    type = "string" },
  ["max-height"] = { bucket = "style",        prop = "max-height",   type = "string" },

  caption      = { bucket = "caption",        type = "string" },

  -- Control flags (true/false); defaults correspond to Plyr's full UI.
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

--- Control presets. These are high-level combinations of control flags.
-- Shortcode/meta can:
--   - pick a preset (controls= "shorts"),
--   - then override individual flags (fullscreen="false", etc.).
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
-- NOSCRIPT fallback builder (YouTube/Vimeo)
------------------------------------------------------------

--- Build <noscript> fallback HTML for YouTube / Vimeo players.
-- @param provider string
-- @param embed_id string
-- @return string
local function build_noscript(provider, embed_id)
  if provider == "youtube" then
    local thumb = "https://img.youtube.com/vi/" .. embed_id .. "/hqdefault.jpg"
    local href  = "https://www.youtube.com/watch?v=" .. embed_id
    return table.concat({
      '<noscript>',
      ' <div class="plyr__video-wrapper plyr__video-embed">',
      '   <a class="noscript-thumb" href="' .. href .. '" target="_blank" rel="noopener">',
      '     <img src="' .. thumb .. '" alt="YouTube video thumbnail">',
      '     <span class="noscript-overlay">YouTube\'da izlemek için tıklayın</span>',
      '   </a>',
      ' </div>',
      '</noscript>'
    }, "\n")
  end

  if provider == "vimeo" then
    return table.concat({
      '<noscript>',
      '<p>JavaScript kapalı olduğu için gömülü Vimeo oynatıcısı kullanılamıyor.</p>',
      '</noscript>'
    }, "\n")
  end

  return ""
end

------------------------------------------------------------
-- MAIN SHORTCODE IMPLEMENTATION
------------------------------------------------------------

--- Main implementation of the {{< video2 ... >}} shortcode.
-- Responsibilities:
--   - Parse URL and detect provider.
--   - Merge defaults from:
--       * built-in defaults (CONTROL_PRESETS.default),
--       * document-level meta (plyr-defaults),
--       * shortcode-level kwargs (highest priority).
--   - Build wrapper, js, style, caption, and control configuration.
--   - Emit final HTML structure including noscript fallback when needed.
local function video2_shortcode(args, kwargs, meta, raw_args, context)
  deps.ensure_plyr()

  ------------------------------------------------------------
  -- 1) URL and provider detection
  ------------------------------------------------------------
  local url = args[1] and pandoc.utils.stringify(args[1])
  if not url then
    return raw_block("<!-- video2: missing URL -->")
  end

  local provider, embed_id = detect_provider(url)

  ------------------------------------------------------------
  -- 2) Read page-level defaults from metadata
  ------------------------------------------------------------
  local meta_defaults = read_meta_defaults(meta, ATTR_SPEC)

  ------------------------------------------------------------
  -- 3) Collect wrapper/js/style/caption attributes
  --    by merging meta defaults and shortcode kwargs.
  ------------------------------------------------------------
  local wrapper_attrs = {}   -- id, class, ...
  local js_attrs      = {}   -- data-start, data-autoplay, data-cc-lang, data-ratio, ...
  local style_props   = {}   -- width, max-width, ...
  local caption_text  = nil  -- caption string

  for key, spec in pairs(ATTR_SPEC) do
    local bucket = spec.bucket

    -- skip control and control-preset here; handled separately later
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

      -- Run validation if defined
      if value ~= nil and spec.validate then
        spec.validate(value)
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
    if provider == "youtube" or provider == "vimeo" then
      id = embed_id
    else
      -- Derive from filename or use a time-based fallback
      id = url:match("([^/]+)%.") or ("vid" .. tostring(os.time()))
    end
    wrapper_attrs["id"] = id
  end

  if used_ids[id] then
    error("Duplicate video ID in this page: " .. id)
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
    error("Unknown controls preset for video2 shortcode: " .. preset_name)
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

  local style_attr = build_style(style_props)
  local wrapper_attr = build_attr(wrapper_attrs) .. style_attr

  ------------------------------------------------------------
  -- 7) Build js-player attributes (from js_attrs + provider + control flags)
  ------------------------------------------------------------
  local js_map = {}

  -- From ATTR_SPEC (start, autoplay, cclang, ratio, ...)
  for k, v in pairs(js_attrs) do
    js_map[k] = v
  end

  -- Provider-derived attributes
  if provider ~= "local" then
    js_map["data-plyr-provider"] = provider
    js_map["data-plyr-embed-id"] = embed_id
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
              "video2: parameter '%s' on id '%s' equals its default; you can omit it.\n",
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
  -- 8) Caption HTML
  ------------------------------------------------------------
  local caption_p =
    caption_text and ('<p class="media-caption">' .. caption_text .. '</p>') or ""

  ------------------------------------------------------------
  -- 9) Provider-specific noscript
  ------------------------------------------------------------
  local noscript_html = build_noscript(provider, embed_id)

  ------------------------------------------------------------
  -- 10) Final HTML output
  ------------------------------------------------------------
  local html

  if provider == "local" then
    -- Local <video> source
    html = table.concat({
      '<div class="media-block media-block-video">',
      '  <div' .. wrapper_attr .. '>',
      '    <video class="js-player" controls playsinline' .. js_attr .. '>',
      '      <source src="' .. url .. '" type="video/mp4">',
      '    </video>',
      '  </div>',
      caption_p,
      '</div>'
    }, "\n")
  else
    -- YouTube / Vimeo (js-player div + noscript fallback)
    html = table.concat({
      '<div class="media-block media-block-video">',
      '  <div' .. wrapper_attr .. '>',
           noscript_html,
      '    <div class="js-player"' .. js_attr .. '></div>',
      '  </div>',
      caption_p,
      '</div>'
    }, "\n")
  end

  return raw_block(html)
end

return {
  video2 = video2_shortcode,
}

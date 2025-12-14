-- filter.lua
-- Automatic hashtag conversion

local core = require("_hashtag.core")

------------------------------------------------------------
-- Inline processor
------------------------------------------------------------

local function process_inlines(inlines, cfg)
  local out = pandoc.List:new()
  local provider = cfg.auto_provider
  local attr = cfg.linkify and core.hashtag_link_attr(provider, cfg)
                       or core.hashtag_span_attr(provider, cfg)

  for _, el in ipairs(inlines) do
    -- Skip code and links entirely
    if el.t == "Link" or el.t == "Code" or el.t == "CodeSpan" then
      out:insert(el)

    elseif el.t == "Str" then
      local text = el.text or ""

      -- Fast path: no hashtag
      if not text:find("#", 1, true) then
        out:insert(el)
      else
        local i = 1
        while i <= #text do
          -- Find next hashtag occurrence with captures:
          -- 1) full: "#Tag"
          -- 2) body: "Tag"
          local s, e, full, body = text:find(core.HASHTAG_PATTERN, i)

          if not s then
            -- No more hashtags; append tail and stop
            out:insert(pandoc.Str(text:sub(i)))
            break
          end

          -- Append prefix before hashtag
          if s > i then
            out:insert(pandoc.Str(text:sub(i, s - 1)))
          end

          -- Handle numeric tags (#2 etc.)
          if core.is_numeric_tag(body) then
            out:insert(pandoc.Str(full))
          else
            if cfg.linkify then
              local url = core.build_url(cfg, provider, body)
              if url then
                out:insert(pandoc.Link({ pandoc.Str(full) }, url, "", attr))
              else
                out:insert(pandoc.Str(full))
              end
            else
              -- Span: same classes, but no rel/target
              out:insert(pandoc.Span({ pandoc.Str(full) }, attr))
            end
          end

          i = e + 1
        end
      end

    elseif el.t == "Span" then
      out:insert(pandoc.Span(process_inlines(el.content, cfg), el.attr))

    elseif el.t == "Emph" then
      out:insert(pandoc.Emph(process_inlines(el.content, cfg)))

    elseif el.t == "Strong" then
      out:insert(pandoc.Strong(process_inlines(el.content, cfg)))

    elseif el.t == "Quoted" then
      out:insert(pandoc.Quoted(el.quotetype, process_inlines(el.content, cfg)))

    else
      out:insert(el)
    end
  end

  return out
end

------------------------------------------------------------
-- Block handler
------------------------------------------------------------

local function handle_block(block, cfg)
  if block.t == "Para" then
    return pandoc.Para(process_inlines(block.content, cfg))
  elseif block.t == "Plain" then
    return pandoc.Plain(process_inlines(block.content, cfg))
  end
  return nil
end

------------------------------------------------------------
-- Pandoc entry point (compatible traversal)
------------------------------------------------------------

function Pandoc(doc)
  local cfg = core.read_config(doc.meta)
  core._cfg_cache = cfg

  -- Single switch: auto_provider
  if not cfg.auto_provider or cfg.auto_provider == "" or cfg.auto_provider == false then
    return doc
  end

  -- Walk blocks using List:walk (works broadly in Quarto/Pandoc Lua)
  doc.blocks = doc.blocks:walk({
    Para  = function(b) return handle_block(b, cfg) end,
    Plain = function(b) return handle_block(b, cfg) end,
  })

  return doc
end

return {
  { Pandoc = Pandoc }
}

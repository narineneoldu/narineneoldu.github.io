# hashtag (Quarto Extension)

A small Quarto extension that renders hashtags as either links or spans, with:

- **Shortcodes** for explicit hashtag rendering (provider-aware)
- An **optional auto-scan filter** that converts `#tags` found in plain text
- A **provider registry** (X, Mastodon, Bluesky, Instagram, etc.) with user overrides
- **Deterministic** HTML attributes and safe URL encoding for non-ASCII tags
- **Numeric hashtag policy** for auto-scan (e.g., prevent `#2025` unless allowed)

## Install

Install this extension into your Quarto project:

```bash
quarto install extension user/hashtag
```

Then enable it in your project (typically in `_quarto.yml`) under
`filters` for `auto-scan` feature. A common setup is:

```yaml
filters:
  - hashtag
```

Note: The extension adds HTML dependencies only for HTML outputs (html/html5/revealjs). The filter also no-ops for non-HTML formats.

---

## Quick Start

### 1) Use shortcodes (explicit rendering)

These always honor `hashtag.linkify` and do not restrict numeric hashtags.

```md
{{< htag "OpenScience" >}}               <!-- uses default provider -->
{{< htag "mastodon" "OpenScience" >}}    <!-- explicit provider -->
{{< x "OpenScience" >}}                  <!-- provider alias -->
{{< bsky "OpenScience" >}}
```

### 2) Enable auto-scan (implicit rendering)

Auto-scan converts hashtags inside normal text (e.g., `#OpenScience`) when enabled:

```yaml
hashtag:
  auto-scan: true
```

Auto-scan respects:

- `skip-classes` (to opt-out in specific Div/Span containers)
- `hashtag-numbers` numeric policy (e.g., block `#2025` by default)

---

## Configuration (Metadata)

Put this in `_quarto.yml` (or document YAML) and adjust as needed.

```yaml
hashtag:
  # Core behavior
  auto-scan: false                     # Enable/disable automatic hashtag conversion via filter
  linkify: true                        # Render hashtags as links (true) or spans (false)
  default-provider: x                  # Default provider for both filter and shortcodes
  target: "_blank"                     # Link target; set to null/false to disable
  title: true                          # Emit data-title attribute with provider display name
  rel: "noopener noreferrer nofollow"  # rel attribute for generated links

  # Pattern used by the auto-scan filter
  # Must capture:
  #   (1) the full token including '#'
  #   (2) the body excluding '#'
  pattern: "%f[^%wçğıİöşüÇĞİÖŞÜ_](#([%wçğıİöşüÇĞİÖŞÜ_]+))"

  # Skip auto-scan inside elements carrying these CSS classes
  skip-classes: ["no-hashtag"]

  # Numeric policy (filter only):
  # 0 => never auto-link numeric-only hashtags (#2025)
  # 1 => allow any numeric length (>= 1)
  # n => allow numeric-only hashtags with length >= n
  hashtag-numbers: 0

  # Icons (HTML only): enables the "hashtag-bi" dependency (css/hashtag-bi.css)
  icons: true

  # Provider registry (keep defaults as-is, or override only what you need)
  providers:
    x:
      name: "X Social"
      url: "https://x.com/search?q=%23{tag}&src=typed_query&f=live"
    mastodon:
      name: "Mastodon"
      url: "https://mastodon.social/tags/{tag}"
    bsky:
      name: "Bluesky"
      url: "https://bsky.app/search?q=%23{tag}"
    instagram:
      name: "Instagram"
      url: "https://www.instagram.com/explore/tags/{tag}/"
    threads:
      name: "Threads"
      url: "https://www.threads.net/tag/{tag}"
    linkedin:
      name: "LinkedIn"
      url: "https://www.linkedin.com/feed/hashtag/{tag}"
    tiktok:
      name: "TikTok"
      url: "https://www.tiktok.com/tag/{tag}"
    youtube:
      name: "YouTube"
      url: "https://www.youtube.com/hashtag/{tag}"
    tumblr:
      name: "Tumblr"
      url: "https://www.tumblr.com/tagged/{tag}"
    reddit:
      name: "Reddit (search)"
      url: "https://www.reddit.com/search/?q=%23{tag}"
```

### Notes on `pattern`

- The pattern is used **only by auto-scan** (the filter).
- It must return two captures:
  1) `full`: the full match including the `#` (e.g., `#OpenScience`)
  2) `body`: the body without `#` (e.g., `OpenScience`)
- The default uses a Lua **frontier pattern** (`%f[...]`) to avoid matching in the middle of a word.

---

## Shortcodes

### Generic shortcode: `htag`

```md
{{< htag "OpenScience" >}}            <!-- uses default-provider -->
{{< htag "x" "OpenScience" >}}        <!-- provider explicitly -->
{{< htag "mastodon" "OpenScience" >}}
```

### Provider aliases

Each provider below can be called directly as a shortcode:

```md
{{< x "OpenScience" >}}
{{< mastodon "OpenScience" >}}
{{< bsky "OpenScience" >}}
{{< instagram "OpenScience" >}}
{{< threads "OpenScience" >}}
{{< linkedin "OpenScience" >}}
{{< tiktok "OpenScience" >}}
{{< youtube "OpenScience" >}}
{{< tumblr "OpenScience" >}}
{{< reddit "OpenScience" >}}
```

---

## Auto-scan Filter

When `hashtag.auto-scan: true`, the filter:

- Scans inline `Str` nodes for matches of `hashtag.pattern`
- Converts matches into either:
  - `Link` nodes (when `linkify: true`)
  - `Span` nodes (when `linkify: false`)
- Avoids processing inside:
  - existing `Link`
  - `Code` and `CodeSpan`
- Supports opt-out regions using `skip-classes`
- Runs only for HTML-ish formats (e.g., `html`, `html5`, `revealjs`)

### Skipping regions

Example: disable auto-scan inside a Div:

```md
::: {.no-hashtag}
This will NOT be auto-converted: #OpenScience
:::
```

(Ensure `skip-classes` includes `no-hashtag`.)

### Numeric hashtags (filter only)

By default, auto-scan does **not** convert purely numeric hashtags such as `#2025`.

To allow numeric hashtags of length >= 4:

```yaml
hashtag:
  auto-scan: true
  hashtag-numbers: 4
```

- `hashtag-numbers: 0` => never auto-link numeric-only tags
- `hashtag-numbers: 1` => allow `#1`, `#2025`, etc.
- `hashtag-numbers: n` => allow only if numeric length >= n

Shortcodes are **not** restricted by this policy.

---

## Adding a New Provider

You can add a provider by extending `hashtag.providers` in metadata. Each provider must provide:

- `name`: display label (used for `data-title` when enabled)
- `url`: template containing `{tag}` (will be URL-encoded and substituted)

Example: add a provider named `example`:

```yaml
hashtag:
  providers:
    example:
      name: "Example Social"
      url: "https://example.com/search?tag=%23{tag}"
```

### Make the new provider the default

```yaml
hashtag:
  default-provider: example
  providers:
    example:
      name: "Example Social"
      url: "https://example.com/search?tag=%23{tag}"
```

### Use the new provider via shortcode

You can always call it via the generic shortcode:

```md
{{< htag "example" "OpenScience" >}}
```

Provider alias shortcodes (e.g., `{{< x "Tag" >}}`) are implemented explicitly in `shortcode.lua`.
To get `{{< example "Tag" >}}` as an alias, add a matching Lua function in `shortcode.lua`:

```lua
--[[ Alias shortcode for provider "example". ]]
function example(args, kwargs, meta)
  return render_hashtag(args, meta, "example")
end
```

---

## Behavior and Safety

- URL encoding is applied to `{tag}` substitutions, so non-ASCII tags are safe in `href`.
- Dependencies are added only in Quarto HTML context:
  - `css/hashtag.css` (base)
  - `css/hashtag-bi.css` (when `icons: true`)

---

## License

Add your license here (e.g., MIT).

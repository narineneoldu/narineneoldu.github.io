
# hashtag (Quarto Extension)

A Quarto extension that renders hashtags as either links or spans, with:

- **Shortcodes** for explicit hashtag rendering (provider-aware)
- An **optional auto-scan filter** that converts `#tags` found in plain text
- A **provider registry** (X, Mastodon, Bluesky, Instagram, etc.) with user overrides
- **Deterministic** HTML attributes and safe URL encoding for non-ASCII tags
- **Fine-grained numeric hashtag control** for auto-scan (e.g., block `#2025` while allowing `#23Ekim`)

---

## Install

Install this extension into your Quarto project:

```bash
quarto install extension user/hashtag
```

Enable the filter (required for auto-scan):

```yaml
filters:
  - hashtag
```

> The extension injects HTML dependencies **only** for HTML outputs
> (`html`, `html5`, `revealjs`). The filter is a no-op for non-HTML formats.

---

## Quick Start

### 1) Shortcodes (explicit rendering)

Shortcodes always render hashtags and are **not affected** by numeric rules.

```md
{{< htag "OpenScience" >}}               <!-- uses default provider -->
{{< htag "mastodon" "OpenScience" >}}    <!-- explicit provider -->
{{< x "OpenScience" >}}                  <!-- provider alias -->
{{< bsky "OpenScience" >}}
```

---

### 2) Auto-scan (implicit rendering)

Enable auto-scan to convert hashtags found in normal text:

```yaml
hashtag:
  auto-scan: true
```

Auto-scan respects:

- `skip-classes`
- numeric-only hashtag rules (`hashtag-numbers`)
- word-boundary logic (see **Word Character Model** below)

---

## Configuration (Metadata)

Place this in `_quarto.yml` or document-level YAML.

```yaml
hashtag:
  # Core behavior
  auto-scan: false                     # Enable/disable auto-scan filter
  linkify: true                        # Render hashtags as links (true) or spans (false)
  default-provider: x                  # Default provider for filter and shortcodes
  target: "_blank"                     # Link target (null/false disables)
  title: true                          # Emit data-title attribute with provider name
  rel: "noopener noreferrer nofollow"  # rel attribute for generated links

  # --- Word character model (recommended API) ---
  #
  # Defines which characters are considered part of a hashtag body.
  # This is the ONLY value most users need to customize.
  #
  # Default:
  #   %w  -> ASCII letters and digits
  #   plus Turkish characters
  #
  word-chars: "%wçğıİöşüÇĞİÖŞÜ_"

  # --- Advanced pattern overrides (optional) ---
  #
  # If provided, these override word-chars entirely.
  #
  # raw-pattern:
  #   Full Lua pattern used by the auto-scan filter.
  #   Must capture:
  #     (1) full token including '#'
  #     (2) body without '#'
  #
  # raw-boundary-pattern:
  #   Single-character Lua pattern used for word-boundary checks.
  #
  # raw-pattern: "(#([%w_]+))"
  # raw-boundary-pattern: "^[%w_]$"

  # Skip auto-scan inside elements carrying these CSS classes
  skip-classes: ["no-hashtag"]

  # Numeric-only hashtag policy (filter only):
  #
  # Applies ONLY to hashtags whose body is digits only.
  #
  # Examples:
  #   #2025        -> numeric-only (subject to this policy)
  #   #23Ekim      -> NOT numeric-only (always allowed)
  #   #1Eylülde... -> NOT numeric-only (always allowed)
  #
  # 0 => never auto-link numeric-only hashtags
  # 1 => allow all numeric-only hashtags
  # n => allow numeric-only hashtags with length >= n
  #
  hashtag-numbers: 0

  # Icons (HTML only)
  icons: true

  # Provider registry (defaults can be overridden selectively)
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

---

## Word Character Model

The auto-scan filter is built around a **word character model**.

By default:

- Hashtags **do not** match inside words (`abc#Tag` is ignored)
- Hashtags **do** match:
  - at the beginning of a line
  - after punctuation (`(#Tag)`, `…#Tag`)

The model is driven by:

```yaml
word-chars: "%wçğıİöşüÇĞİÖŞÜ_"
```

This single definition is used to **derive both**:

- the hashtag matching pattern
- the boundary checks that prevent mid-word matches

### When to use advanced overrides

Use `raw-pattern` and `raw-boundary-pattern` **only if**:

- you need a fundamentally different hashtag grammar
- you understand Lua pattern semantics

For most use cases, `word-chars` is sufficient and recommended.

---

## Auto-scan Filter Behavior

When `hashtag.auto-scan: true`, the filter:

- Scans inline `Str` nodes only
- Converts matches into:
  - `Link` nodes (`linkify: true`)
  - `Span` nodes (`linkify: false`)
- Never processes:
  - existing `Link`
  - `Code` or `CodeSpan`
- Respects opt-out regions via `skip-classes`
- Runs only for HTML-like formats

### Skipping regions

```md
::: {.no-hashtag}
This will NOT be auto-converted: #OpenScience
:::
```

---

## Numeric Hashtag Rules

Numeric rules apply **only** to numeric-only bodies:

| Hashtag | Auto-scan |
|--------|-----------|
| `#2025` | ❌ (default) |
| `#23Ekim` | ✅ |
| `#1EylüldeYenikapı` | ✅ |

Shortcodes always bypass numeric restrictions.

---

## Adding a Provider

Add providers via metadata:

```yaml
hashtag:
  providers:
    example:
      name: "Example Social"
      url: "https://example.com/search?tag=%23{tag}"
```

Make it default:

```yaml
hashtag:
  default-provider: example
```

Use via shortcode:

```md
{{< htag "example" "OpenScience" >}}
```

---

## Behavior and Safety

- `{tag}` is URL-encoded before substitution
- HTML dependencies are injected only when needed:
  - `css/hashtag.css`
  - `css/hashtag-bi.css` (when `icons: true`)

---

## License

Add your license here (e.g., MIT).

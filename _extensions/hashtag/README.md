# Hashtag (Quarto Extension)

A Quarto extension that renders `#hashtags` as provider links (default) or styled spans. It supports:

- **Auto-scan**: converts hashtags in normal prose automatically (HTML outputs only).
- **Shortcodes**: explicit hashtag rendering (independent of auto-scan).
- Provider registry with per-project overrides (X, Mastodon, Bluesky, Instagram, etc.).
- Numeric hashtag policy for auto-scan (e.g., skip `#2` / allow `#2025`).

The auto-scan logic is intentionally conservative: it uses explicit start/stop rules and skips URL-like contexts to reduce false positives.

---

## Install

From your Quarto project directory:

```bash
quarto install extension user/hashtag
```

---

## Enable in `_quarto.yml`

Add the filter:

```yaml
filters:
  - hashtag
```

Shortcodes ship with the extension and become available after installation.

---

## Configuration

Configure the extension under a `hashtag:` block either:

- **Project-wide**: `_quarto.yml`
- **Per document**: YAML front matter in a `.qmd`

Quarto project defaults may also arrive under `metadata:`; this extension checks both.

### Example configuration

```yaml
hashtag:
  auto-scan: true
  linkify: true
  default-provider: x
  target: _blank
  rel: "noopener noreferrer nofollow"
  title: true
  icons: true

  hashtag-numbers: 4
  skip-classes:
    - no-hashtag
    - raw

  providers:
    x:
      name: "X Social"
      url: "https://x.com/search?q=%23{tag}&src=typed_query&f=live"
    mastodon:
      url: "https://mastodon.social/tags/{tag}"
```

### Settings reference

#### `auto-scan` (boolean, default: `false`)
When `true`, the Pandoc filter traverses blocks (Para/Plain/Div) and converts matching hashtags found in inline `Str` nodes.

- Runs **only** for HTML-like formats (`html`, `html5`, `revealjs`, etc.).
- Does nothing for PDF/Docx/LaTeX.

#### `linkify` (boolean, default: `true`)
Controls how hashtags render in both auto-scan and shortcodes:

- `true`: render as links (`<a>`)
- `false`: render as spans (`<span>`)

#### `default-provider` (string, default: `x`)
The provider key used when none is explicitly specified.

This affects:
- **Auto-scan**: detected hashtags link to `default-provider`.
- **Default shortcode**: `{{< htag "TagName" >}}` uses `default-provider`.

If `default-provider` does not exist in the provider registry, the extension fails safely:
- auto-scan outputs plain text `#Tag`
- shortcodes output plain text `#Tag`
- a warning is written to stderr

#### `target` (string or disabled, default: `_blank`)
The link `target` attribute. Can be disabled via Quarto’s disabled-signal (implementation depends on `_hashtag.meta`).

#### `rel` (string or disabled, default: `noopener noreferrer nofollow`)
The link `rel` attribute. Can be disabled via Quarto’s disabled-signal.

#### `title` (boolean, default: `true`)
If enabled, the provider display name is exposed as a `data-title` attribute using the provider registry’s `name`.

#### `icons` (boolean, default: `true`)
If enabled, the extension registers its icon-related HTML dependency (via `_hashtag.deps.ensure_html_bi_dependency()`).

#### `hashtag-numbers` (number, default: `0`)
Numeric-only hashtag policy for **auto-scan**:

- `0`: never auto-link numeric-only tags
- `N > 0`: auto-link numeric-only tags only when digit-count is at least `N`

Example: `hashtag-numbers: 4` links `#2025`, but not `#2` or `#99`.

Shortcodes do **not** apply numeric restrictions (explicit is assumed intentional).

#### `skip-classes` (list of strings, default: `[]`)
Disables auto-scan inside any Div/Span that carries any of these classes.

#### `providers` (map)
Override or extend providers. Each provider supports:

- `name`: display name (used when `title: true`)
- `url`: template URL containing `{tag}`

`{tag}` is replaced with the URL-encoded tag value.

---

## Usage

### Auto-scan

Enable:

```yaml
hashtag:
  auto-scan: true
```

Then write hashtags normally:

```markdown
This converts: #OpenScience
This stays plain text by default: #2
```

Auto-scan matching summary:

- A hashtag starts at `#` only if the previous character is:
  - start-of-string / start-of-inline, or
  - a “start boundary” (space, punctuation, quotes, brackets, etc.)
- The body continues until a “stop character” (space, punctuation, quotes, `<`, `>`, `|`, etc.).
- URL-like contexts are skipped (simple heuristics look for `://` or `www.` shortly before the `#`).

### Shortcodes

Shortcodes honor `linkify` but ignore numeric restrictions.

#### Generic shortcode: `htag`

Default-provider form:

```markdown
{{< htag "OpenScience" >}}
```

Explicit provider form:

```markdown
{{< htag "x" "OpenScience" >}}
{{< htag "mastodon" "OpenScience" >}}
```

#### Provider alias shortcodes

```markdown
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

## Disabling auto-scan in a section

Wrap content in a Div/Span with a skip class:

```markdown
::: {.no-hashtag}
No auto-scan here: #RawText
:::
```

---

## Output HTML

When `linkify: true`, hashtags render as `<a>` with deterministic attributes:

- `class="hashtag hashtag-provider hashtag-<provider>"`
- `data-provider="<provider>"`
- `data-title="<provider name>"` (when `title: true`)
- `target="..."` and `rel="..."` (when configured)

When `linkify: false`, hashtags render as `<span>` with the same class/data attributes, but without `href`.

---

## Default provider registry

Shipped defaults (can be overridden in `hashtag.providers`):

- `x`
- `mastodon`
- `bsky`
- `instagram`
- `threads`
- `linkedin`
- `tiktok`
- `youtube`
- `tumblr`
- `reddit`

---

## Troubleshooting

- Hashtags are not converting:
  - Confirm `hashtag.auto-scan: true`
  - Confirm HTML output
  - Check skip-classes on parent Div/Span

- `#` inside a URL is being converted:
  - Auto-scan intentionally avoids URL-like contexts; if you have an edge case, add a skip class around that region.

- Default provider warnings:
  - Ensure `default-provider` matches a registry key (normalized to lowercase slug form).

---

## License

Add your license details here.

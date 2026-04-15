---
last-verified: 2026-04-16
verified-against-commits: 4db3ec3..3175ec3
scope: local Quarto extensions under _extensions/, purpose and gotchas
---

> **This document is an architectural overview, not a source of truth.**
> Each extension has its own README inside `_extensions/<name>/` where
> applicable. When this file disagrees with the code or the extension
> README, the code wins.

# Local Extensions

Four custom Quarto extensions live under `_extensions/`, plus a shared
test harness. They are not published to the Quarto extension registry;
they are vendored in-repo so edits here ship with the site.

| Extension      | Size       | Purpose                                          | Tests          | Risk  |
| -------------- | ---------- | ------------------------------------------------ | -------------- | ----- |
| `header-slug`  | ~265 lines | Turkish-aware slug generator for heading IDs     | 9+ cases       | Low   |
| `hashtag`      | ~1100 lines| Auto-scan and shortcode for social-media hashtags| 17 files + perf guard | Medium (high coverage mitigates complexity) |
| `date-modified`| ~800 lines | Git-derived last-modified timestamps + metadata  | 13 cases (new) | Medium |
| `media-short`  | ~1100 lines| Plyr-based `audio` / `video2` / `jump` shortcodes| 29 cases (new, partial) | High (audio + video2 uncovered) |
| `_testkit`     | ~3 files   | Shared luaunit harness                           | N/A            | N/A   |

All test runners live at `_extensions/<name>/run_tests.sh` and can be
executed standalone from any directory. They invoke `lua test_*.lua`
directly using the shared `_testkit` via a symlink at
`_extensions/<name>/tests/_testkit`.

## `header-slug`

**What.** A Pandoc Lua filter (`header_slug.lua`) that intercepts
`Header` AST nodes and rewrites the `identifier` field using a
language-aware folding function.

**Why custom.** Pandoc's built-in slug generator produces wrong
results for Turkish: `İstanbul` → `stanbul` (the dotted I is stripped
instead of folded to `i`). This is a deal-breaker for a
Turkish-language site where half the headings are Turkish place
names or proper nouns.

**How.** A large `fold` table maps Latin diacritics, Greek, Cyrillic
letters, and ligatures (`ß` → `ss`, `æ` → `ae`) to ASCII. A custom
UTF-8 decoder (`utf8_next`) walks the header text one codepoint at a
time so multi-byte sequences are handled correctly. Characters that
are not in the fold table are kept as-is, so Chinese, Japanese, and
Arabic headings produce readable URL-encoded slugs.

**Gotchas.**

- **Turkish override for `I` and `ı`.** In Turkish, `I` lowercases to
  `ı` (dotless i), not `i`. The fold table hard-codes `I → i` so that
  English words embedded in Turkish headings still slug consistently.
  This is a conscious compromise: a Turkish-only site would use
  `I → ı`, but the single global rule is correct most of the time.
- **Non-Latin scripts stay in the slug.** A heading `"عنوان عربي"`
  produces a URL-encoded slug containing Arabic characters. Looks
  ugly in logs but is deterministic and linkable.
- **`used_ids` is reset per document** via the `Pandoc` entry point.
  A heading `"Giriş"` in two different files produces the same base
  slug (`giris`). Duplicate handling only suffixes within a single
  document. This is the expected Pandoc-compatible behavior.

## `hashtag`

**What.** Two contribution points:

1. **Auto-scan filter** (`filter.lua`). When `hashtag.auto-scan: true`
   in metadata, every `#tag` substring in a Para or Plain block is
   replaced by a link to a configured social-media provider.
2. **Explicit shortcodes** (`shortcode.lua`). `{{< htag "Tag" >}}`,
   `{{< x "Tag" >}}`, `{{< bsky "Tag" >}}`, plus aliases for nine
   other providers.

**Why custom.** Quarto has no native hashtag handling. Manually writing
`[#tag](https://x.com/search?q=%23tag)` every time would be tedious and
fragile.

**Architecture.** This is the most modular extension in the repo:

```
_extensions/hashtag/
├── filter.lua          # Format gate (HTML only), block walker, Div propagation
├── shortcode.lua       # htag + 10 provider aliases
├── _hashtag/
│   ├── core.lua        # Facade that ties the submodules together
│   ├── config.lua      # Read defaults from _quarto.yml metadata
│   ├── providers.lua   # PROVIDERS registry + provider key normalization
│   ├── scan.lua        # Inline scanner — the actual parser
│   ├── utf8.lua        # UTF-8 word/stop char tables
│   ├── deps.lua        # HTML dependency injection (Bootstrap Icons variant)
│   └── meta.lua        # Metadata key helper
```

The inline scanner is a hand-rolled parser walking Pandoc `Str` /
`Space` nodes looking for `#` boundary-preceded by stop characters
and followed by word characters. It handles the messy case where
Pandoc splits what reads as one hashtag (`#Straßenverkehr`) into
multiple inlines, so a naive per-`Str` regex would miss cross-node
matches.

**Testing.** 17 test files cover: core URL building, numeric filters,
Div class propagation, scan basic / cross-string / nested / skip
classes / stop chars / URL context, shortcode basic / edge cases,
UTF-8 boundary, a golden-paragraph integration test, property-based
micro tests. A performance guard (`run_perf_guard.sh`) runs a 20 K
token synthetic paragraph through the scanner and reports elapsed
time; CI can opt-in to hard-fail via `PERF_ENFORCE=1`.

**Why so much coverage?** The scanner is a parser. Parser bugs tend
to be silent — wrong output looks plausible until someone notices a
broken link in a 3-month-old post. The test density is earned.

**Gotchas.**

- **`skip-classes` is empty by default.** The extension supports
  opting out of auto-scan by giving a Div an excluded class, but the
  current `_quarto.yml` does not configure any. If you ever need
  `.no-hashtag` spans, you must add the class name to
  `hashtag.skip-classes` in metadata.
- **Numeric hashtags are filtered in auto-scan but not shortcodes.**
  `#2024` in body text will not be wrapped; `{{< htag "2024" >}}`
  will. The shortcode layer intentionally trusts the author.

## `date-modified`

**What.** A filter (`date_modified.lua`) that computes a last-modified
timestamp for every page and injects it into the page metadata as
`modification-date` plus SEO `<meta>` tags in `<head>`.

**Why custom.** Quarto has a `date-modified` front-matter field, but
it is static per page and must be maintained by hand. This extension
derives the value from Git history (preferred) or filesystem mtime
(fallback), so it is always accurate without author effort.

**Strategy.**

- `use_mtime: false` (default): run `git log -1 --format=%cI -- <file>`
  for each source file. The project-root `index.qmd` uses the latest
  commit in the entire repo rather than just its own, so home-page
  timestamps reflect any update to the site.
- `use_mtime: true`: always read filesystem mtime; a small state
  file at `.quarto/date-modified.json` stabilizes the output across
  clones where mtimes are not preserved.

**Submodules** under `_extensions/date-modified/_date_modified/`:

- `deps.lua` — CSS/JS dependency injection
- `json.lua` — Minimal JSON reader/writer (does not use Pandoc's
  `pandoc.json`, presumably for Lua 5.1 compatibility)
- `language.lua` + `language/` — Localized labels (`"Güncelleme"` /
  `"Updated"` / `"Actualisé"` / ...)
- `url.lua` — URL normalization, extracted for unit testing
  (commit `c5d9beb`)

**Gotchas.**

- **`normalize_github_url` used to only match `git@github.com:...`.**
  Users with multiple GitHub identities set up SSH host aliases
  (`git@github-<alias>:...`) in `~/.ssh/config`, and the function
  returned those URLs unchanged, which downstream code treated as a
  relative link target. Result: `"Unable to resolve link target:
  git@github-narineneoldu:..."` warnings on every page (144 on a full
  TR+EN build). Fixed in `dc225ea` — now matches both `github.com` and
  `github-*` alias forms.
- **Repo names with dots were also broken.** The same regex had
  `([^%.]+)%.git$` for the repo capture, which stopped at the first
  dot. Repo `narineneoldu.github.io` broke the match. The fix in
  `dc225ea` widened to `(.+)` and strips `.git` as a separate step.
- **Every page render runs `git log -1`.** For a 150-file build that
  is about 150 subprocess invocations. CI budget should account for
  this. On a fast local disk it is a few seconds total.

## `media-short`

**What.** Three shortcodes for Plyr-based rich media players:

| Shortcode          | Purpose                                         |
| ------------------ | ----------------------------------------------- |
| `{{< audio ... >}}`| Audio player with optional auto-VTT subtitles   |
| `{{< video2 ... >}}`| Video player (YouTube, Vimeo, or local URL)    |
| `{{< jump ... >}}` | Anchor link that triggers a player at a timecode|

**Why `video2` and not `video`?** Quarto ships a built-in `video`
shortcode that does basic iframe embedding. This extension's player
needs Plyr integration, caption handling, control presets, and
metadata-driven defaults, so it exports under the name `video2` to
avoid the conflict. **This trips up new readers.** The file is named
`shortcode-video.lua` but the function inside it is `video2` — look
for `return { video2 = ... }` at the bottom.

**Architecture.**

```
_extensions/media-short/
├── shortcode-audio.lua   # {{< audio >}} — ~549 lines
├── shortcode-video.lua   # {{< video2 >}} — ~479 lines
├── shortcode-jump.lua    # {{< jump >}} — ~95 lines
├── _media_short/
│   ├── plyr_common.lua   # Shared helpers: build_attr, build_style, normalize_*
│   ├── deps_core.lua     # Plyr CSS + JS dependency injection (audio + video)
│   └── deps_jump.lua     # Plyr jump extension dependency injection
├── css/                  # plyr.css, media-block.css, vol-popup.css
└── js/                   # plyr.js (vendored), plyr-core, plyr-caption, plyr-jump, plyr-vol-popup
```

The JS bundle is the Plyr library plus a few custom loaders. The
library version is whatever was current when the bundle was last
re-vendored; Plyr has no version file committed alongside it, so
checking the current version means reading the file header.

**VTT subtitles auto-detection.** For local audio files with no
explicit `subtitles` kwarg, the audio shortcode looks for
`<basename>-<lang>.vtt` alongside the audio file. If found, a single
`<track>` element is emitted. Example: `/resources/audio/foo.mp3`
with `lang: tr` → looks for `/resources/audio/foo-tr.vtt`. The
`resources:` list in `_quarto.yml` must include the VTT file for it
to be copied into the build output.

**Gotchas.**

- **`{{< video >}}` does NOT exist in this extension.** Use
  `{{< video2 >}}`. Confused searches for "video" will find Quarto's
  built-in, which looks similar but does not integrate with Plyr.
- **Plyr was previously vendored twice.** Before commit `3175ec3`, a
  second copy lived at `resources/plyr/` and was referenced in
  `_quarto.yml:format.html.css`. The two copies had drifted
  (`plyr-core.js` etc. were different sizes). That directory has been
  deleted; the extension is now the single source of truth. If
  something references `resources/plyr/` after this date, it is a
  regression.
- **Testing coverage is uneven.** `plyr_common` (the foundation) has
  23 unit tests covering `normalize_string`, `normalize_bool`,
  `build_attr`, `build_style`. `shortcode-jump` has 6 golden-file
  snapshot tests. Audio and video2 remain untested — their metadata
  interactions and control-preset resolution are too entangled with
  Pandoc/Quarto globals for a simple smoke test. A bug there will
  manifest as broken Plyr config on embedded media, and will only be
  caught in production.

## `_testkit`

**What.** Three files under `_extensions/_testkit/`:

- `bootstrap.lua` — Sets `_G.FORMAT = "html"`, installs minimal
  `pandoc`, `pandoc.utils`, `pandoc.List`, `quarto` global stubs so
  filter code can be `require`d outside of a real Quarto run.
- `init.lua` — Tiny entry point consumed by `require("_testkit")`.
- `luaunit.lua` — Vendored copy of LuaUnit.

**How extensions use it.** Each extension has a symlink
`tests/_testkit` → `../../_testkit` and a `tests/proxy.lua` that
configures `package.path` (adds the extension root) then calls
`require("_testkit")`. Test files begin with `require("proxy")` and
then `require("luaunit")`.

This lets test runs happen with plain `lua test_file.lua` — no
Quarto, no Pandoc binary needed — which makes the test feedback loop
instant (milliseconds, not ~4 minutes for a full render).

**Cost.** The pandoc stub is minimal. Anything that reaches for a
Pandoc function not in the stub (for example,
`pandoc.utils.from_raw_format` or `pandoc.MetaBlocks`) will either
crash the test or silently produce wrong output. If you add a test
that needs a new Pandoc capability, extend the stub in
`_testkit/bootstrap.lua` rather than per-extension.

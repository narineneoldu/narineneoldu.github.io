---
last-verified: 2026-04-16
verified-against-commits: 4db3ec3..3175ec3
scope: pandoc filter ordering, global vs local overrides, span_multi internals
---

> **This document is an architectural overview, not a source of truth.**
> When the code and this file disagree, the code wins. `tr/_quarto.yml`,
> `en/_quarto.yml`, `shared/lua/span_multi.lua`, and any `_metadata.yml`
> under `tr/` / `en/` are the ground truth.

# Filter Pipeline

Quarto runs a chain of Lua filters over the Pandoc AST of each `.qmd`
file during render. The order of this chain is load-bearing: several
filters assume an earlier filter has already normalized or tagged the
content, and a wrong order silently corrupts output.

## Global filter chain

Declared in `tr/_quarto.yml` (and the structurally identical
`en/_quarto.yml`). The list from top to bottom is the execution order:

| # | Filter                                     | Purpose                                                                                     |
| - | ------------------------------------------ | ------------------------------------------------------------------------------------------- |
| 1 | `date-modified` (extension)                | Compute last-modified timestamp per page from Git (fallback: mtime); inject into page meta. |
| 2 | `hashtag` (extension)                      | Convert `#etiket` inline patterns to social-media search links; register `{{< htag >}}` shortcodes. |
| 3 | `header-slug` (extension)                  | Override Pandoc's default slug generation with Turkish-aware folding. |
| 4 | `../shared/lua/render_start_timer.lua`     | Stash per-qmd start time into a Pandoc state table for `render_end_timer`. |
| 5 | `../shared/lua/span_multi.lua`             | **The big one.** Ten detectors run over paragraph text in a single pass; see below. |
| 6 | `../shared/lua/filter_internal_links.lua`  | Walk `Link` nodes, tag internal links with a CSS class for styling. |
| 7 | `../shared/lua/filter_stats_panel.lua`     | Inject reading-time / stats panel Div using sidecars written by `precompute_reading_stats.py`. |
| 8 | `../shared/lua/render_end_timer.lua`       | Stop per-qmd timer, write TSV row for `emit_render_json.py`, inject footer HTML. |

## Local filter overrides

Quarto supports per-subdirectory filter additions via `_metadata.yml`.
When a `.qmd` lives under a directory with a `_metadata.yml` that
declares `filters:`, Quarto **appends** those filters to the global
chain for files in that subtree. The global chain still runs first.

The canonical example in this repo is **speaker highlighting on
testimony pages**:

```yaml
# tr/trial/testimonies/_metadata.yml
filters:
  - ../../../shared/lua/anchor_lines.lua
  - ../../../shared/lua/highlight_speakers.lua
  - ../../../shared/lua/render_end_timer.lua
```

What this does:

- `anchor_lines.lua` runs **after** `span_multi` and injects `<a id="…">`
  anchors at the start of paragraphs (so a deep link can point at a
  specific utterance).
- `highlight_speakers.lua` runs after that, scanning for
  `Speaker Name : utterance` at line start and wrapping the result as
  `<span class="speaker GROUP">…</span> <span class="utterance">…</span>`.
- `render_end_timer.lua` is re-declared so the local timing TSV row is
  written **after** the testimony-specific filters, giving an accurate
  per-file timing.

Effects to be aware of:

1. **`highlight_speakers.lua` is not global.** It only activates inside
   `tr/trial/testimonies/` (and the mirror `en/trial/testimonies/`).
   Adding speaker-like dialogue in a blog post will not get highlighted.
2. **Local filters cannot reorder or remove global filters.** If a
   testimony page needs to bypass `span_multi`, the only escape hatches
   are the skip mechanisms built into `span_multi` itself (below).
3. **Duplicating `render_end_timer.lua` in the local list is intentional.**
   It replaces the timing emission at the end of the extended chain so
   numbers reflect the actual full pipeline, not just the global part.

## What `span_multi.lua` actually does

`span_multi` is a unified inline processor, not a wrapper over a single
detector. It:

1. Loads ten per-language utility modules (`utils_phone`, `utils_plate`,
   `utils_unit`, `utils_abbr`, `utils_time`, `utils_record`, `utils_date`,
   `utils_day`, `utils_participant`, `utils_refs`). Each module has the
   same interface:

   ```lua
   M.set_dict(meta)   -- one-time: read metadata into a cache
   M.find(text)       -- many times: return list of {s, e, kind, ...}
   ```

   For `en` renders, `span_multi` first tries `utils_<name>_en` and
   falls back to `utils_<name>`. This is how `utils_date_en.lua` and
   `utils_unit_en.lua` exist alongside the TR defaults.

2. Walks every `Para` and `Plain` block. For each block:
   1. Collects a run of textlike inlines (`Str`, `Space`, `SoftBreak`).
   2. Linearizes the run into a single string plus a map from string
      indices back to inline positions (`shared/lua/inline_utils.lua`).
   3. Runs **every** `util.find(text)` against that string. Each
      detector returns hits independently.
   4. Merges all hit lists: sorts by start index, resolves overlaps
      greedily with the priority table (higher wins; ties broken by
      longer match).
   5. Rebuilds the inline list with `<span class="…">` wrappers around
      each accepted hit, preserving original text between hits.

3. After span rewriting, two follow-up passes run over the same blocks:
   - **ParenFilter**: wraps balanced `(...)` text in a paren span.
   - **QuoteFilter**: wraps `"..."` text in `<span class="quote">`.

   These are kept out of the main dispatch because they operate on
   matched pairs of characters that are far easier to express as a
   small state machine than as `find()` hit lists.

### Priority table

```lua
{ key = "phone",       pri = 7  },
{ key = "plate",       pri = 6  },
{ key = "unit",        pri = 5  },
{ key = "abbr",        pri = 4  },
{ key = "time",        pri = 3  },
{ key = "record",      pri = 2  },
{ key = "date",        pri = 1  },
{ key = "day",         pri = 0  },
{ key = "participant", pri = 8  },
{ key = "refs",        pri = 20 },
```

`refs` dominates everything (external reference spans must never be
broken by a detector eating part of the reference text). `participant`
outranks `phone` (an unusual case where a phone number overlaps a name
would be absurd, but the ordering is defensive). `day` has priority 0
and effectively fills whatever is left.

**If two detectors can plausibly fire on the same substring you must
think about priority explicitly.** Adding a new detector means adding
its `pri` value to this table and verifying the new detector's output
against participant/abbr/phone overlaps by hand.

## Skip mechanisms

Three layers let content opt out of `span_multi` processing, each
broader than the last.

### 1. Per-span class skip

Any existing `Span` whose class is already one of the known kinds
(`phone`, `plate`, `abbr`, `unit`, `time`, `record`, `date`, `day`,
`participant`, `refs`, or the special `speaker`, `utterance`,
`span-multi-skip`) is left alone on subsequent passes. This is what
makes the filter idempotent: re-running it on its own output produces
no changes.

### 2. `span-multi-skip` class

`mark_quarto_navigation_envelope` (inside `span_multi.lua`) finds
`Div#quarto-navigation-envelope` (the top-level wrapper Quarto puts
around navbar/sidebar content) and wraps every inline child with
`<span class="span-multi-skip">`. Detectors then see only the
body-content paragraphs; navbar text is untouched.

Manual opt-out: wrap any Div in `{.span-multi-skip}` in your `.qmd` to
exempt it.

### 3. Whole-document opt-outs

Two top-level escape hatches:

- **`disable-spanning: true`** in a page's YAML front matter — skip
  `span_multi` entirely for that page. Nothing is wrapped. Use this for
  pages where the detector heuristics produce false positives that
  outweigh the value.
- **`metadata.span-multi-skip`** in `_quarto.yml` (or a subtree
  `_metadata.yml`) lists source paths to skip:

  ```yaml
  metadata:
    span-multi-skip:
      - blog/posts/some-author/quoted-external-piece.qmd
  ```

  Paths are matched against `quarto.doc.input_file` (POSIX-normalized)
  at render time.

### 4. Never recurse into `<a>`

`span_multi` hard-codes a rule: inside a `Link` inline, it does not
recurse into `el.content`. Anchor text is untouched regardless of its
content. Rationale: link text is authored for a specific destination,
and wrapping an abbreviation tooltip around the word "Adli Tıp Kurumu"
in a link to the real ATK page would clash with the link's own tooltip.

## Filter ordering gotchas

- **`date-modified` runs first** because it adds `modification-date`
  into page meta that later filters and the page template read. If it
  moved after `span_multi`, the footer template would render before
  the date was known.
- **`header-slug` runs before `span_multi`** so that heading IDs are
  stable regardless of whether `span_multi` later inserts spans inside
  the heading content. A reordering here would not break rendering but
  would desync cross-document anchor links if any heading ever
  contained a span.
- **`render_start_timer.lua` must precede `render_end_timer.lua`.**
  Trivially obvious, but both live in `shared/lua/` — do not rename one
  without the other.
- **`filter_stats_panel.lua` runs after `span_multi`** because it
  injects a Div that should not itself be scanned for phones, dates,
  etc. (The panel contains numbers like "3 min read" that would
  otherwise match `utils_time` or `utils_date`.)
- **Testimony local filters append to the global chain**, so
  `highlight_speakers` sees the output of `span_multi`. A speaker line
  already has participant spans inside the utterance half; the speaker
  filter wraps around them without disturbing the inner structure.

## Where to look when a filter misbehaves

| Symptom                                                 | Probable source |
| ------------------------------------------------------- | --------------- |
| A name is not highlighted in body text                  | `utils_participant.lua` variant generation, or missing entry in `_quarto.yml:metadata.participant` |
| A name is highlighted inside a word (`XSanık Salim`)    | Left-boundary check fails or the variant list has a too-short entry |
| An utterance line is not split into speaker + utterance | `highlight_speakers.lua`, or the testimony page is not under `tr/trial/testimonies/` |
| A page has duplicate detector spans                     | `span_multi` ran twice — usually means an upstream filter produced already-wrapped output without the expected class |
| Dates look wrong in English pages                       | `utils_date_en.lua` lookup failed and it fell back to `utils_date.lua` |
| "Unable to resolve link target" warning mentioning `git@` | `_extensions/date-modified/_date_modified/url.lua` did not recognize the remote URL form |

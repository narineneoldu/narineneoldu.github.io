---
last-verified: 2026-04-16
verified-against-commits: 4db3ec3..3175ec3
scope: cross-file architecture and build/deploy flow
---

> **This document is an architectural overview, not a source of truth.**
> When the code and this file disagree, the code wins. Check the
> `verified-against-commits` range above: if `git log` shows significant
> changes since then in `tr/_quarto.yml`, `en/_quarto.yml`, `build*`, or
> `shared/bash/*`, treat this file with suspicion until re-verified.

# Architecture

## Directory layout

```
narineneoldu.github.io/
├── tr/               # Turkish site — CANONICAL source
│   ├── _quarto.yml   # Global config: website, filters, metadata, resources
│   ├── _quarto-dev.yml, _quarto-prod.yml   # Profile overrides
│   ├── _site/        # Quarto render output (gitignored)
│   ├── index.qmd, 404.qmd
│   ├── blog/, trial/, about/, faq/, guide/, resources/, test/
│   └── trial/testimonies/_metadata.yml   # Local filter override
│
├── en/               # English site — translated from tr/
│   ├── _quarto.yml   # Mirrors tr/_quarto.yml structure (EN strings)
│   ├── _site/        # Quarto render output (gitignored)
│   └── (parallel tree of .qmd files under tr/)
│
├── shared/
│   ├── lua/          # Filters and utils used by both tr/ and en/
│   ├── python/       # Pre-render hooks (reading stats, timer, pandoc AST)
│   └── bash/         # clean.sh, sync-en.sh, sync-tr.sh, deploy.sh
│
├── _extensions/      # Local Quarto extensions (header-slug, hashtag,
│   │                 # date-modified, media-short) + _testkit (shared)
│   └── _testkit/     # Shared luaunit test harness (symlinked from per-ext)
│
├── resources/        # Static assets at repo root: css/scss/js/images/...
│                     # Both sites reference these via absolute /resources/... paths.
│
├── docs/             # GitHub Pages publish root (tracked in git!)
│                     # Final deploy target. Not overwritten by ./build; only by
│                     # shared/bash/deploy.sh.
│
├── build, build-tr, build-en, preview-tr, preview-en,
│ deploy.sh (in shared/bash/), ignore-docs, no-ignore-docs
```

## TR is canonical; EN nests under TR

The site is mono-domain, bilingual. Only `docs/` is served by GitHub Pages;
the Turkish site lives at the root and the English site lives at `/en/`.
This is achieved in post-render by `shared/bash/sync-en.sh` which rsyncs
`en/_site/` into `tr/_site/en/`. The merged `tr/_site/` is then the
deploy source.

Consequences:

- English pages' canonical URLs are under `/en/...` — keep this in mind
  for `site-url`, `repo-url`, and sitemap generation.
- A change to `resources/` affects both sites simultaneously (single source).
- If only `./build-en` is run, `tr/_site/en/` is **not** regenerated
  (that sync runs inside the TR render pipeline). To preview the merged
  result, use `./build` or render TR after EN.

## Build vs deploy

These are separate operations, intentionally. Rendering does not publish.

### Render (local preview of changes)

| Command  | Effect                                                                  |
| -------- | ----------------------------------------------------------------------- |
| `./build`    | `quarto render tr/` then `quarto render en/`. Writes to `tr/_site/`, `en/_site/`. Runs all hooks. |
| `./build-tr` | TR only. `tr/_site/`.                                                 |
| `./build-en` | EN only. `en/_site/`. Does **not** re-sync into TR site.              |
| `./preview-tr` | `quarto preview tr --no-browse` (port 7777). Hot reload loop.      |
| `./preview-en` | `quarto preview en --no-browse`.                                  |

All scripts accept an optional profile argument: `./build dev` (default)
or `./build prod`. Profiles come from `_quarto-dev.yml` / `_quarto-prod.yml`
overrides applied on top of `_quarto.yml`.

### Deploy (publish to GitHub Pages)

`shared/bash/deploy.sh` is the only script that writes to `docs/`. It
rsyncs `tr/_site/` → `docs/` (with `--delete`). This is deliberately
separated from `build` so that multi-step editing sessions don't produce
a noisy `docs/` diff on every save.

Typical workflow:

1. `./preview-tr` — iterate on changes with hot reload
2. Commit small changes as you go (do not touch `docs/`)
3. When done with the work, run `./shared/bash/deploy.sh` once, commit
   the updated `docs/`, push.

`./build` also writes to `_site/` directories but its success message
says "`Output directory: docs/`" which is misleading — it does not copy
to `docs/`.

## Pre- and post-render hooks

The hook chain lives in `tr/_quarto.yml:pre-render`, `tr/_quarto.yml:post-render`
and equivalents for `en/`. Each entry is a script path relative to the
project directory. Order matters: failures abort the render.

**Pre-render:**

1. `shared/bash/clean.sh` — remove temp `.qrender-time.tmp-*.tsv` and
   stale debug logs from the previous run.
2. `shared/python/precompute_reading_stats.py` — walk every `.qmd`, compute
   reading-time / word-count stats, write sidecar YAML used by
   `filter_stats_panel.lua`.
3. `shared/python/render_timer.py start` — record wall-clock start time
   in `.qrender_timer.tmp.json`.

**Post-render:**

1. `shared/bash/sync-en.sh` (TR build) or the equivalent — rsync
   `en/_site/` → `tr/_site/en/` so the merged TR site contains both
   languages. On the EN-only build path this hook is a no-op.
2. `shared/python/render_timer.py end` — compute elapsed, print
   `Total elapsed time`, invoke `emit_render_json.py` which aggregates
   per-file timing TSV into `.qrender-time-<lang>.json`.

Renamed / deleted scripts here will fail the build loudly (pre-render
scripts run with `set -e`). A silent-failing pre-render hook is a much
worse bug than a loud one.

## Profiles: dev vs prod

`tr/_quarto.yml` declares `profiles: [dev, prod]`. `_quarto-dev.yml` and
`_quarto-prod.yml` are override layers loaded when the matching profile
is active. Profile is selected via the `--profile` flag passed by the
build scripts.

The exact differences between dev and prod overrides change over time —
diff the two files to see current state. Typical usage:

- `dev` is the default for local iteration. Lighter config, fewer
  optimizations, no analytics, faster feedback.
- `prod` is the default for publishing. Enables whatever is gated
  behind the prod flag (analytics, minification, strict link checking,
  etc. — again, diff to confirm).

When introducing a new config knob that should differ between dev and
prod, put the default in `_quarto.yml` and the override in one of the
profile files. Do not duplicate across both profiles.

## Known pitfalls

1. **`docs/` is tracked in git** because GitHub Pages publishes from it.
   Every deploy produces hundreds of diff lines. The `ignore-docs` and
   `no-ignore-docs` scripts toggle `git update-index --assume-unchanged`
   on all files under `docs/` as a local-only workaround so in-progress
   commits don't show the build noise. This is not a real ignore: it is
   per-clone, can be reset by `git pull`/`merge`, and easily forgotten.
   A GitHub Actions `gh-pages` deploy would eliminate this entirely.
   See the notes in `CLAUDE.md` under "Bilinen Kapalı Konular".

2. **Silent broken links via `css:` list**. Quarto does **not** fail the
   build when a file listed under `format.html.css` is missing — it
   emits a broken `href=""` into the HTML with zero warning. The
   pre-`3175ec3` project had `resources/plyr/plyr.css` in that list for
   a file that existed but was a redundant duplicate. Renaming the
   source file did not trigger any build error. Watch for this when
   moving static assets.

3. **Build timing is stabilized** (not real). `shared/lua/render_end_timer.lua`
   intentionally smooths per-file render durations: if the new value is
   within ±500 ms of the previously-recorded value in
   `.qrender-time-<lang>.json`, the old value is kept. Footer shows
   stable numbers page-to-page, and the aggregated "Quarto render time"
   line on stdout inherits the same stabilization. This means running
   `./build` four times in a row prints the same `Quarto render time`
   down to the millisecond — **not** a cache bug, by design. For actual
   wall-clock, read the `Total elapsed time` line that `render_timer.py`
   produces.

4. **`_site/` directories are not stable between `./build` invocations
   with different subset scripts.** `./build-en` updates `en/_site/`
   but leaves `tr/_site/en/` stale. Running `./preview-tr` after
   `./build-en` will serve the old EN copy until you rerun the TR
   pipeline. Prefer `./build` for a coherent snapshot.

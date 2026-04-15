---
last-verified: 2026-04-16
verified-against-commits: 4db3ec3..3175ec3
scope: _quarto.yml metadata schemas consumed by shared Lua filters
---

> **This document is an architectural overview, not a source of truth.**
> The authoritative schema is whatever the consuming Lua files actually
> read. If you add a field and this file doesn't mention it, trust the
> code. Primary consumers: `shared/lua/utils_participant.lua`,
> `shared/lua/utils_phone.lua`, `shared/lua/utils_plate.lua`,
> `shared/lua/utils_abbr.lua`, `shared/lua/highlight_speakers.lua`.

# Metadata Schemas

Four domain-specific metadata blocks in `tr/_quarto.yml` (mirrored in
`en/_quarto.yml`) drive automatic inline annotation across the site:

- `metadata.phones` — phone number → tooltip map
- `metadata.plates` — license plate → tooltip map
- `metadata.abbr`   — acronym → expansion map
- `metadata.participant` — hierarchical speaker / person directory

All four are loaded lazily during each render by `span_multi.lua`'s
dispatch and passed to the matching `utils_*` module's `set_dict(meta)`
entry point. Adding a new row to any of them requires no code changes;
adding a new kind of entry (a new top-level key) requires a matching
detector module.

## Simple dictionaries

### `phones` and `plates`

Plain string → string maps:

```yaml
metadata:
  phones:
    "0533XXX9779": "Nevzat Bahtiyar'ın kullandığı telefon numarası"
    "0536XXX7120": "Yüksel Güran'ın kullandığı telefon numarası"
  plates:
    "23 XX 630": "Nevzat Bahtiyar'ın kullandığı kırmızı araç"
    "47 XX 388": "Salim Güran'ın kullandığı araç"
```

Rules:

- The key is matched **literally** (plain, case-sensitive) against
  paragraph text via `string.find(text, key, start, true)`. No regex,
  no normalization. The spacing and digit pattern must match exactly
  how it appears in content.
- The value becomes the `data-title` attribute on the emitted span,
  consumed by `resources/js/plate-tooltip.js` (for plates; phones use
  a similar tooltip mechanism via CSS + JS).
- Sensitive data is partially masked with `XXX` / `XX` on purpose.
  Content authors write the masked form in text and metadata together,
  not full numbers.

### `abbr`

Same shape — acronym → full expansion string:

```yaml
metadata:
  abbr:
    AAÜT: "Avukatlık Asgari Ücret Tarifesi"
    ATK: "Adli Tıp Kurumu"
    CMK: "Ceza Muhakemesi Kanunu"
    "fer'i": "yan, tali"
    SEGBİS: "Ses ve Görüntü Bilişim Sistemi"
```

Differences from phones/plates:

- **Longest key wins**. `utils_abbr.lua` sorts keys by length
  descending before matching, so `"AAÜT"` is attempted before `"A"`
  (if both existed). Avoid adding single-letter keys unless you
  understand the consequences.
- **`(KEY)` form is skipped**. The detector explicitly recognizes
  `(ATK)` as a parenthetical gloss that authors write after the first
  occurrence and does not wrap it as an abbreviation. This prevents
  double-tooltips on `"Adli Tıp Kurumu (ATK)"`.
- Non-ASCII keys work (`SEGBİS`, `fer'i`) because the key is matched
  as bytes, not as Latin-range regex.

## `participant` — the hierarchical schema

This is the only structured one. It drives both `utils_participant`
(inline span wrapping inside body text) and `highlight_speakers`
(line-start speaker detection inside testimony pages).

### Shape

```yaml
metadata:
  participant:
    victim:                                 # group key → becomes CSS class
      - variant: true                       # enable UPPERCASE surname variant
      - text: Maktul                        # human-readable label for data-title
      - prefix:                             # acceptable prefixes (for variant expansion)
        - Maktul
      - suffix:                             # (reserved; not currently used)
      - names:
        - "Narin Güran"
    suspect:
      - variant: true
      - text: Sanık
      - prefix:
        - Sanık
      - names:
        - "Nevzat Bahtiyar"
        - "Yüksel Güran"
        - "Salim Güran"
        - "Enes Güran"
    witness:
      - variant: true
      - text: Tanık
      - names:
        - "Muhammed Emre Güran"
        - "Maşşallah Güran"
        - "Maşallah Güran"                  # alternate spelling kept explicitly
    mudafi-enes:
      - text: "Sanık Enes Güran Müdafi"
      - prefix:
        - "Av."
      - names:
        - "Mahir Akbilek"
        - "Mustafa Demir"
```

Each group's value is a **YAML sequence of small maps**, not a single
map. The parser concatenates `prefix` and `names` across entries, so
you can split them across list items if it aids readability. In
practice every group uses exactly this pattern: one item each for
`variant`, `text`, `prefix`, `suffix`, `names`.

### Field meanings

| Field | Purpose | Consumer |
| ----- | ------- | -------- |
| `variant` | If `true`, generate the UPPERCASE-SURNAME variant (`Narin GÜRAN`) alongside the base name. Case-sensitive Turkish conversion via `to_upper_tr`. | Both |
| `text` | Human-readable group label. Appears in `data-title` tooltips and is used to decide whether to append the label to the data-title. | `utils_participant` |
| `prefix` | Strings that legitimately precede the name in running text (`Sanık Salim`). For each prefix, lowercase and title-cased variants are both produced. | Both |
| `suffix` | Currently not consumed. Kept in the YAML for future use / documentation. | (none) |
| `names` | The canonical full names. Every name is expanded into the variant set described below. | Both |

### Group keys → CSS classes

The group key (`victim`, `suspect`, `witness`, `mudafi-enes`, `kdb`,
`ashb`, `judge`, `prosecutor`, `complainant`, `others`) is emitted as
the second CSS class on the span:

```html
<span class="participant suspect" data-title="Sanık">Nevzat Bahtiyar</span>
```

When adding a new group key you must also add a matching SCSS rule in
`resources/scss/` so the group has visible styling. Without that, the
span exists but looks identical to surrounding text.

### Variant generation algorithm

`utils_participant.lua:build_variants_for_name()` takes one full name
plus prefix list and emits a set of strings to scan for. For
`"Narin Güran"` with `prefix: [Maktul]` and `variant: true`:

```
Narin Güran                 # base
Narin GÜRAN                 # UPPERCASE surname (variant: true)
maktul Narin                # prefix + given part, lowercase prefix
Maktul Narin                # prefix + given part, capitalized prefix
maktul Narin Güran          # prefix + full
Maktul Narin Güran
maktul Narin GÜRAN
Maktul Narin GÜRAN
```

Key design decisions, with rationale:

1. **The bare given name (`Narin`) is NOT in the variant set.** If
   "narin" appeared as a Turkish adjective ("delicate") the detector
   would wrongly wrap every occurrence. The given part only appears
   as a prefix expansion (`Maktul Narin`), which is grounded by the
   prefix and unambiguous.

2. **Surname-uppercase variant requires `variant: true`.** Turkish
   court documents routinely render surnames in all caps
   (`Nevzat BAHTİYAR`). Groups that always appear as full-case only
   should leave `variant` off — it suppresses the UPPERCASE-branch
   output and keeps the variant set smaller.

3. **No suffix variants.** `Salim Güran'ın`, `Narin'in`, etc. are
   never produced. Turkish case endings are too productive to
   enumerate (they depend on vowel harmony, consonant mutation,
   apostrophes). Instead, the matcher intentionally leaves the suffix
   outside the wrapped span (see below).

4. **Longer names win.** `PARTICIPANTS` is sorted by variant length
   descending before matching, so `"Nevzat Bahtiyar"` is tried before
   `"Nevzat"`. This is how the detector avoids double-wrapping.

### Matching rules

Inside `utils_participant.find_hits()`:

1. **Left word boundary is checked.** If the character immediately
   before a hit is a word character (`[%w]`, ASCII-only), the hit is
   rejected. `"XSanık Salim"` will not match.
2. **Right word boundary is NOT checked.** This is deliberate. A
   match on `"Sanık Salim"` inside `"Sanık Salim'in"` leaves `'in`
   outside the span, which is exactly the desired rendering.
3. **Header-line heuristic.** If the hit falls before the first `:`
   in the paragraph and within the first 40 characters, it is
   rejected. Rationale: that region is a speaker-line header
   (`Speaker Name :`) which is handled by `highlight_speakers.lua`
   on testimony pages, and double-wrapping would clobber the speaker
   span.
4. **Matching is case-sensitive plain find.** There is no
   case-insensitive fallback; the variant set must pre-generate every
   reachable casing.

### Data-title assignment rules

The emitted span's `data-title` is either:

- Omitted if the variant already contains the group label
  (`"Maktul Narin"` → no redundant tooltip).
- Set to just `group_label` (`"Maktul"`) if the variant contains the
  surname but not the group label.
- Set to `group_label + full_name` (`"Maktul Narin Güran"`) if the
  variant contains neither.

See `utils_participant.lua:290-310`.

## Known gotchas

1. **Spelling variants are manual.** `"Maşşallah"` and `"Maşallah"`
   appear in the witness list because real court documents use both
   spellings. The metadata has no fuzzy matching — add every spelling
   you encounter in source material, or the inconsistent variant will
   render as plain text.

2. **A single-word name in `names` will match every occurrence of
   that word.** Do not shorten `"Salim Güran"` to `"Salim"` to save
   typing; it will wrap every sentence containing `salim` (including
   non-name uses). If you need just the given name for a specific
   context, add it as a prefix on a longer base.

3. **Adding a participant means touching two places.**
   `_quarto.yml:metadata.participant` for detection AND the
   `_quarto.yml:website.sidebar` entry for navigation (if the person
   has their own testimony/defense page). Forgetting the sidebar
   leaves a dead page; forgetting the metadata leaves unhighlighted
   names.

4. **`utils_participant.lua` and `highlight_speakers.lua` duplicate
   variant logic.** They share `normalize_spaces`, `to_upper_tr`,
   `capitalize_first`, `title_case`, and most of the variant
   enumeration. A bug fix in one must be mirrored in the other. This
   is a long-standing hazard waiting to be refactored into a shared
   helper — see `CLAUDE.md` notes.

5. **`variant: false` (or omitted) has a non-obvious effect.** It
   does not just turn off UPPERCASE generation — it also prevents the
   prefix expansion for the given part. Non-variant groups get only
   full-name plus prefix-plus-full-name forms. When in doubt, diff
   the variant set for your new entry by adding a debug print in
   `build_variants_for_name`.

6. **`abbr` and `participant` overlap is resolved by priority.**
   `participant: 8` beats `abbr: 4`. If a name contains a known
   abbreviation substring, the name wins. Example: if `"ATK"` were an
   abbreviation and a hypothetical witness name were `"Atk Demir"`,
   the witness wrap would swallow the abbreviation. Not a current
   problem, but worth knowing before adding short abbreviations.

7. **No test coverage exists for any of this.** The variant builder
   and `find_hits` are pure Lua functions with no external
   dependencies — they would be trivial to test against a fixture,
   but no test file exists today. Adding regressions is easy; catching
   them in review is hard.

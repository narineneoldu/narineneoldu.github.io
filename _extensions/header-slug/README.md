# header-slug

A Pandoc / Quarto Lua filter that generates **stable, readable header slugs** for multilingual documents.

Unlike Pandoc’s default slug generation, `header-slug` provides:
- Correct handling of **Turkish I / İ / ı**
- Latin character folding for **European languages**
- Built-in transliteration for **Greek** and **Cyrillic (Russian)**
- Safe handling of **non‑Latin scripts** (Chinese, Japanese, Arabic, etc.)
- Deterministic and collision‑free header identifiers

This makes it especially suitable for multilingual blogs, documentation sites, and archives.

---

## Features

### ✔ Language-aware folding
The extension transliterates characters using a carefully curated map:

- **Latin-based languages** (French, German, Spanish, etc.)
- **Turkish** (special I / İ / ı handling)
- **Greek**
- **Cyrillic (Russian)**

Examples:

| Header | Generated slug |
|------|----------------|
| `İstanbul'da Işık` | `istanbulda-isik` |
| `Fußgängerstraße` | `fussgangerstrasse` |
| `École d'été` | `ecole-dete` |
| `Привет мир` | `privet-mir` |
| `Γεια σου Κοσμε` | `geia-soy-kosme` |

---

### ✔ Non‑Latin scripts are preserved

Scripts that are **not explicitly transliterated** are kept as-is:

| Header | Generated slug |
|------|----------------|
| `中文 标题` | `中文-标题` |
| `日本語の見出し` | `日本語の見出し` |
| `عنوان عربي` | `عنوان-عربي` |

---

### ✔ Deterministic unique IDs

Duplicate headers are suffixed automatically:

```text
ecole-dete
ecole-dete-2
ecole-dete-3
```

---

## Installation

### Quarto extension

```bash
quarto add narineneoldu/header-slug
```

Or clone manually into `_extensions/header-slug/`.

---

### Pandoc usage

```bash
pandoc input.md --lua-filter=header_slug.lua -o output.html
```

---

## Testing

```bash
lua tests/test_slugify.lua
```

---

## License

MIT

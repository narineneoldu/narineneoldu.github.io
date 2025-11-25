#!/usr/bin/env python3
# ../shared/python/precompute_reading_stats.py

import os
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import subprocess
import json
import yaml  # PyYAML
import re

SECONDS_PER_SYLLABLE = 0.2

# Glob patterns relative to PROJECT_ROOT
GLOB_PATTERNS = [
    # "blog/posts/ali-duran-topuz/2025-10-23-Narin-Guran-vakasi-2/index.qmd",
    "trial/judgment.qmd",
    "trial/defenses/*/*.qmd",
    "trial/testimonies/suspect/*/testimony.qmd",
    "trial/testimonies/witness/*.qmd",
    "blog/posts/*/*/index.qmd",
]

GLOB_NOT_PATTERNS = [
    "trial/defenses/*/index.qmd",
]

# List of paths for totals
AGGREGATED_PATHS = [
    "trial",
    "trial/testimonies",
    "trial/testimonies/suspect",
    "trial/testimonies/witness",
    "trial/defenses",
    "trial/defenses/*",
    "blog",
    "blog/posts/*"
]

TURKISH_VOWELS = set("aeıioöuüâîûAEIİOÖUÜ")

# Global word log file handle (for temporary debugging)
ENABLE_WORD_LOGGING = False  # False → do not create tmp word files
WORD_LOG = None


def collect_glob(root: Path, patterns):
    """Return a list of Path objects matching given glob patterns."""
    out = []
    for pat in patterns:
        out.extend(root.glob(pat))
    return out


def resolve_qmd_files(root: Path, include_patterns, exclude_patterns):
    include = collect_glob(root, include_patterns)
    exclude = collect_glob(root, exclude_patterns)
    # Set difference
    final = sorted(set(include) - set(exclude))
    return final


def is_vowel(ch: str) -> bool:
    return ch in TURKISH_VOWELS


def strip_brackets_and_braces(tok: str) -> str:
    """
    Remove curly and square brackets from the whole token.
    This covers cases like {yazdığım yazıda}[1].
    """
    return re.sub(r"[{}\[\]]+", "", tok)


def normalize_for_vowel_check(tok: str) -> str:
    """Remove digits before vowel check."""
    return re.sub(r"\d+", "", tok)


def has_vowel(tok: str) -> bool:
    """Return True if token contains at least one vowel (after digit removal)."""
    tok_clean = normalize_for_vowel_check(tok)
    for ch in tok_clean:
        if is_vowel(ch):
            return True
    return False


def is_all_digits(tok: str) -> bool:
    """Return True if token is composed only of digits."""
    tok = tok.strip()
    return bool(tok) and tok.isdigit()


def stats_yaml_path(qmd_path: Path) -> Path:
    """Return the path to the reading stats yaml next to the qmd file."""
    # "index.qmd" -> "index_reading_stats.yml"
    return qmd_path.with_name(qmd_path.stem + "_reading_stats.yml")


def load_existing_stats(yml_path: Path):
    """Load existing YAML stats file, if any."""
    if not yml_path.exists():
        return None
    with yml_path.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def compute_file_hash(path: Path, lang: str, seconds_per_syllable: float) -> str:
    """Compute a stable hash for the qmd file plus relevant config."""
    h = hashlib.sha256()
    # Include file content
    h.update(path.read_bytes())
    # Include relevant config so changes invalidate the stats
    h.update(lang.encode("utf-8"))
    h.update(str(seconds_per_syllable).encode("utf-8"))
    return h.hexdigest()


def needs_rebuild(
    qmd_path: Path,
    yml_path: Path,
    lang: str,
    seconds_per_syllable: float,
) -> bool:
    """
    Return True if we need to recompute stats for this qmd file.

    Checks current hash vs stored 'hash' field in YAML.
    """
    new_hash = compute_file_hash(qmd_path, lang, seconds_per_syllable)
    existing = load_existing_stats(yml_path)
    if not existing:
        return True
    return existing.get("hash") != new_hash


def write_stats_yaml(
    qmd_path: Path,
    yml_path: Path,
    file_hash: str,
    lang: str,
    reading: dict,
):
    """
    Write per-file stats YAML in the new schema:

    hash: ...
    generated_at: ...
    language: ...
    type: stat
    reading: { ... }
    """
    payload = {
        "hash": file_hash,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "language": lang,
        "type": "stat",
        "reading": reading,
    }
    with yml_path.open("w", encoding="utf-8") as f:
        yaml.safe_dump(payload, f, allow_unicode=True, sort_keys=False)


def write_index_stats_yaml(
    yml_path: Path,
    aggregated_hash: str,
    lang: str,
    reading: dict,
):
    """
    Write aggregate index_reading_stats.yml in the new schema:

    aggregated_hash: ...
    generated_at: ...
    language: ...
    type: aggregated_stat
    reading: { ... }
    """
    payload = {
        "aggregated_hash": aggregated_hash,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "language": lang,
        "type": "aggregated_stat",
        "reading": reading,
    }
    with yml_path.open("w", encoding="utf-8") as f:
        yaml.safe_dump(payload, f, allow_unicode=True, sort_keys=False)


def load_quarto_config(root: Path):
    """Load lang and seconds-per-syllable from _quarto.yml."""
    config_path = root / "_quarto.yml"
    lang = "tr"
    seconds_per_syllable = SECONDS_PER_SYLLABLE

    if config_path.exists():
        with config_path.open("r", encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
        lang = data.get("lang", lang)
        rt = data.get("reading-time") or {}
        seconds_per_syllable = float(
            rt.get("seconds-per-syllable", seconds_per_syllable)
        )

    return lang, seconds_per_syllable


def get_pandoc_ast(qmd_path: Path):
    """
    Run pandoc on the QMD file and return its JSON AST as a Python dict.
    """
    cmd = [
        "pandoc",
        str(qmd_path),
        "-f",
        "markdown+yaml_metadata_block+fenced_divs+link_attributes+bracketed_spans+pipe_tables+grid_tables+raw_html",
        "-t",
        "json",
    ]
    result = subprocess.run(cmd, check=True, capture_output=True)
    return json.loads(result.stdout.decode("utf-8"))


def syllables_for_word(tok: str) -> int:
    """Approximate syllable count for a single token."""
    tok_clean = normalize_for_vowel_check(tok)
    syllables = 0
    prev_vowel = False
    saw_letter = False

    for ch in tok_clean:
        if ch.isalpha():
            saw_letter = True
        v = is_vowel(ch)
        if v and not prev_vowel:
            syllables += 1
        prev_vowel = v

    # Handle pure numbers: count them as 1 syllable for timing
    if is_all_digits(tok):
        return 1

    # If we saw letters but no vowel, count as 1 (abbreviations, etc.)
    if saw_letter and syllables == 0:
        syllables = 1

    return syllables


def count_token(tok: str):
    """
    Return (syllables, words) contribution of a single raw token.

    Rules:
    - Strip { } [ ] everywhere in the token.
    - If token is all digits -> ignore as a word but timing fallback handled above.
    - Otherwise, remove digits and check if there is any vowel.
      If there is, count as one word and compute syllables.
      If not, ignore as a word.
    """
    from __main__ import WORD_LOG  # ensure we refer to the global in this module

    tok = strip_brackets_and_braces(tok)
    tok = tok.strip()

    if not tok:
        return 0, 0

    # Non-pure-number tokens:
    if has_vowel(tok):
        syl = syllables_for_word(tok)
        # Log counted word to tmp file if logging is enabled
        if WORD_LOG is not None:
            WORD_LOG.write(tok + "\n")
        return syl, 1
    else:
        # No vowel after digit removal → ignore as word
        return 0, 0


def count_inlines(inlines):
    """Count (syllables, words) in a list of Pandoc inlines (JSON AST form)."""
    total_syllables = 0
    total_words = 0

    for el in inlines:
        t = el["t"]
        c = el.get("c")

        if t == "Str":
            text = c
            for tok in text.split():
                syl, w = count_token(tok)
                total_syllables += syl
                total_words += w

        elif t in ("Emph", "Strong"):
            inner = c
            s, w = count_inlines(inner)
            total_syllables += s
            total_words += w

        elif t == "Span":
            if isinstance(c, list) and len(c) >= 2:
                inner = c[1]
                s, w = count_inlines(inner)
                total_syllables += s
                total_words += w

        elif t == "Quoted":
            if isinstance(c, list) and len(c) == 2:
                inner = c[1]
                s, w = count_inlines(inner)
                total_syllables += s
                total_words += w

        elif t == "Link":
            if isinstance(c, list):
                if len(c) >= 2 and isinstance(c[1], list):
                    inner = c[1]
                elif len(c) >= 1 and isinstance(c[0], list):
                    inner = c[0]
                else:
                    inner = []
                s, w = count_inlines(inner)
                total_syllables += s
                total_words += w

        elif t == "Image":
            if isinstance(c, list):
                if len(c) >= 2 and isinstance(c[1], list):
                    alt_inlines = c[1]
                elif len(c) >= 1 and isinstance(c[0], list):
                    alt_inlines = c[0]
                else:
                    alt_inlines = []
                s, w = count_inlines(alt_inlines)
                total_syllables += s
                total_words += w

        elif t == "Code":
            continue

        elif t in ("Space", "SoftBreak", "LineBreak"):
            continue

        elif t == "RawInline":
            if isinstance(c, list) and len(c) == 2:
                fmt, raw = c
                if fmt == "html" and raw.lstrip().lower().startswith("<iframe"):
                    continue
            continue

        else:
            continue

    return total_syllables, total_words


def count_blocks(blocks):
    """Count (syllables, words) over a list of block elements."""
    total_syllables = 0
    total_words = 0

    for blk in blocks:
        t = blk["t"]
        c = blk.get("c")

        if t == "Div":
            # c = [attr, [blocks...]]
            attr, inner_blocks = c
            identifier = attr[0]
            classes = attr[1] or []

            # Skip navigation and external refs
            if identifier == "quarto-navigation-envelope":
                continue
            if "external-refs" in classes:
                continue

            s, w = count_blocks(inner_blocks)
            total_syllables += s
            total_words += w

        elif t in ("Para", "Plain"):
            inlines = c
            s, w = count_inlines(inlines)
            total_syllables += s
            total_words += w

        elif t == "Header":
            inlines = c[2]
            s, w = count_inlines(inlines)
            total_syllables += s
            total_words += w

        elif t == "BlockQuote":
            s, w = count_blocks(c)
            total_syllables += s
            total_words += w

        elif t == "Figure":
            if isinstance(c, list):
                if len(c) >= 3 and isinstance(c[2], list):
                    content_blocks = c[2]
                    s, w = count_blocks(content_blocks)
                    total_syllables += s
                    total_words += w
                else:
                    nested_blocks = [
                        x for x in c
                        if isinstance(x, dict) and "t" in x
                    ]
                    if nested_blocks:
                        s, w = count_blocks(nested_blocks)
                        total_syllables += s
                        total_words += w

        elif t in ("BulletList", "OrderedList"):
            if t == "BulletList":
                items = c
            else:
                items = c[1]
            for item in items:
                s, w = count_blocks(item)
                total_syllables += s
                total_words += w

        elif t == "Table":
            caption = c[0] if isinstance(c, list) and c else None
            long_caption = None
            if isinstance(caption, dict) and caption.get("t") == "Caption":
                _, long_blocks = caption["c"]
                caption_inlines = []
                for b in long_blocks:
                    if b["t"] in ("Para", "Plain"):
                        caption_inlines.extend(b["c"])
                long_caption = caption_inlines

            if long_caption:
                s, w = count_inlines(long_caption)
                total_syllables += s
                total_words += w

        elif t == "RawBlock":
            if isinstance(c, list) and len(c) == 2:
                fmt, raw = c
                if fmt == "html" and raw.lstrip().lower().startswith("<iframe"):
                    continue

        else:
            continue

    return total_syllables, total_words


def count_meta(ast):
    """Count (syllables, words) from title, subtitle, description in meta."""
    meta = ast.get("meta", {})
    total_syllables = 0
    total_words = 0

    def meta_field_inlines(name):
        v = meta.get(name)
        if not v:
            return []
        if v.get("t") == "MetaInlines":
            return v["c"]
        if v.get("t") == "MetaString":
            return [{"t": "Str", "c": v["c"]}]
        return []

    for key in ("title", "subtitle", "description"):
        inlines = meta_field_inlines(key)
        if inlines:
            s, w = count_inlines(inlines)
            total_syllables += s
            total_words += w

    return total_syllables, total_words


def compute_reading_stats_for_ast(ast, lang: str, seconds_per_syllable: float):
    """
    Compute reading stats (syllables, words, seconds, label) from Pandoc AST.

    Returns a dict suitable for the 'reading' field in YAML:
      {
        "secones_per_syllable": ...,
        "syllables": ...,
        "words": ...,
        "seconds": ...,
        "text": "...",
        "label_reading_time": "...",
        "label_word_count": "..."
      }
    """
    meta_syl, meta_words = count_meta(ast)
    body_syl, body_words = count_blocks(ast.get("blocks", []))

    total_syllables = meta_syl + body_syl
    total_words = meta_words + body_words

    total_seconds = total_syllables * seconds_per_syllable
    minutes_raw = total_seconds / 60.0
    minutes_rounded = int(minutes_raw + 0.5)

    hours = minutes_rounded // 60
    minutes = minutes_rounded % 60

    if lang == "tr":
        if hours > 0:
            if minutes > 0:
                label = f"~ {hours} sa {minutes} dk"
            else:
                label = f"~ {hours} sa"
        else:
            label = f"~ {minutes} dk"
        label_reading_time = "Okuma Süresi"
        label_word_count = "Kelime Sayısı"
    else:
        if hours > 0:
            if minutes > 0:
                label = f"~ {hours} h {minutes} min"
            else:
                label = f"~ {hours} h"
        else:
            label = f"~ {minutes} min"
        label_reading_time = "Reading Time"
        label_word_count = "Word Count"

    return {
        "secones_per_syllable": seconds_per_syllable,  # intentionally using the requested key name
        "syllables": int(total_syllables),
        "words": int(total_words),
        "seconds": round(float(total_seconds), 2),
        "text": label,
        "label_reading_time": label_reading_time,
        "label_word_count": label_word_count,
    }


def aggregate_totals_for_paths(
    root: Path,
    qmd_files,
    aggregated_paths,
    lang: str,
    seconds_per_syllable: float
):
    """
    For each path in aggregated_paths (relative to root), sum syllables, words, seconds
    from the *_reading_stats.yml files of qmd_files whose relative path starts
    with that prefix, and write an index_reading_stats.yml into that directory.

    Additionally, compute a aggregated_hash from the child hash values and only
    rewrite the index file if the aggregated_hash changed.
    """
    # Expand patterns inside AGGREGATED_PATHS
    resolved_paths = []

    for prefix in aggregated_paths:
        if "*" in prefix:
            # Resolve glob relative to root
            for p in (root.glob(prefix)):
                if p.is_dir():
                    rel = p.relative_to(root).as_posix()
                    resolved_paths.append(rel)
        else:
            resolved_paths.append(prefix)

    # Remove duplicates and sort
    resolved_paths = sorted(set(resolved_paths))

    for prefix in resolved_paths:
        total_syllables = 0
        total_words = 0
        total_seconds = 0.0
        child_hash_entries = []  # will contain "rel:path:hash" strings

        for qmd in qmd_files:
            rel = qmd.relative_to(root).as_posix()
            # Match files under this prefix directory, e.g. "trial/..." or "trial/testimonies/..."
            if not (rel == prefix or rel.startswith(prefix + "/")):
                continue

            yml_path = stats_yaml_path(qmd)
            existing = load_existing_stats(yml_path)
            if not existing:
                continue

            rt = existing.get("reading") or {}
            total_syllables += int(rt.get("syllables", 0))
            total_words += int(rt.get("words", 0))
            total_seconds += float(rt.get("seconds", 0.0))

            # Collect child hash for aggregate hashing (if present)
            file_hash = existing.get("hash")
            if file_hash:
                child_hash_entries.append(f"{rel}:{file_hash}")

        # If nothing accumulated, skip writing
        if total_syllables == 0 and total_words == 0:
            continue

        # Compute new aggregated_hash from child_hash_entries
        child_hash_entries.sort()
        hasher = hashlib.sha256()
        for entry in child_hash_entries:
            hasher.update(entry.encode("utf-8"))
        aggregated_hash = hasher.hexdigest()

        out_dir = root / prefix
        out_path = out_dir / "index_reading_stats.yml"

        # If existing index file has the same aggregated_hash, skip rewriting
        existing_total = load_existing_stats(out_path)
        if existing_total and existing_total.get("aggregated_hash") == aggregated_hash:
            continue

        # Build label from total_seconds (same logic as compute_reading_stats_for_ast)
        minutes_raw = total_seconds / 60.0
        minutes_rounded = int(minutes_raw + 0.5)

        hours = minutes_rounded // 60
        minutes = minutes_rounded % 60

        if lang == "tr":
            if hours > 0:
                if minutes > 0:
                    label = f"~ {hours} sa {minutes} dk"
                else:
                    label = f"~ {hours} sa"
            else:
                label = f"~ {minutes} dk"
            label_reading_time = "Toplam Okuma Süresi"
            label_word_count = "Toplam Kelime Sayısı"
        else:
            if hours > 0:
                if minutes > 0:
                    label = f"~ {hours} h {minutes} min"
                else:
                    label = f"~ {hours} h"
            else:
                label = f"~ {minutes} min"
            label_reading_time = "Total Reading Time"
            label_word_count = "Total Word Count"

        reading = {
            "secones_per_syllable": seconds_per_syllable,
            "syllables": int(total_syllables),
            "words": int(total_words),
            "seconds": round(float(total_seconds), 2),
            "text": label,
            "label_reading_time": label_reading_time,
            "label_word_count": label_word_count,
        }

        write_index_stats_yaml(out_path, aggregated_hash, lang, reading)


def main():
    global WORD_LOG

    root = Path(os.getenv("QUARTO_PROJECT_DIR", "."))
    lang, seconds_per_syllable = load_quarto_config(root)
    qmd_files = resolve_qmd_files(root, GLOB_PATTERNS, GLOB_NOT_PATTERNS)

    for qmd in qmd_files:
        # Only open tmp word file if logging is enabled
        if ENABLE_WORD_LOGGING:
            tmp_path = qmd.with_name(qmd.stem + "_words.tmp")
            log_file = tmp_path.open("w", encoding="utf-8")
            WORD_LOG = log_file
        else:
            WORD_LOG = None

        yml = stats_yaml_path(qmd)
        if not needs_rebuild(qmd, yml, lang, seconds_per_syllable):
            if ENABLE_WORD_LOGGING:
                log_file.close()
                WORD_LOG = None
            continue

        file_hash = compute_file_hash(qmd, lang, seconds_per_syllable)
        ast = get_pandoc_ast(qmd)
        reading = compute_reading_stats_for_ast(ast, lang, seconds_per_syllable)
        write_stats_yaml(qmd, yml, file_hash, lang, reading)

        if ENABLE_WORD_LOGGING:
            log_file.close()
            WORD_LOG = None

    aggregate_totals_for_paths(root, qmd_files, AGGREGATED_PATHS, lang, seconds_per_syllable)


if __name__ == "__main__":
    main()

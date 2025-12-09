#!/usr/bin/env python3
# ../shared/python/precompute_reading_stats.py

import sys
import os
import re
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import yaml  # PyYAML


# from zemberek_lemmatizer import lemma_func
# from zemberek_noun_phrase_filter import noun_phrase_filter
from pandoc_ast import PandocAST
from wordcloud_ngrams import (
    STOPWORDS,
    export_ngram_files_from_tokens,
)

SECONDS_PER_SYLLABLE = 0.2

# Phrases / words to remove from n-gram text (all lowercase)
PHRASES_TO_REMOVE = [
    "madde", "sanık", "sanığın", "sanıklar", "sanıkların",
    "maddesinde", "maddesindeki", "maddesinin", "maddesi",
    "sayılı", "XX", "plakalı",
    "defendant", "defendants", "article", "articles",
]

# Glob patterns relative to PROJECT_ROOT
GLOB_PATTERNS = [
    "test/*/*.qmd",
    "trial/judgment.qmd",
    "trial/defenses/*/*.qmd",
    "trial/testimonies/suspect/*/testimony.qmd",
    "trial/testimonies/witness/*.qmd",
    "blog/posts/*/*/index.qmd",
]

GLOB_NOT_PATTERNS = [
    "test/pages/ref-test.qmd",
    "trial/defenses/*/index.qmd",
    "trial/testimonies/witness/index.qmd"
]

# List of paths for totals
AGGREGATED_PATHS = [
    "test",
    "trial",
    "trial/testimonies",
    "trial/testimonies/suspect",
    "trial/testimonies/witness",
    "trial/defenses",
    "trial/defenses/*",
    "blog",
    "blog/posts/*"
]

def collect_glob(root: Path, patterns):
    """Return a list of Path objects matching given glob patterns."""
    out = []
    for pat in patterns:
        out.extend(root.glob(pat))
    return out


def format_reading_label(seconds: int, lang: str) -> str:
    """
    Given rounded total minutes, return a formatted reading time label.
    E.g. "~ 1 day 2 h 5 min" or "~ 2 gün 3 sa 10 dk"
    """
    minutes_rounded = int(seconds / 60.0 + 0.5)
    days = minutes_rounded // (60 * 24)
    rem_minutes = minutes_rounded % (60 * 24)
    hours = rem_minutes // 60
    minutes = rem_minutes % 60

    if lang == "tr":
        units = [("gün", days), ("sa", hours), ("dk", minutes)]
    else:
        units = [("day", days), ("h", hours), ("min", minutes)]

    # Keep only non-zero components, in order
    parts = [f"{value} {label}" for label, value in units if value > 0]

    # If everything is zero (çok kısa metin), en azından 0 dakika göster
    if not parts:
        label_min = units[-1][0]
        parts = [f"0 {label_min}"]

    return "~ " + " ".join(parts)


def resolve_qmd_files(root: Path, include_patterns, exclude_patterns):
    include = collect_glob(root, include_patterns)
    exclude = collect_glob(root, exclude_patterns)
    # Set difference
    final = sorted(set(include) - set(exclude))
    return final


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


def build_reading_dict(
    syllables: int,
    words: int,
    seconds_per_syllable: float,
    lang: str,
) -> dict:
    """
    Build the 'reading' dict for YAML, given counts and language.
    """
    total_seconds = syllables * seconds_per_syllable
    label = format_reading_label(total_seconds, lang)

    if lang == "tr":
        label_reading_time = "Okuma Süresi"
        label_word_count = "Kelime Sayısı"
    else:
        label_reading_time = "Reading Time"
        label_word_count = "Word Count"

    return {
        "seconds_per_syllable": seconds_per_syllable,  # intentionally keep this key
        "syllables": int(syllables),
        "words": int(words),
        "seconds": round(float(total_seconds), 2),
        "text": label,
        "label_reading_time": label_reading_time,
        "label_word_count": label_word_count,
    }

def write_aggregated_stats_yaml(
    yml_path: Path,
    aggregated_hash: str,
    lang: str,
    reading: dict,
):
    """
    Write aggregate index_reading_stats.yml in the new schema **only if**
    aggregated_hash changed.

    aggregated_hash: ...
    generated_at: ...
    language: ...
    type: aggregated_stat
    reading: { ... }
    """
    # If file exists and hash is the same, do not rewrite
    existing = load_existing_stats(yml_path)
    if existing and existing.get("aggregated_hash") == aggregated_hash:
        return

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

        # Build label from total_seconds (same logic as compute_reading_stats_for_ast)
        label = format_reading_label(total_seconds, lang)
        
        if lang == "tr":
            label_reading_time = "Toplam Okuma Süresi"
            label_word_count = "Toplam Kelime Sayısı"
        else:
            label_reading_time = "Total Reading Time"
            label_word_count = "Total Word Count"

        reading = {
            "seconds_per_syllable": seconds_per_syllable,
            "syllables": int(total_syllables),
            "words": int(total_words),
            "seconds": round(float(total_seconds), 2),
            "text": label,
            "label_reading_time": label_reading_time,
            "label_word_count": label_word_count,
        }

        write_aggregated_stats_yaml(out_path, aggregated_hash, lang, reading)


def main():

    root = Path(os.getenv("QUARTO_PROJECT_DIR", "."))
    lang, seconds_per_syllable = load_quarto_config(root)
    qmd_files = resolve_qmd_files(root, GLOB_PATTERNS, GLOB_NOT_PATTERNS)

    for qmd in qmd_files:
        yml = stats_yaml_path(qmd)
        if not needs_rebuild(qmd, yml, lang, seconds_per_syllable):
            continue
        # print(qmd)
        file_hash = compute_file_hash(qmd, lang, seconds_per_syllable)
    
        # Use PandocAST to compute counts
        ast_obj = PandocAST(qmd, seconds_per_syllable=seconds_per_syllable,
                            focus_blocks=["word-cloud"],
                            require_focus=False)

        reading = build_reading_dict(
            syllables=ast_obj.syllable_count,
            words=ast_obj.word_count,
            seconds_per_syllable=seconds_per_syllable,
            lang=lang,
        )
  
        write_stats_yaml(qmd, yml, file_hash, lang, reading)

        if ast_obj.word_cloud:
          # 1) Get full text as a single string (punctuation stripped)
          raw_text = ast_obj.to_string(punct=False, lower=True)
    
          # 3) Remove specific phrases (single or multi-word)
          #    We match them as whole-phrase tokens using whitespace boundaries:
          #    (?<!\S)phrase(?!\S)  ≈ phrase surrounded by start/end or whitespace
          for phrase in PHRASES_TO_REMOVE:
              pattern = rf"(?<!\S){re.escape(phrase)}(?!\S)"
              raw_text = re.sub(pattern, " ", raw_text)
    
          tokens = raw_text.split(" ") if raw_text else []
            
          # Export n-gram frequency files (currently only unigrams -> *_words.txt)
          export_ngram_files_from_tokens(
              qmd_path=qmd,
              tokens=tokens,
              stopwords=STOPWORDS,
              max_ngram=0,                    # later you can set 2 or 3 for bi/tri-grams
              lemma_func=None,                # lemma_func
              filter_func=None,               # noun_phrase_filter
              min_count_per_n={1: 1, 2: 2, 3: 2, 4: 2},  # frequency threshold per n
              top_k=100,               # top 200 terms
              use_wordcloud=True,          # veya False
              wordcloud_kwargs={
                  "collocations": False,
                  "normalize_plurals": False,
                  # "background_color": "white", ...
              },
          )

    aggregate_totals_for_paths(root, qmd_files, AGGREGATED_PATHS,
                               lang, seconds_per_syllable)


if __name__ == "__main__":
    main()

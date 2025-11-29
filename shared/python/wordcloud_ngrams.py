#!/usr/bin/env python3
# ../shared/python/wordcloud_ngrams.py

from __future__ import annotations

import json
from pathlib import Path
from collections import Counter
from typing import Any, Callable, Dict, Iterable, List, Optional, Sequence, Tuple

import re

COMPRESSED = True  # Whether to minify JSON output files

# Shared Turkish stopwords (you can extend this)
TURKISH_STOPWORDS: set[str] = {
    "ve", "veya", "ile", "da", "dan", "de", "den", "mi",
    "bir", "bu", "şu", "o", "i", "ise", "göre", "a", "e", "nin",
    "ama", "fakat", "in", "ın", "nın", "adet", "ne", "nun",
    "için", "gibi", "daha", "çok", "yani", "biz", "ki", "ı", "mu",
    "çünkü", "ancak", "her", "hiç", "bazı", "opr", "ya",
}

# Proper-name exceptions: will be forced to Title-case in tokens
PROPER_NAME_EXCEPTIONS = {
    "Narin",
    "Nevzat",
    "Arif",
    "Enes",
    "Yüksel",
    "Salim",
    "Güran",
    "Bahtiyar",
    "Diyarbakır",
    "Bağlar",
    "Eğertutmaz"
    # extend as needed
}

def turkish_upper(text: str) -> str:
    """
    Unicode-aware Turkish upper-case conversion.
    Correct mappings:
      ı -> I
      i -> İ
    """
    return text.replace("ı", "I").replace("i", "İ").upper()


def turkish_lower2(text: str) -> str:
    """
    Unicode-aware Turkish lower-case conversion.
    Correct mappings:
      I -> ı
      İ -> i

    If the whole token is already ALL CAPS (e.g. 'TCK'),
    we keep it as is and do NOT lowercase.
    """
    return text.replace("I", "ı").replace("İ", "i").lower()


# Map from lower-case form → desired Title-case form
PROPER_NAME_MAP = {
    turkish_lower2(name): name for name in PROPER_NAME_EXCEPTIONS
}


def turkish_lower(text: str) -> str:
    """
    Unicode-aware Turkish lower-case conversion.
    Correct mappings:
      I -> ı
      İ -> i

    If the whole token is already ALL CAPS (e.g. 'TCK'),
    we keep it as is and do NOT lowercase.
    """
    text_left = text.split("’", 1)[0].split("'", 1)[0]
    if text_left == turkish_upper(text_left):
        return text

    return turkish_lower2(text)


def preprocess_tokens(
    tokens: Sequence[str],
    *,
    lowercase: bool = True,
) -> List[str]:
    """
    Basic cleanup for tokens before n-gram processing.

    - Optionally lowercases.
    - Strips surrounding whitespace.
    - Drops tokens that are only punctuation or digits.
    NOTE: This function does NOT apply stopwords. Stopwords are handled
    in the n-gram logic (hybrid model).
    """
    cleaned: List[str] = []
    for tok in tokens:
        t = tok.strip()
        if not t:
            continue
        if lowercase:
            t = turkish_lower(t)

        # Drop pure digits or digit-like tokens
        if re.fullmatch(r"[\d/.:,-]+", t):
            continue

        # Drop tokens without any letter (e.g., ":", "...")
        if not re.search(r"[a-zA-ZğüşöçıİĞÜŞÖÇ]", t):
            continue

        cleaned.append(t)
    return cleaned


def generate_ngrams(tokens: Sequence[str], n: int) -> List[Tuple[str, ...]]:
    """
    Generate consecutive n-grams as tuples of tokens.
    Example: ["a", "b", "c"], n=2 -> [("a","b"), ("b","c")]
    """
    if n <= 0:
        raise ValueError("n must be >= 1")
    return [tuple(tokens[i : i + n]) for i in range(len(tokens) - n + 1)]


def default_ngram_filter(
    ngram: Tuple[str, ...],
    *,
    stopwords: Optional[Iterable[str]] = None,
) -> bool:
    """
    Default filter for n-grams (hybrid stopword model).

    Rules:
    - For unigrams (n=1): drop if the token is in stopwords.
    - For n>1:
        - drop if ALL tokens are stopwords.
        - otherwise keep (this allows internal stopwords, e.g. "suçun işlendiği").
    """
    sw = set(stopwords or [])
    n = len(ngram)

    if n == 1:
        return ngram[0] not in sw

    # n > 1: keep if at least one token is not a stopword
    return not all(tok in sw for tok in ngram)


def get_org_upper_tokens(tokens: Sequence[str]) -> set[str]:
  # 1.a) ALL-CAPS bookkeeping için önce adayları normalize et
  # Örnek: "CMK’nun" -> "CMK", "TCK'nin" -> "TCK"
  caps_candidates: list[str] = []
  for tok in tokens:
      t = tok.strip()
      if not t:
          continue
  
      # Önce Türkçe apostrof ’ ile böl
      base = t.split("’", 1)[0]
      # Sonra gerekirse normal apostrof ' ile de böl
      base = base.split("'", 1)[0]
  
      base = base.strip()
      if base:
        caps_candidates.append(base)
  
  # 1.b) ALL-CAPS olanları seç (TCK, CMK vs.)
  original_upper_tokens = {
      t for t in caps_candidates
      if t == turkish_upper(t)
  }
  
  # 1.c) Lower-case ikizi varsa (örn. "cmk") onları hariç tut
  lower_set = {turkish_lower2(t) for t in caps_candidates}
  
  return {
      tok for tok in original_upper_tokens
      if turkish_lower2(tok) not in caps_candidates
  }


def adjust_proper_names(tokens: Sequence[str]) -> List[str]:
    """
    Apply proper-name mapping to a list of tokens.
    """
    adjusted_tokens: List[str] = []
    for t in tokens:
        key = turkish_lower2(t)
        if key in PROPER_NAME_MAP:
            adjusted_tokens.append(PROPER_NAME_MAP[key])
        else:
            adjusted_tokens.append(t)
    return adjusted_tokens


def remove_apostrophes_from_tokens(tokens: Sequence[str]) -> List[str]:
    """
    Remove Turkish apostrophes and trailing suffixes from tokens.
    E.g. "TCK’nin" -> "TCK"
    """
    cleaned_tokens: List[str] = []
    for t in tokens:
        base = t.split("’", 1)[0].split("'", 1)[0]
        cleaned_tokens.append(base)
    return cleaned_tokens


def compute_ngram_frequencies(
    tokens: Sequence[str],
    *,
    max_ngram: int = 1,
    top_k: int = 200,
    stopwords: Optional[Iterable[str]] = None,
    lemma_func: Optional[Callable[[str], str]] = None,
    filter_func: Optional[
        Callable[[Tuple[str, ...]], bool]
    ] = None,
    min_count_per_n: Optional[Dict[int, int]] = None,
    use_wordcloud: bool = False,
    wordcloud_kwargs: Optional[Dict[str, Any]] = None,
) -> Tuple[Dict[int, Dict[str, int]], Optional[Dict[str, int]]]:
    """
    Core n-gram frequency computation.

    Returns
    -------
     (freqs_by_n, wc_unigrams)
 
     freqs_by_n: Dict[int, Dict[str, int]]
         Example: {1: {"narin": 12, "olay": 7}, 2: {"narin güran": 4}, ...}
     wc_unigrams: Optional[Dict[str, int]]
         If use_wordcloud=True, unigrams computed by WordCloud.process_text.
         Otherwise None.
    """
    if max_ngram < 1:
      max_ngram = 0

    sw = set(stopwords or [])
    predicates = filter_func or (lambda ng: default_ngram_filter(ng, stopwords=sw))
    min_counts = min_count_per_n or {}

    # 1) Basic preprocessing (punctuation, digits, casing)
    pre_tokens = preprocess_tokens(tokens, lowercase=True)

    # 1.a) Restore ALL-CAPS tokens (e.g. TCK) bookkeeping (used only for WordCloud casing logic)
    original_upper_tokens = get_org_upper_tokens(pre_tokens)

    # 1.b) Proper-name exception handling:
    #     If a token's lower-case form is in PROPER_NAME_MAP, replace it with the
    #     configured Title-case form. This affects all downstream n-grams.
    pre_tokens = adjust_proper_names(pre_tokens)

    # 2) Lemmatization (if any)
    if lemma_func is not None:
        lemma_tokens = [lemma_func(t) for t in pre_tokens]
    else:
        lemma_tokens = pre_tokens

    # 3) Optional: WordCloud unigrams (for judgment_words.txt)
    wc_unigrams: Optional[Dict[str, int]] = None
    if use_wordcloud:
        try:
            from wordcloud import WordCloud
        except ImportError as e:
            raise RuntimeError(
                "use_wordcloud=True but the 'wordcloud' package is not installed."
            ) from e

        text_for_wc = " ".join(lemma_tokens)

        wc_params: Dict[str, Any] = dict(wordcloud_kwargs or {})
        # If caller did not pass explicit stopwords, use our shared set
        if stopwords is not None and "stopwords" not in wc_params:
            wc_params["stopwords"] = sw

        wc = WordCloud(**wc_params)
        wc_unigrams = wc.process_text(text_for_wc)  # {word: freq}

        # Post-process WordCloud output:
        # 1) ALL-CAPS geri yükle (original_upper_tokens)
        # 2) Proper-name Title-case map uygula (PROPER_NAME_MAP)
        if wc_unigrams is not None:
            adjusted: Dict[str, int] = {}
            for term, count in wc_unigrams.items():
                new_key = term

                # 1) ALL-CAPS restore: wc "tck" üretmişse ve
                #    orijinal metinde "TCK" varsa → "TCK"
                candidate_caps = turkish_upper(term)
                if candidate_caps in original_upper_tokens:
                    new_key = candidate_caps
                else:
                    # 2) Proper-name mapping: "narin" -> "Narin" vb.
                    lower_key = turkish_lower2(term)
                    mapped = PROPER_NAME_MAP.get(lower_key)
                    if mapped is not None:
                        new_key = mapped

                adjusted[new_key] = adjusted.get(new_key, 0) + count

            # top_k uygulaması burada
            wc_unigrams = dict(
                sorted(adjusted.items(), key=lambda kv: kv[1], reverse=True)[:top_k]
            )

    result: Dict[int, Dict[str, int]] = {}

    for n in range(1, max_ngram + 1):
        tokens_for_ngrams = lemma_tokens if n > 2 else remove_apostrophes_from_tokens(lemma_tokens)
        ngrams = generate_ngrams(tokens_for_ngrams, n)
        counter: Counter[str] = Counter()

        for ng in ngrams:
            # Hybrid stopword + n-gram filter
            if not predicates(ng):
                continue

            phrase = " ".join(ng)
            counter[phrase] += 1

        # Apply minimum count threshold for this n
        threshold = min_counts.get(n, 1)
        freq_dict = {k: v for k, v in counter.items() if v >= threshold}


        if freq_dict:
            # Proper-name mapping on phrase level:
            # "narin güran" → "Narin Güran" (eğer map'te varsa)
            adjusted: Dict[str, int] = {}

            for phrase, count in freq_dict.items():
                tokens = phrase.split()
                mapped_tokens: List[str] = []

                for tok in tokens:
                    lower_key = turkish_lower2(tok)
                    mapped = PROPER_NAME_MAP.get(lower_key)
                    if mapped is not None:
                        mapped_tokens.append(mapped)
                    else:
                        mapped_tokens.append(tok)

                new_phrase = " ".join(mapped_tokens)
                adjusted[new_phrase] = adjusted.get(new_phrase, 0) + count

            # Sort and apply top_k
            freq_dict = dict(
                sorted(adjusted.items(), key=lambda kv: kv[1], reverse=True)[:top_k]
            )
            result[n] = freq_dict

    return result, wc_unigrams


def write_words_file(
    base_qmd_path: Path,
    freqs: Dict[str, int],
    compressed: bool = True
) -> None:
    """
    Write BASENAME_words.json from a flat frequency dict.
    """
    stem = base_qmd_path.stem
    out_path = base_qmd_path.with_name(f"{stem}_words.json")

    items = [
        {"text": term, "value": count}
        for term, count in freqs.items()
    ]

    with out_path.open("w", encoding="utf-8") as f:
        if compressed:
            # Minified JSON
            json.dump(
                items,
                f,
                ensure_ascii=False,
                separators=(",", ":")   # no extra whitespace
            )
        else:
            # Pretty-printed JSON
            json.dump(
                items,
                f,
                ensure_ascii=False,
                indent=2
            )


def write_ngram_frequency_files(
    base_qmd_path: Path,
    freqs_by_n: Dict[int, Dict[str, int]]
) -> None:
    """
    Write frequency files for each n.

    Naming convention:
      - n == 1 -> BASENAME_words.txt
      - n >= 2 -> BASENAME_{n}gram.txt

    File format (one term per line):
      term,count
    """
    stem = base_qmd_path.stem

    for n, freq in freqs_by_n.items():
        if not freq:
            continue

        out_path = base_qmd_path.with_name(f"{stem}_{n}gram.txt")

        # Sort by descending frequency
        items = sorted(freq.items(), key=lambda kv: kv[1], reverse=True)

        with out_path.open("w", encoding="utf-8") as f:
            for term, count in items:
                f.write(f"{term},{count}\n")


def export_ngram_files_from_tokens(
    qmd_path: Path,
    tokens: Sequence[str],
    *,
    stopwords: Optional[Iterable[str]] = None,
    max_ngram: int = 1,
    lemma_func: Optional[Callable[[str], str]] = None,
    filter_func: Optional[Callable[[Tuple[str, ...]], bool]] = None,
    min_count_per_n: Optional[Dict[int, int]] = None,
    top_k: int = 200,
    use_wordcloud: bool = False,
    wordcloud_kwargs: Optional[Dict[str, Any]] = None,
) -> Dict[int, Dict[str, int]]:
    """
    High-level helper for integration with PandocAST.

    use_wordcloud:
        If True, judgment_words.txt is built using Python WordCloud,
        and our own n-gram pipeline writes BASENAME_1gram.txt, 2gram, 3gram, ...

    wordcloud_kwargs:
        Optional kwargs passed to WordCloud(...) when use_wordcloud=True.
    """
    freqs_by_n, wc_unigrams = compute_ngram_frequencies(
        tokens=tokens,
        max_ngram=max_ngram,
        top_k=top_k,
        stopwords=stopwords,
        lemma_func=lemma_func,
        filter_func=filter_func,
        min_count_per_n=min_count_per_n,
        use_wordcloud=use_wordcloud,
        wordcloud_kwargs=wordcloud_kwargs,
    )

    # 1) judgment_words.txt
    # use_wordcloud=True  → Python WordCloud output
    # use_wordcloud=False → our own 1-gram frequencies
    if use_wordcloud and wc_unigrams is not None:
        words_freq = wc_unigrams
    else:
        words_freq = freqs_by_n.get(1, {})

    if words_freq:
        write_words_file(
            qmd_path,
            words_freq,
            compressed=COMPRESSED
        )

    # 2) judgment_1gram.txt, 2gram, 3gram, ...
    write_ngram_frequency_files(qmd_path, freqs_by_n)
    return freqs_by_n

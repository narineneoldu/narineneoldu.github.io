#!/usr/bin/env python3
# ../shared/python/pandoc_ast.py

from __future__ import annotations

import subprocess
import json
import re
import string
from pathlib import Path
from typing import Any, Dict, List, Sequence, Union, Optional

# Default reader extensions used for Quarto / Pandoc markdown
PANDOC_READER_FORMAT = (
    "markdown"
    "+yaml_metadata_block"
    "+fenced_divs"
    "+link_attributes"
    "+bracketed_spans"
    "+pipe_tables"
    "+grid_tables"
    "+raw_html"
)

# Default vowel set (Turkish-focused, also valid for English)
TURKISH_VOWELS = set("aeıioöuüâîûAEIİOÖUÜ")

# Translation table to strip ASCII punctuation in to_string(punct=False)
# + "’"
_STR_PUNCT = string.punctuation
# _PUNCT_TRANSLATION = str.maketrans("", "", string.punctuation)


class PandocAST:
    """
    Wrapper around a Pandoc JSON AST that can compute:
    - syllable count
    - word count
    - approximate reading time (seconds)

    Additionally, it stores the counted words and can expose them as a string.
    
    focus_blocks:
        Optional list of ids / class names to focus on.
        If provided, we will try to count only the content inside
        Divs whose identifier or classes match any of these.

    require_focus:
        If True and no matching focus blocks are found,
        the body is not counted at all (0 words, 0 syllables).
        If False and no focus blocks are found,
        we fall back to counting the whole body as usual.
    """

    def __init__(
        self,
        path: Union[str, Path],
        seconds_per_syllable: float = 0.2,
        vowels: Sequence[str] = tuple(TURKISH_VOWELS),
        *,
        focus_blocks: Optional[Sequence[str]] = None,
        require_focus: bool = False,
    ) -> None:
        """
        Initialize the object, load AST and compute statistics.

        :param path: Path to a .qmd / markdown file (str or Path).
        :param seconds_per_syllable: Reading speed in seconds per syllable.
        :param vowels: Iterable of characters treated as vowels.
        :param focus_blocks: Optional list of block ids/classes to focus on.
        :param require_focus: See class docstring.
        """
        self._path = Path(path)
        self._seconds_per_syllable = float(seconds_per_syllable)
        self._vowel_set = set(vowels)

        # Focus configuration
        self._focus_blocks = set(focus_blocks or [])
        self._require_focus = bool(require_focus)

        # Internal storage for AST and stats
        self._ast: Dict[str, Any] = self._load_ast()
        self._syllable_count: int = 0
        self._word_count: int = 0
        self._reading_time: float = 0.0  # seconds

        # Internal storage for words that were actually counted
        self._words: List[str] = []

        # Compute all stats immediately
        self._compute_counts()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    @property
    def path(self) -> Path:
        """Return the source file path."""
        return self._path

    @property
    def seconds_per_syllable(self) -> float:
        """Return the reading speed in seconds per syllable."""
        return self._seconds_per_syllable

    @property
    def ast(self) -> Dict[str, Any]:
        """Return the Pandoc JSON AST."""
        return self._ast

    @property
    def syllable_count(self) -> int:
        """Return the total syllable count."""
        return self._syllable_count

    @property
    def word_count(self) -> int:
        """Return the total word count."""
        return self._word_count

    @property
    def reading_time(self) -> float:
        """Return the approximate reading time in seconds."""
        return self._reading_time

    @property
    def word_cloud(self) -> bool:
        """Return True if any focus blocks are defined for word cloud."""
        default = False
        meta = self._ast.get("meta", {})
        node = meta.get("word-cloud")
        if not node:
            return default

        t = node.get("t")
        c = node.get("c")

        # Pandoc JSON: MetaBool
        if t == "MetaBool":
            return bool(c)

        # Eğer string olarak yazıldıysa (WordCloud: "true"/"false")
        if t == "MetaString":
            val = str(c).strip().lower()
            if val in {"true", "yes", "on", "1"}:
                return True
            if val in {"false", "no", "off", "0"}:
                return False

        return default

    def to_list(self, punct: bool = True, lower: bool = False) -> List[str]:
        if punct:
            if not lower:
                # Return raw words exactly as they were counted
                return list(self._words)
            lower_words: List[str] = []
            for w in self._words:
                lower_words.append(self._turkish_lower(w))
            return lower_words
        else:
            cleaned: List[str] = []
    
            # Regex: tüm punctuation karakterlerini boşlukla değiştir
            punct_regex = r"[{}]+".format(re.escape(_STR_PUNCT))
    
            for w in self._words:
                # 1) punctuation karakterlerini boşluk yap
                w2 = re.sub(punct_regex, " ", w)
    
                # 2) birden fazla boşluk toplanır
                w2 = re.sub(r"\s+", " ", w2).strip()

                # 3) boşluklara göre split et
                for part in w2.split():
                    if part:
                        cleaned.append(self._turkish_lower(part))

            return cleaned

    def to_string(self, punct: bool = True, lower: bool = False) -> str:
        """
        Return the counted words as a single string.

        :param punct: If True, return words with punctuation preserved.
                      If False, strip ASCII punctuation characters.
        """
        return " ".join(self.to_list(punct=punct, lower=lower))

    # ------------------------------------------------------------------
    # Internal: Pandoc IO
    # ------------------------------------------------------------------

    @classmethod
    def _turkish_upper(cls, text: str) -> str:
        """
        Unicode-aware Turkish upper-case conversion.
        Correct mappings:
          ı -> I
          i -> İ
        """
        return text.replace("ı", "I").replace("i", "İ").upper()

    @classmethod
    def _turkish_lower(cls, text: str) -> str:
        """
        Unicode-aware Turkish lower-case conversion.
        Correct mappings:
          I -> ı
          İ -> i
        """
        text_left = text.split("’", 1)[0].split("'", 1)[0]
        if text_left == cls._turkish_upper(text_left):
            return text

        return text.replace("I", "ı").replace("İ", "i").lower()

    def _load_ast(self) -> Dict[str, Any]:
        """
        Run pandoc on the file and return its JSON AST as a Python dict.
        """
        cmd = [
            "pandoc",
            str(self._path),
            "-f",
            PANDOC_READER_FORMAT,
            "-t",
            "json",
        ]
        result = subprocess.run(cmd, check=True, capture_output=True)
        return json.loads(result.stdout.decode("utf-8"))

    # ------------------------------------------------------------------
    # Internal: core counters
    # ------------------------------------------------------------------

    def _compute_counts(self) -> None:
        """
        Compute syllable_count, word_count, and reading_time from the AST.
        """
        blocks = self._ast.get("blocks", [])
        
        # Eğer focus_blocks tanımlı değilse,
        # meta ile birlikte direkt tüm gövdeyi say
        if not self._focus_blocks:
            meta_syl, meta_words = self._count_meta(self._ast)
            body_syl, body_words = self._count_blocks(blocks)
            self._syllable_count = meta_syl + body_syl
            self._word_count = meta_words + body_words
        else:
            # Önce focus Div/Section içeriğini çıkart
            focus_blocks = self._extract_focus_blocks(blocks)

            if focus_blocks:
                # Sadece bu blokların içeriğini say
                body_syl, body_words = self._count_blocks(focus_blocks)
            else:
                # Hiç focus bloğu yok
                if self._require_focus:
                    body_syl, body_words = 0, 0
                else:
                    # Eski davranış: tüm gövdeyi say
                    body_syl, body_words = self._count_blocks(blocks)

            self._syllable_count = body_syl
            self._word_count = body_words

        self._reading_time = self._syllable_count * self._seconds_per_syllable

    # ------------------------------------------------------------------
    # Focus selection helpers
    # ------------------------------------------------------------------

    def _matches_focus(self, ident: str, classes: Sequence[str]) -> bool:
        """
        Return True if Div identifier or any class matches focus_blocks.
        """
        if not self._focus_blocks:
            return False
        if ident and ident in self._focus_blocks:
            return True
        for cls_name in classes or []:
            if cls_name in self._focus_blocks:
                return True
        return False

    def _extract_focus_blocks(
        self,
        blocks: Sequence[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        """
        Traverse top-level blocks and collect inner blocks of any Div
        whose id / classes match focus_blocks.

        For your pattern:

            :::wordcloud
            # Heading
            ...
            :::

        AST tarafında bu, id "delillerin-deger..." ve
        classes ["wordcloud", "level1"] olan bir Div (Section) olacak.

        Bu metot, o Div'in içindeki block listesini toplayıp döndürüyor.
        """
        collected: List[Dict[str, Any]] = []

        for blk in blocks:
            if blk.get("t") == "Div":
                attr, inner_blocks = blk["c"]
                ident = attr[0]
                classes = attr[1] or []

                if self._matches_focus(ident, classes):
                    # Bu Div bir focus bloğu → sadece içeriğini al
                    collected.extend(inner_blocks)
                else:
                    # İçinde başka Div'ler olabilir, içlerine bak
                    # (örneğin nested wordcloud vs.)
                    nested = self._extract_focus_blocks(inner_blocks)
                    collected.extend(nested)

            # Diğer block türlerinin içine Div koyma ihtimalin düşük;
            # sade ve kontrollü tutmak için şimdilik sadece Div içinde arıyoruz.

        return collected

    # ------------------------------------------------------------------
    # Low-level helpers
    # ------------------------------------------------------------------

    def _is_vowel(self, ch: str) -> bool:
        """Return True if the character is treated as a vowel."""
        return ch in self._vowel_set

    @staticmethod
    def _strip_brackets_and_braces(tok: str) -> str:
        """
        Remove curly and square brackets from the whole token.

        This covers cases like {yazdığım yazıda}[1].
        """
        return re.sub(r"[{}\[\]]+", "", tok)

    @staticmethod
    def _normalize_for_vowel_check(tok: str) -> str:
        """Remove digits before vowel check."""
        return re.sub(r"\d+", "", tok)

    def _has_vowel(self, tok: str) -> bool:
        """Return True if token contains at least one vowel (after digit removal)."""
        tok_clean = self._normalize_for_vowel_check(tok)
        for ch in tok_clean:
            if self._is_vowel(ch):
                return True
        return False

    @staticmethod
    def _is_all_digits(tok: str) -> bool:
        """Return True if token is composed only of digits."""
        tok = tok.strip()
        return bool(tok) and tok.isdigit()

    def _syllables_for_word(self, tok: str) -> int:
        """Approximate syllable count for a single token."""
        tok_clean = self._normalize_for_vowel_check(tok)
        syllables = 0
        prev_vowel = False
        saw_letter = False

        for ch in tok_clean:
            if ch.isalpha():
                saw_letter = True
            v = self._is_vowel(ch)
            if v and not prev_vowel:
                syllables += 1
            prev_vowel = v

        # Handle pure numbers: count them as 1 syllable for timing
        if self._is_all_digits(tok):
            return 1

        # If we saw letters but no vowel, count as 1 (abbreviations, etc.)
        if saw_letter and syllables == 0:
            syllables = 1

        return syllables

    # ------------------------------------------------------------------
    # Token / inline / block counters
    # ------------------------------------------------------------------

    def _count_token(self, tok: str) -> tuple[int, int]:
        """
        Return (syllables, words) contribution of a single raw token.

        Rules:
        - Strip { } [ ] everywhere in the token.
        - If token is all digits -> ignore as a word but timing fallback handled above.
        - Otherwise, remove digits and check if there is any vowel.
          If there is, count as one word and compute syllables.
          If not, ignore as a word.
        """
        # Store the word for later introspection
        self._words.append(tok.strip())
        tok = self._strip_brackets_and_braces(tok)
        tok = tok.strip()

        if not tok:
            return 0, 0

        if self._has_vowel(tok):
            syl = self._syllables_for_word(tok)
            return syl, 1
        else:
            # No vowel after digit removal → ignore as word
            return 0, 0

    def _count_inlines(self, inlines: Sequence[Dict[str, Any]]) -> tuple[int, int]:
        """Count (syllables, words) in a list of Pandoc inlines (JSON AST form)."""
        total_syllables = 0
        total_words = 0

        for el in inlines:
            t = el["t"]
            c = el.get("c")

            if t == "Str":
                text = c
                for tok in text.split():
                    syl, w = self._count_token(tok)
                    total_syllables += syl
                    total_words += w

            elif t in ("Emph", "Strong"):
                inner = c
                s, w = self._count_inlines(inner)
                total_syllables += s
                total_words += w

            elif t == "Span":
                if isinstance(c, list) and len(c) >= 2:
                    inner = c[1]
                    s, w = self._count_inlines(inner)
                    total_syllables += s
                    total_words += w

            elif t == "Quoted":
                if isinstance(c, list) and len(c) == 2:
                    inner = c[1]
                    s, w = self._count_inlines(inner)
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
                    s, w = self._count_inlines(inner)
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
                    s, w = self._count_inlines(alt_inlines)
                    total_syllables += s
                    total_words += w

            elif t == "Code":
                # Skip inline code
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

    def _count_blocks(self, blocks: Sequence[Dict[str, Any]]) -> tuple[int, int]:
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

                s, w = self._count_blocks(inner_blocks)
                total_syllables += s
                total_words += w

            elif t in ("Para", "Plain"):
                inlines = c
                s, w = self._count_inlines(inlines)
                total_syllables += s
                total_words += w

            elif t == "Header":
                inlines = c[2]
                s, w = self._count_inlines(inlines)
                total_syllables += s
                total_words += w

            elif t == "BlockQuote":
                s, w = self._count_blocks(c)
                total_syllables += s
                total_words += w

            elif t == "Figure":
                if isinstance(c, list):
                    if len(c) >= 3 and isinstance(c[2], list):
                        content_blocks = c[2]
                        s, w = self._count_blocks(content_blocks)
                        total_syllables += s
                        total_words += w
                    else:
                        nested_blocks = [
                            x for x in c
                            if isinstance(x, dict) and "t" in x
                        ]
                        if nested_blocks:
                            s, w = self._count_blocks(nested_blocks)
                            total_syllables += s
                            total_words += w

            elif t in ("BulletList", "OrderedList"):
                if t == "BulletList":
                    items = c
                else:
                    items = c[1]
                for item in items:
                    s, w = self._count_blocks(item)
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
                    s, w = self._count_inlines(long_caption)
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

    # ------------------------------------------------------------------
    # Meta counting (title, subtitle, description)
    # ------------------------------------------------------------------

    def _count_meta(self, ast: Dict[str, Any]) -> tuple[int, int]:
        """Count (syllables, words) from title, subtitle, description in meta."""
        meta = ast.get("meta", {})
        total_syllables = 0
        total_words = 0

        def meta_field_inlines(name: str) -> List[Dict[str, Any]]:
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
                s, w = self._count_inlines(inlines)
                total_syllables += s
                total_words += w

        return total_syllables, total_words

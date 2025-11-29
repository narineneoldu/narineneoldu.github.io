# ../shared/python/zemberek_lemmatizer.py

from zemberek import TurkishMorphology

# Create the morphology instance once (expensive object)
_morph = TurkishMorphology.create_with_defaults()


def lemma_func(token: str) -> str:
    """
    Return lemma (root) using Zemberek, but avoid collapsing
    derivationally different words.

    Heuristic:
      - Run full morphological analysis + disambiguation.
      - If dictionary lemma is UNK → return token as is.
      - Inspect the morpheme string:
          * If it contains a derivational boundary '^DB+',
            keep the original surface form (e.g. 'cansız' stays 'cansız').
          * Otherwise, return the dictionary lemma
            (e.g. 'evden' → 'ev').
    """
    try:
        # 1) All possible analyses for the token
        analyses = _morph.analyze(token)
        if not analyses:
            return token

        # 2) Disambiguate in a one-token "sentence"
        sentence = [token]
        sentence_analyses = [analyses]
        disamb = _morph.disambiguate(sentence, sentence_analyses)

        # Python wrapper: best_analysis() returns a list
        best = disamb.best_analysis()[0]

        # 3) If lemma is UNK, keep original token
        lemma = getattr(best.item, "lemma", None)
        if not lemma or lemma == "UNK":
            return token

        # 4) Morphological description string, e.g.:
        #    "can+Noun+A3sg+Pnon+Nom^DB+Adj+Without"
        morph_str = best.format_morpheme_string()

        # 5) If there is any derivational boundary, do NOT reduce to lemma
        #    This prevents 'cansız' and 'canlı' from both collapsing to 'can'.
        if "^DB+" in morph_str:
            return token

        # 6) Purely inflectional: safe to return lemma
        return lemma

    except Exception:
        # On any unexpected failure, fall back gracefully
        return token
      

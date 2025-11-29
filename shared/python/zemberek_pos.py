# ../shared/python/zemberek_pos.py

from zemberek import TurkishMorphology

# Create only once
_morph = TurkishMorphology.create_with_defaults()

# Map Zemberek POS labels → bizim şemamız
_POS_MAP = {
    "Noun": "NOUN",
    "Adj": "ADJ",
    "Adjective": "ADJ",
    "Verb": "VERB",
    "Prop": "PROPN",
    "ProperNoun": "PROPN",
    "Pron": "PRON",
    "Num": "NUM",
    "Adv": "ADV",
}


def _normalize_pos(best) -> str:
    """
    Take a SingleAnalysis object and return an upper-case POS tag
    like: NOUN, ADJ, PROPN, VERB ...

    If cannot determine → "UNK".
    """
    raw = None

    # 1) Try best.item.primary_pos if available
    try:
        if hasattr(best, "item") and hasattr(best.item, "primary_pos"):
            raw = best.item.primary_pos
    except Exception:
        raw = None

    # 2) Fallback: best.primary_pos or best.pos
    if raw is None:
        for attr in ("primary_pos", "pos"):
            if hasattr(best, attr):
                try:
                    raw = getattr(best, attr)
                    break
                except Exception:
                    raw = None

    if raw is None:
        return "UNK"

    # raw genelde bir enum; adını veya kısa formunu string'e çevir
    if hasattr(raw, "name"):
        s = raw.name
    elif hasattr(raw, "short_form"):
        s = raw.short_form
    else:
        s = str(raw)

    # map + upper-case
    return _POS_MAP.get(s, s.upper())


def pos_sequence(tokens):
    """
    Input  : ["diyarbakır", "adli", "emaneti"]
    Output : ["PROPN", "ADJ", "NOUN"]

    If POS cannot be determined → "UNK"
    """
    tags = []
    for tok in tokens:
        try:
            # Analyze + disambiguate as a one-word sentence
            analyses = _morph.analyze(tok)
            sentence = [tok]
            sentence_analyses = [analyses]
            disamb = _morph.disambiguate(sentence, sentence_analyses)

            best_list = disamb.best_analysis()
            if not best_list:
                tags.append("UNK")
                continue

            best = best_list[0]
            tag = _normalize_pos(best)
            tags.append(tag)
        except Exception:
            tags.append("UNK")
    return tags

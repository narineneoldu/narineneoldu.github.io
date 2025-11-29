# ../shared/python/zemberek_noun_phrase_filter.py

from zemberek_pos import pos_sequence


def noun_phrase_filter(ngram):
    """
    Sadece isim tamlaması olabilecek n-gram'ları tut.

    Kurallar (şimdilik):

      n = 2:
        (NOUN, NOUN)
        (ADJ,  NOUN)
        (PROPN, NOUN)
        (PROPN, PROPN)   # Örn: "diyarbakır barosu" gibi durumlar için ekleyebilirsin

      n = 3:
        (PROPN, ADJ,  NOUN)
        (NOUN,  ADJ,  NOUN)
        (ADJ,   NOUN, NOUN)  # Örn: "ağır ceza mahkemesi"

    İstersen yeni pattern'ler ekleyebiliriz.
    """
    tokens = list(ngram)
    tags = pos_sequence(tokens)

    if len(tags) == 2:
        return tuple(tags) in {
            ("NOUN", "NOUN"),
            ("ADJ",  "NOUN"),
            ("PROPN", "NOUN"),
            ("PROPN", "PROPN"),
        }

    if len(tags) == 3:
        return tuple(tags) in {
            ("PROPN", "ADJ",  "NOUN"),
            ("NOUN",  "ADJ",  "NOUN"),
            ("ADJ",   "NOUN", "NOUN"),
        }

    return False

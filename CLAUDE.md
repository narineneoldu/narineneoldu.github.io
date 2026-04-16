# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Proje Özeti

Quarto tabanlı iki dilli (TR/EN) statik website: `narineneoldu.github.io`. Narin Güran davası ile ilgili mahkeme ifadeleri, savunmalar, gerekçeli karar ve blog yazılarını sunar. GitHub Pages ile `docs/` klasöründen yayınlanır.

## Derin Referans: `documentation/`

`documentation/` altında dört architectural overview var. Kapsamlı (150-400 satır) cross-file bilgileri tek-dosya kod yorumlarında verilemediği için oraya yazıldı. Her birinin frontmatter'ında `last-verified` tarihi ve `verified-against-commits` aralığı var — eğer o aralıktan sonra ilgili dosyalarda önemli değişiklik olduysa docs'lara şüpheyle yaklaş ve koda güven.

- **[architecture.md](documentation/architecture.md)** — Build vs deploy, `tr/`↔`en/` ilişkisi, pre/post-render hook zinciri, profile sistemi, known pitfalls (docs/ tracking, silent missing css, timing stabilization)
- **[filter-pipeline.md](documentation/filter-pipeline.md)** — Global filter sırası, lokal filter override'ları (`tr/trial/testimonies/_metadata.yml`), `span_multi` 10-detector dispatch ve priority, skip mekanizmaları
- **[metadata-schemas.md](documentation/metadata-schemas.md)** — `phones`/`plates`/`abbr`/`participant` YAML şemaları, variant üretim algoritması, word boundary asimetrisi, gotcha'lar
- **[extensions.md](documentation/extensions.md)** — 4 custom extension (header-slug, hashtag, date-modified, media-short) + `_testkit`, her birinin amacı, test durumu, `{{< video2 >}}` gibi isim sürprizleri
- **[content-workflow.md](documentation/content-workflow.md)** — Yeni blog yazısı / ifade / tanık ekleme akışları, TR↔EN senkronu, preview ve deploy adımları, yaygın hatalar ve karar ağacı

Sıra: genel sorunda önce CLAUDE.md'deki bu bölümün ilgili pointer'ını oku, oradan ilgili documentation dosyasına git. CLAUDE.md kompakt navigasyon rehberi olarak kalmalı; uzun açıklamalar documentation/'da.

## Build & Preview Komutları

Tüm script'ler `dev` (varsayılan) veya `prod` Quarto profilini kabul eder.

```bash
./build          # Hem TR hem EN site render eder → tr/_site, en/_site
./build-tr       # Sadece TR → tr/_site
./build-en       # Sadece EN → en/_site
./preview-tr     # quarto preview tr (port 7777)
./preview-en     # quarto preview en
./build prod     # Production profile ile render

./shared/bash/deploy.sh   # tr/_site → docs/ rsync (canlıya alma)
```

**Build ≠ deploy**: `./build` sadece `tr/_site`/`en/_site` altında render eder. Canlı site (`narineneoldu.github.io`, `docs/` dizininden yayınlanıyor) güncellenmek için **`deploy.sh`'in ayrıca çalıştırılması gerekir**. `build` script'inin çıktı mesajı `docs/` yazar ama yanıltıcıdır — gerçek deploy yapmaz. Bu ikiye ayırma kasıtlı: kullanıcı iş akışı "birden fazla değişiklik yap + commit'le → hepsi bittiğinde tek seferlik deploy" şeklinde.

**Yaklaşık build süreleri** (lokal, MacPorts Python 3.11, M-serisi Mac):
- TR tek başına: ~130s total (~74s Quarto render + hook'lar)
- EN tek başına: ~100s total (~40s Quarto render + hook'lar)
- `./build` (sequential TR + EN): ~3m 50s

`docs/` klasörü GitHub Pages için kaynak (Settings → Pages → Source: `main` branch, `/docs` path) — `.gitignore` bu dizini kasıtlı olarak dışlamaz. `docs/` sadece `shared/bash/deploy.sh` tarafından güncellenir; `./build` ve `./preview-*` scriptleri `docs/`'a dokunmaz (`tr/_site/` ve `en/_site/`'a yazar). Bu yüzden normal çalışma döngüsünde `docs/` diff gürültüsü oluşmaz — sadece deploy anında değişir ve hemen commit'lenir.

## Lua Extension Testleri

Extension'lar kendi test harness'larına sahiptir (lua + luaunit, shared `_extensions/_testkit` üzerinden):

```bash
_extensions/header-slug/run_tests.sh
_extensions/hashtag/run_tests.sh
_extensions/hashtag/run_perf_guard.sh
```

Tek test çalıştırmak için:
```bash
cd _extensions/header-slug/tests && lua test_slugify.lua
```

## Mimari

### İki Site, Paylaşılan Kaynak

- `tr/` — Türkçe site (canonical), `tr/_quarto.yml` ana config
- `en/` — İngilizce site, `tr/`'den çevrilmiş içerik
- `shared/` — Her iki site tarafından kullanılan Lua filter'ları, Python scriptleri ve bash helper'ları
- `resources/` — Root-level static assets (css/scss/js/images/audio/icons); her iki site root path `/resources/...` ile referans verir
- `docs/` — TR site'in final deploy hedefi (EN, `tr/_site/en/` altında iç içe geçer)

**Build akışı** (`tr/_quarto.yml` pre/post-render hook'ları):
1. `shared/bash/clean.sh` — geçici render artifact'lerini temizler
2. `shared/python/precompute_reading_stats.py` — okuma süresi istatistiklerini hesaplar
3. `shared/python/render_timer.py start` — render süresini ölçer
4. Quarto render
5. `shared/bash/sync-tr.sh` — `en/_site/` → `tr/_site/en/` rsync (iç içe dil dağıtımı)
6. `shared/python/render_timer.py end`

TR site rendering'den sonra `shared/bash/deploy.sh` opsiyonel olarak `tr/_site/` → `docs/` senkronize eder.

### Quarto Extensions (`_extensions/`)

Yerel, custom extension'lar (hepsi Lua filter/shortcode):

- **header-slug** — Başlıklardan Türkçe-aware slug üretir (test coverage'lı)
- **hashtag** — `#etiket` → sosyal medya linkine dönüştürür (`auto-scan: true`, `default-provider: x`); performans regression guard ile
- **date-modified** — Dosya değişiklik tarihlerini sayfa footer'ına enjekte eder
- **media-short** — `{{< audio >}}`, `{{< video2 >}}`, `{{< jump >}}` shortcode'ları (plyr entegrasyonu). **Not**: `shortcode-video.lua` dosyası tanımladığı shortcode'u `video2` adıyla export eder (`video` adı Quarto built-in'i ile çakışmaktan kaçınmak için). Dosya adıyla shortcode adı kasıtlı olarak farklıdır.
- **_testkit** — Paylaşılan luaunit bootstrap; extension test'leri bunu tüketir

### Shared Lua Filters (`shared/lua/`)

`tr/_quarto.yml`'deki `filters:` sıralaması önemlidir — her filter pandoc AST üzerinde çalışır:

```
filters:
  - date-modified
  - hashtag
  - header-slug
  - ../shared/lua/render_start_timer.lua
  - ../shared/lua/span_multi.lua
  - ../shared/lua/filter_internal_links.lua
  - ../shared/lua/filter_stats_panel.lua
  - ../shared/lua/render_end_timer.lua
```

`utils_*.lua` modülleri tarih, telefon, plaka, katılımcı (participant), kayıt (record), zaman, birim (unit) formatlaması için yardımcılardır. Türkçe ve İngilizce varyantları ayrı dosyalardadır (`utils_date.lua` vs `utils_date_en.lua`).

### Katılımcı Sistemi (Participants)

`tr/_quarto.yml` içindeki `metadata.participant` bloğu davada geçen kişileri rol bazında (victim/suspect/witness/judge/prosecutor/müdafi/...) tanımlar. Lua filter'lar (`utils_participant.lua`, `highlight_speakers.lua`, `span_multi.lua`) bu metadata'yı okuyarak inline rol gösterimlerini, renk vurgularını ve tooltip'leri otomatik üretir. Yeni bir isim veya rol eklerken `_quarto.yml`'deki participant tablosunu güncelle — isimler metin içinde eşleştiği yerlerde otomatik işlenir.

Benzer şekilde `metadata.abbr` kısaltma genişletmesi için, `metadata.phones` ve `metadata.plates` de `utils_phone.lua` / `utils_plate.lua` tooltip'leri için kullanılır.

### Python Yardımcıları (`shared/python/`)

**Aktif pipeline** (pre-render/post-render hook'larında çalışır):
- `precompute_reading_stats.py` — her `.qmd` için okuma süresi/istatistik YAML üretir
- `wordcloud_ngrams.py` — n-gram ve word cloud hesaplaması (stdlib-only)
- `pandoc_ast.py` — pandoc binary'sini subprocess ile çağırıp AST dönüşümü yapar (`precompute_reading_stats` tarafından kullanılır)
- `render_timer.py start|end` — toplam build wall-clock süresini `.qrender_timer.tmp.json` ile ölçer; `end` çağrısı `emit_render_json.py`'yi subprocess olarak çağırır
- `emit_render_json.py` — `render_end_timer.lua`'nın yazdığı `.qrender-time.tmp-<lang>.tsv` dosyalarını okuyup `.qrender-time-<lang>.json` JSON'una aggregate eder

**Dead code** (pipeline'da **kullanılmıyor**, import'lar yorum satırı):
- `zemberek_lemmatizer.py`, `zemberek_pos.py`, `zemberek_noun_phrase_filter.py` — Türkçe NLP için offline script'ler. JVM + Zemberek JAR gerektirirler ama aktif build'de import edilmezler (`precompute_reading_stats.py:13-14`'te import'lar comment'lenmiş). Geçmişte word cloud üretimi için kullanılmış olabilir.

**Kesin aktif Python bağımlılık listesi**: `PyYAML` + `pandoc` binary (Quarto ile geliyor). Java/JVM/Zemberek gerekmiyor.

### Profiles

`_quarto.yml` `profiles: [dev, prod]` tanımlar; `_quarto-dev.yml` ve `_quarto-prod.yml` override'ları içerir. Production build'lerde ekstra optimizasyon/analytics katmanları açılır — yeni bir flag eklerken hangi profile'a ait olduğunu kontrol et.

### Render Timing Stabilization (Dikkat!)

`shared/lua/render_end_timer.lua:147-153`'te per-file render süreleri için **kasıtlı stabilization** var: Yeni ölçülen ms, `.qrender-time-<lang>.json`'daki eski değerden 500ms'den az farklıysa, **eski değer kullanılır**. Hem footer HTML'inde hem JSON'a geri yazılırken.

**Amacı**: Page footer'daki "bu sayfa X saniyede render oldu" metriği her build'de ±50ms oynamasın (stabil UX).

**Yan etkisi**: `emit_render_json.py:121`'deki `⚙️ Quarto render time : XX sec` satırı (stdout'a basılan toplam) de aynı threshold etkisiyle sabit görünür. Örn. 4 ardışık build'de tam sayı eşleşmesi (`73.669`, `40.072`) tipik. **Bu cache/freeze bozukluğu değil, tasarımın doğal sonucu.** Gerçek wall-clock için `✅ Total elapsed time : XX s` satırına bak (`render_timer.py` üretir, stabilization yoktur).

Minör: `os.clock()` CPU time ölçer, wall-clock değil — paralel filter'larda gariplik olabilir. Ayrıca silinmiş `.qmd` dosyalarına ait kayıtlar `.qrender-time-<lang>.json`'dan asla temizlenmez (stale entries birikir).

## Değişiklik Yaparken Dikkat Edilecekler

- **İki dilli değişiklikler:** İçerik değişikliği tipik olarak `tr/` canonical, sonra `en/` altında mirror edilir. Yeni sayfa eklerken her iki site'de dosya yolları paralel olmalı (`tr/trial/x.qmd` ↔ `en/trial/x.qmd`).
- **Static assets:** `resources/` hem TR hem EN tarafından `/resources/...` absolute path ile tüketilir — her iki site'in `_quarto.yml`'inde bu klasör `resources:` listesinde değil, paylaşımlıdır. Asset değiştirirken her iki profile için etkisini düşün.
- **Navbar/sidebar:** `tr/_quarto.yml`'deki website yapısı extensive — mahkeme → ifadeler/savunmalar/karar → sanık/tanık hiyerarşisi. Yeni sanık/tanık eklerken ilgili sidebar entry'sini ve `participant` metadata'sını birlikte güncelle.
- **Extension'lara dokunurken:** Custom Lua extension'ları değiştirince mutlaka ilgili `run_tests.sh`'i çalıştır. `hashtag` için ayrıca perf guard var.
- **Render hook'ları:** `pre-render`/`post-render` zinciri bozulursa `docs/` deploy çalışmaz — script'lerin exit code'u önemli (`set -e`).

## Diller & Çeviri

`translation-prompt.txt` TR → EN çeviri için kullanılan prompt template. EN içeriği manuel/yarı-otomatik (harici LLM) üretilir; EN render sonrası `sync-tr.sh` onu TR site'in `/en/` subdirectory'sine taşır (tek bir GitHub Pages deploy).

## Git Identity & Remote

Bu repo **git-guard** ile koruma altındadır (`.git-identity-guard` commit'li). Identity politikası:

- **Account**: `narineneoldu` (NOT `isezen` — Claude Code'un default kimliği)
- **Email**: `224759555+narineneoldu@users.noreply.github.com`
- **Name**: `narineneoldu`
- **Remote**: `git@github-narineneoldu:narineneoldu/narineneoldu.github.io.git` (SSH host alias, `github.com` değil)

Yanlış identity ile commit/push yapılırsa hook blocklar. Yeni bir clone'da bu identity repo-local olarak yeniden set edilmelidir. `.git-identity-guard` policy dosyası repo'da kalıcıdır.

**Commit mesajlarında Claude attribution kullanma** — bu repo'ya özgü kural. Commit history'de sadece `narineneoldu` görünmeli; `Co-Authored-By: Claude ...` satırı eklenmez.

## Bilinen Kapalı Konular

- **`shared/python/zemberek_*.py` dosyaları dead code**. Aktif pipeline'da import edilmiyorlar (`precompute_reading_stats.py` içindeki ilgili import satırları commentli). Silinip silinmemesi kullanıcı kararı.
- **`shared/lua/external_links.lua` ve `blog_post_filter.backup.lua`** — `.gitignore`'da, eski backup'lar. Kullanım dışı olabilir, proje sahibi doğrulayana kadar dokunma.
- **`docs/` artık doğrudan tracked**: Önceki `ignore-docs`/`no-ignore-docs` `assume-unchanged` workaround'u kaldırıldı — stale git stat cache bug'ına neden oluyordu (deploy commit'lerinde güncellenmiş dosyalar sessizce atlanıyordu). `docs/` sadece `deploy.sh` tarafından güncellenir, normal iş akışında gürültü oluşmaz.

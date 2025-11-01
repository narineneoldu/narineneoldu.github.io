document.addEventListener('DOMContentLoaded', () => {

  // --- basit WebVTT parser -> [{start,end,text}, ...] ---
  function parseVTT(vttText) {
    const lines = vttText.split(/\r?\n/);
    const cues = [];
    let i = 0;

    function tsToSec(ts) {
      // "HH:MM:SS.mmm" veya "MM:SS.mmm"
      const parts = ts.split(':');
      let h, m, s;
      if (parts.length === 3) {
        h = parseInt(parts[0],10) || 0;
        m = parseInt(parts[1],10) || 0;
        s = parseFloat(parts[2]) || 0;
      } else {
        h = 0;
        m = parseInt(parts[0],10) || 0;
        s = parseFloat(parts[1]) || 0;
      }
      return h*3600 + m*60 + s;
    }

    while (i < lines.length) {
      let line = lines[i].trim();

      // WEBVTT header / boş satırları geç
      if (!line || /^WEBVTT/i.test(line)) {
        i++;
        continue;
      }

      // optional cue id satırı olabilir
      let maybeId = line;
      let next = (lines[i+1] || "").trim();
      let timecodeLine = null;

      if (next.includes('-->')) {
        // bu satır ID, sonraki satır timecode
        timecodeLine = next;
        i += 2;
      } else if (line.includes('-->')) {
        // bu satır timecode'ın kendisi
        timecodeLine = line;
        i += 1;
      } else {
        i++;
        continue;
      }

      if (!timecodeLine) continue;
      const match = timecodeLine.match(/([^ ]+)\s+-->\s+([^ ]+)/);
      if (!match) continue;

      const startSec = tsToSec(match[1]);
      const endSec   = tsToSec(match[2]);

      // metin satırlarını oku (boş satıra kadar)
      const textLines = [];
      while (i < lines.length && lines[i].trim() !== "") {
        textLines.push(lines[i]);
        i++;
      }
      // boş satırı da geç
      i++;

      const text = textLines.join('\n').trim();
      cues.push({ start: startSec, end: endSec, text: text });
    }

    return cues;
  }

  // Kaynak var mı yok mu?
  async function resourceExists(url) {
    if (!url) return false;
    try {
      const res = await fetch(url, { method: 'HEAD' });
      return res.ok;
    } catch(e) {
      return false;
    }
  }

  // Bütün player'ları başlat
  const players = Array.from(document.querySelectorAll('.js-player')).map(mediaEl => {

    const player = new Plyr(mediaEl, {
      controls: [
        'play',
        'progress',
        'current-time',
        'mute',
        'settings'
      ],
      captions: {
        active: false,      // Plyr'in default captions UI'si audio'da zaten görünmeyecek
        language: 'auto',
        update: false
      }
    });

    player.on('ready', async () => {
      const plyrRoot  = player.elements.container; // .plyr div
      const blockRoot = plyrRoot.closest('.audio-block');

      // 1) wrapper ve üst caption bandını yarat
      // <div class="plyr-wrapper">
      //   <div class="plyr-audio-caption-live"></div>
      //   <div class="plyr ..."></div>
      // </div>
      const wrapper = document.createElement('div');
      wrapper.className = 'plyr-wrapper';

      const liveCap = document.createElement('div');
      liveCap.className = 'plyr-audio-caption-live';
      liveCap.textContent = ''; // başlangıçta boş

      // wrapper'ı DOM'a sok:
      // audio-block'un içinde plyrRoot vardı. plyrRoot'u wrapper'a taşıyoruz.
      blockRoot.insertBefore(wrapper, plyrRoot);
      wrapper.appendChild(liveCap);
      wrapper.appendChild(plyrRoot);

      // 2) mini volume popup kur
      const muteBtn = plyrRoot.querySelector('[data-plyr="mute"]');
      if (muteBtn) {
        muteBtn.classList.add('has-mini-volume');
        muteBtn.setAttribute('aria-haspopup', 'true');
        muteBtn.setAttribute('aria-expanded', 'false');

        const volWrapper = document.createElement('div');
        volWrapper.className = 'mini-volume-wrapper';

        const volInner = document.createElement('div');
        volInner.className = 'mini-volume-inner';

        const volLabel = document.createElement('div');
        volLabel.className = 'mini-volume-label';

        const volShell = document.createElement('div');
        volShell.className = 'mini-volume-slider-shell';

        const volSlider = document.createElement('input');
        volSlider.type = 'range';
        volSlider.min = '0';
        volSlider.max = '1';
        volSlider.step = '0.05';
        volSlider.value = player.volume.toString();
        volSlider.className = 'mini-volume-slider';

        volShell.appendChild(volSlider);
        volInner.appendChild(volLabel);
        volInner.appendChild(volShell);
        volWrapper.appendChild(volInner);
        muteBtn.appendChild(volWrapper);

        // ilk değerleri yaz
        const initV = player.volume;
        volLabel.textContent = Math.round(initV * 100) + '%';
        volSlider.style.setProperty('--val', Math.round(initV * 100) + '%');

        // sabit
        const MIN_VALID_VOLUME = 0.1;   // %10
        const DEFAULT_RESTORE_VOLUME = 0.5; // %50

        let lastNonZeroVolume = player.volume > 0 ? player.volume : DEFAULT_RESTORE_VOLUME;

        // hover
        muteBtn.addEventListener('mouseenter', () => {
          volWrapper.classList.add('show');
          muteBtn.setAttribute('aria-expanded', 'true');
        });
        muteBtn.addEventListener('mouseleave', () => {
          volWrapper.classList.remove('show');
          muteBtn.setAttribute('aria-expanded', 'false');
        });

        // kutuya tıklanınca mute olmasın
        ['mousedown','click','pointerdown'].forEach(evt => {
          volWrapper.addEventListener(evt, ev => {
            ev.stopPropagation();
            ev.stopImmediatePropagation?.();
            ev.preventDefault?.();
          });
        });

        // slider sadece bubble'ı kessin
        ['mousedown','click','pointerdown','touchstart'].forEach(evt => {
          volSlider.addEventListener(evt, ev => {
            ev.stopPropagation();
            ev.stopImmediatePropagation?.();
          });
        });

        // 🎛 slider değişince
        volSlider.addEventListener('input', (ev) => {
          const v = Math.max(0, Math.min(1, parseFloat(ev.target.value) || 0));
          player.volume = v;
          player.muted = (v === 0);

          // sadece anlamlı (>10%) sesleri hatırla
          if (v >= MIN_VALID_VOLUME) {
            lastNonZeroVolume = v;
          }

          const pct = Math.round(v * 100) + '%';
          volLabel.textContent = pct;
          volSlider.style.setProperty('--val', pct);
        });

        // 🎯 MUTE BUTTON → SLIDER ile SENKRON
        // (Plyr muteyi kendi yapacak, biz sonra düzeltiriz)
        muteBtn.addEventListener('click', () => {
          setTimeout(() => {
            // Unmute oldu ama sesi 0
            if (!player.muted && (player.volume === 0 || isNaN(player.volume))) {
              const restore =
                (lastNonZeroVolume && lastNonZeroVolume >= MIN_VALID_VOLUME)
                  ? DEFAULT_RESTORE_VOLUME
                  : lastNonZeroVolume;

              player.volume = restore;
              volSlider.value = restore;

              const pct = Math.round(restore * 100) + '%';
              volLabel.textContent = pct;
              volSlider.style.setProperty('--val', pct);
            }
          }, 0);
        });

        // 🎯 Plyr tarafında mute/unmute olunca
        player.on('volumechange', () => {
          const v = player.muted ? 0 : player.volume;
          volSlider.value = v;
          const pct = Math.round(v * 100) + '%';
          volLabel.textContent = pct;
          volSlider.style.setProperty('--val', pct);
        });
      }

      // 3) altyazı bandı (liveCap) için VTT yükle / eşle
      const captionURL = mediaEl.getAttribute('data-caption-src');
      if (!captionURL || !(await resourceExists(captionURL))) {
        // hiç VTT yoksa bandı sakla
        liveCap.style.display = 'none';
        return;
      }

      // VTT indir ve parse et
      let cues = [];
      try {
        const vttText = await fetch(captionURL, { credentials: 'same-origin' }).then(r => r.text());
        cues = parseVTT(vttText);
      } catch (e) {
        console.warn("VTT okunamadı / parse edilemedi:", captionURL, e);
      }

      if (!cues.length) {
        liveCap.style.display = 'none';
        return;
      }

      // 🎯 VTT'deki en uzun metne göre yüksekliği sabitle
      function computeCaptionHeight() {
        const measurer = document.createElement('div');
        measurer.style.position = 'absolute';
        measurer.style.visibility = 'hidden';
        measurer.style.pointerEvents = 'none';
        measurer.style.whiteSpace = 'normal';
        measurer.style.width = liveCap.clientWidth + 'px';
        measurer.style.lineHeight = window.getComputedStyle(liveCap).lineHeight;
        measurer.style.fontSize = window.getComputedStyle(liveCap).fontSize;
        measurer.style.fontFamily = window.getComputedStyle(liveCap).fontFamily;
        measurer.style.padding = window.getComputedStyle(liveCap).padding;
        document.body.appendChild(measurer);

        let maxHeight = 0;
        for (const cue of cues) {
          measurer.innerHTML = cue.text.replace(/\n/g, '<br>');
          const h = measurer.scrollHeight;
          if (h > maxHeight) maxHeight = h;
        }

        document.body.removeChild(measurer);
        liveCap.style.minHeight = maxHeight + 'px';
      }

      // İlk hesaplama
      computeCaptionHeight();

      // 🎯 Resize olursa yeniden hesapla (debounce ile)
      let resizeTimeout;
      window.addEventListener('resize', () => {
        clearTimeout(resizeTimeout);
        resizeTimeout = setTimeout(() => {
          computeCaptionHeight();
        }, 200);
      });

      // timeupdate ile aktif cue'yu bulalım
      let lastText = '';
      function updateCaption() {
        const t = player.currentTime;
        let active = '';
        for (let i=0; i<cues.length; i++) {
          if (t >= cues[i].start && t <= cues[i].end) {
            active = cues[i].text;
            break;
          }
        }
        if (active !== lastText) {
          lastText = active;
          // newline -> <br>
          liveCap.innerHTML = active.replace(/\n/g, '<br>');
        }
      }

      // ilk yüklemede ve sonra her değişimde
      updateCaption();
      player.on('timeupdate', updateCaption);
      player.on('seeked', updateCaption);
    });

    return player;
  });
});

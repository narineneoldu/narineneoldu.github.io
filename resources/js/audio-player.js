document.addEventListener('DOMContentLoaded', () => {
  const players = Array.from(document.querySelectorAll('.js-player')).map(audioEl => {
    const player = new Plyr(audioEl, {
      controls: [
        'play',
        'progress',
        'current-time',
        'mute',
        'settings'
      ]
    });

    player.on('ready', () => {
      const plyrRoot = player.elements.container;

      // 1. mute butonunu bul
      const muteBtn = plyrRoot.querySelector('[data-plyr="mute"]');
      if (!muteBtn) return;

      // 2. popup wrapper
      const volWrapper = document.createElement('div');
      volWrapper.className = 'mini-volume-wrapper';

      // 3. inner container
      const volInner = document.createElement('div');
      volInner.className = 'mini-volume-inner';

      // 4. dikey slider
      const volSlider = document.createElement('input');
      volSlider.type = 'range';
      volSlider.min = '0';
      volSlider.max = '1';
      volSlider.step = '0.05';
      volSlider.value = player.volume.toString();
      volSlider.className = 'mini-volume-slider';

      // yapıyı birleştir
      volInner.appendChild(volSlider);
      volWrapper.appendChild(volInner);

      // mute butonu popup anchor'ı olsun
      muteBtn.classList.add('has-mini-volume');
      muteBtn.appendChild(volWrapper);

      // --- kritik kısım: olayları butona/bubble ettirmiyoruz ---
      // kullanıcı slider'a tıklayınca plyr'ın mute toggle etmesini engelle
      const blockBubble = (ev) => {
        ev.stopPropagation();
        ev.stopImmediatePropagation?.();
      };

      // pointer/mouse/touch olaylarını engelle
      ['mousedown','mouseup','click','touchstart','touchend','pointerdown','pointerup']
        .forEach(evtName => {
          volSlider.addEventListener(evtName, (ev) => {
            blockBubble(ev);
          });
        });

      // sürüklerken volume'ü güncelle
      volSlider.addEventListener('input', (ev) => {
        blockBubble(ev);

        const v = parseFloat(ev.target.value);

        // sesi ayarla
        player.volume = v;

        // volume 0 ise mute=true, değilse mute=false
        player.muted = (v === 0);
      });

      // slidera ilk basıldığında otomatik olarak muted=false yapalım
      // (yani kullanıcı sesi açmak isterse unmute olsun)
      volSlider.addEventListener('pointerdown', (ev) => {
        blockBubble(ev);
        if (player.muted && parseFloat(volSlider.value) > 0) {
          player.muted = false;
        }
      });

      // hover davranışı
      muteBtn.addEventListener('mouseenter', () => {
        volWrapper.classList.add('show');
      });
      muteBtn.addEventListener('mouseleave', () => {
        volWrapper.classList.remove('show');
      });
    });

    return player;
  });
});

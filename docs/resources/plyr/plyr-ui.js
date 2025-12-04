// ../resource/plyr/plyr-ui.js

(function () {
  // Mini volume popup initializer (idempotent)
  function setupMiniVolume(player) {
    if (!player || player._miniVolumeInitialized) {
      return;
    }

    const plyrRoot = player.elements && player.elements.container;
    if (!plyrRoot) {
      return;
    }

    const muteBtn = plyrRoot.querySelector('[data-plyr="mute"]');
    if (!muteBtn) {
      // Controls may not be built yet
      return;
    }

    // If wrapper already exists on this button, consider it initialized
    if (muteBtn.querySelector('.mini-volume-wrapper')) {
      player._miniVolumeInitialized = true;
      return;
    }

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

    // Initial label/slider style
    const initV = player.volume;
    volLabel.textContent = Math.round(initV * 100) + '%';
    volSlider.style.setProperty('--val', Math.round(initV * 100) + '%');

    // Constants
    const MIN_VALID_VOLUME = 0.1;   // 10%
    const DEFAULT_RESTORE_VOLUME = 0.5; // 50%

    let lastNonZeroVolume =
      player.volume > 0 ? player.volume : DEFAULT_RESTORE_VOLUME;

    // Hover handlers
    muteBtn.addEventListener('mouseenter', () => {
      volWrapper.classList.add('show');
      muteBtn.setAttribute('aria-expanded', 'true');
    });
    muteBtn.addEventListener('mouseleave', () => {
      volWrapper.classList.remove('show');
      muteBtn.setAttribute('aria-expanded', 'false');
    });

    // Prevent mute toggle when interacting with popup container
    ['mousedown', 'click', 'pointerdown'].forEach(evt => {
      volWrapper.addEventListener(evt, ev => {
        ev.stopPropagation();
        if (typeof ev.stopImmediatePropagation === 'function') {
          ev.stopImmediatePropagation();
        }
        if (typeof ev.preventDefault === 'function') {
          ev.preventDefault();
        }
      });
    });

    // Slider only stops event bubbling
    ['mousedown', 'click', 'pointerdown', 'touchstart'].forEach(evt => {
      volSlider.addEventListener(evt, ev => {
        ev.stopPropagation();
        if (typeof ev.stopImmediatePropagation === 'function') {
          ev.stopImmediatePropagation();
        }
      });
    });

    // Slider change → update player volume
    volSlider.addEventListener('input', (ev) => {
      const v = Math.max(
        0,
        Math.min(1, parseFloat(ev.target.value) || 0)
      );
      player.volume = v;
      player.muted = (v === 0);

      if (v >= MIN_VALID_VOLUME) {
        lastNonZeroVolume = v;
      }

      const pct = Math.round(v * 100) + '%';
      volLabel.textContent = pct;
      volSlider.style.setProperty('--val', pct);
    });

    // Mute button click → sync slider with restored volume if needed
    muteBtn.addEventListener('click', () => {
      setTimeout(() => {
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

    // Volume changes from Plyr side → sync slider and label
    player.on('volumechange', () => {
      const v = player.muted ? 0 : player.volume;
      volSlider.value = v;
      const pct = Math.round(v * 100) + '%';
      volLabel.textContent = pct;
      volSlider.style.setProperty('--val', pct);
    });

    // Mark as initialized to avoid duplicates
    player._miniVolumeInitialized = true;
  }

  function attachMiniVolumeHooks(player) {
    if (!player || !player.on) return;

    // Ensure setup on ready (controls are built)
    player.on('ready', () => {
      setupMiniVolume(player);
    });

    // And on play (covers autoplay cases if mute button appeared later)
    player.on('play', () => {
      setupMiniVolume(player);
    });
  }

  // When new players are created by core, attach hooks
  window.addEventListener('plyr-player-created', (ev) => {
    const player = ev.detail && ev.detail.player;
    if (!player) return;
    attachMiniVolumeHooks(player);
  });

  // Also handle players that might already exist in PlyrCore.players
  if (window.PlyrCore && Array.isArray(window.PlyrCore.players)) {
    window.PlyrCore.players.forEach((player) => {
      attachMiniVolumeHooks(player);
    });
  }

  // Expose for debugging if needed
  window.PlyrUI = window.PlyrUI || {};
  window.PlyrUI.setupMiniVolume = setupMiniVolume;
})();

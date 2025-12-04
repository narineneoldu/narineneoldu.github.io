// ../resource/plyr/plyr-jump.js

(function () {
  // Parse "HH:MM:SS", "MM:SS" or "SS" into seconds
  function parseTimecodeToSeconds(str) {
    if (!str) {
      return 0;
    }

    const clean = String(str).trim();
    if (!clean) {
      return 0;
    }

    // Keep only digits and colons
    const normalized = clean.replace(/[^\d:]/g, '');
    const parts = normalized.split(':').map(function (p) {
      const n = parseInt(p, 10);
      return isNaN(n) ? 0 : n;
    });

    if (parts.length === 3) {
      const h = parts[0];
      const m = parts[1];
      const s = parts[2];
      return h * 3600 + m * 60 + s;
    } else if (parts.length === 2) {
      const m = parts[0];
      const s = parts[1];
      return m * 60 + s;
    } else if (parts.length === 1) {
      return parts[0];
    }

    return 0;
  }

  // Parse hash in the form "#ID&t=01:23"
  function parseHash(hash) {
    if (!hash || hash.length <= 1) {
      return null;
    }

    // Remove leading '#'
    const raw = hash.slice(1);
    if (!raw) {
      return null;
    }

    const parts = raw.split('&');
    const idPart = parts[0] || '';
    if (!idPart) {
      return null;
    }

    let timePart = null;
    for (let i = 1; i < parts.length; i++) {
      const piece = parts[i];
      const kv = piece.split('=');
      if (kv[0] === 't') {
        timePart = kv[1] || '';
        break;
      }
    }

    if (!timePart) {
      return null;
    }

    try {
      return {
        id: decodeURIComponent(idPart),
        timeString: decodeURIComponent(timePart)
      };
    } catch (e) {
      // Fallback: use raw values if decoding fails
      return {
        id: idPart,
        timeString: timePart
      };
    }
  }

  // Find Plyr instance by ID (matches player._id, wrapper.id or mediaEl.id)
  function findPlayerById(id) {
    if (!id || !window.PlyrCore || !Array.isArray(window.PlyrCore.players)) {
      return null;
    }

    const players = window.PlyrCore.players;
    for (let i = 0; i < players.length; i++) {
      const p = players[i];
      if (!p) continue;

      if (p._id === id) {
        return p;
      }
      if (p._wrapper && p._wrapper.id === id) {
        return p;
      }
      if (p._mediaEl && p._mediaEl.id === id) {
        return p;
      }
    }

    return null;
  }

  // Eski:
  // function seekAndPlay(player, seconds) {
  function seekAndPlay(player, seconds, opts) {
    const autoPlay = !opts || opts.autoPlay !== false;

    if (!player || !Number.isFinite(seconds)) {
      return;
    }

    try {
      // 1) Her durumda önce seek et
      try {
        player.currentTime = seconds;
      } catch (e) {
        console.warn("Error setting currentTime:", e);
      }

      // Deep-link senaryosu için: sadece seek et, play etme
      if (!autoPlay) {
        console.groupEnd();
        return;
      }

      // 2) Eğer zaten oynuyorsa, ekstra play/mute/volume dokunma
      if (player.playing) {
        console.groupEnd();
        return;
      }

      // 3) Paused ise Plyr’ın kendi play butonuna tıklamayı simüle et
      let playButton = null;

      if (player.elements && player.elements.buttons && player.elements.buttons.play) {
        playButton = player.elements.buttons.play;
      }

      if (!playButton && player.elements && player.elements.container) {
        playButton = player.elements.container.querySelector('[data-plyr="play"]');
      }

      if (playButton && typeof playButton.click === "function") {
        playButton.click();
      } else {
        try {
          const maybePromise = player.play();
          if (maybePromise && typeof maybePromise.then === "function") {
            maybePromise.catch(function (err) {
              console.warn("player.play() rejected in fallback:", err);
            });
          }
        } catch (e) {
          console.warn("Fallback player.play() error:", e);
        }
      }

      console.groupEnd();
    } catch (e) {
      console.warn("seekAndPlay outer ERROR:", e);
    }
  }

  document.addEventListener('DOMContentLoaded', function () {
    // If there is a hash with time info on initial load, store it as "pending"
    let pendingHashJump = null;

    function applyHashJumpIfPossible() {
      if (!pendingHashJump) {
        return;
      }

      const player = findPlayerById(pendingHashJump.id);
      if (!player || !player._isReady) {
        // Player is not ready yet; keep pending
        return;
      }

      seekAndPlay(player, pendingHashJump.seconds, { autoPlay: false });
      pendingHashJump = null;
    }

    // 1) Initial deep-link from URL hash (e.g. #LAe1zoOdF1c&t=01:23)
    (function handleInitialHash() {
      const info = parseHash(window.location.hash);
      if (!info) {
        return;
      }

      const seconds = parseTimecodeToSeconds(info.timeString);
      if (!Number.isFinite(seconds)) {
        return;
      }

      pendingHashJump = {
        id: info.id,
        seconds: seconds
      };

      // Try immediately (in case players are already ready)
      applyHashJumpIfPossible();
    })();

    // If players become ready later, re-try pending hash jump
    window.addEventListener('plyr-player-ready', function () {
      applyHashJumpIfPossible();
    });

    // 2) Delegated click handler for .timejump links
    document.addEventListener('click', function (ev) {
      const link = ev.target.closest && ev.target.closest('a.timejump');
      if (!link) {
        return;
      }

      // Prefer data attributes if available
      let targetId = link.dataset.player || null;
      let timeStr = link.dataset.time || null;

      // Fallback: parse from href hash if needed
      if (!targetId || !timeStr) {
        try {
          const url = new URL(link.href, window.location.href);
          const info = parseHash(url.hash);
          if (info) {
            if (!targetId) {
              targetId = info.id;
            }
            if (!timeStr) {
              timeStr = info.timeString;
            }
          }
        } catch (e) {
          // Ignore URL parsing errors
        }
      }

      if (!targetId || !timeStr) {
        return;
      }

      const seconds = parseTimecodeToSeconds(timeStr);
      if (!Number.isFinite(seconds)) {
        return;
      }

      // Detect if this is a same-page link
      let samePage = false;
      try {
        const url = new URL(link.href, window.location.href);
        samePage =
          url.origin === window.location.origin &&
          url.pathname === window.location.pathname;
      } catch (e) {
        // If parsing fails, assume same page
        samePage = true;
      }

      if (samePage) {
        // Prevent full navigation/reload
        ev.preventDefault();

        // Update the URL hash to "#ID&t=01:23" so that:
        // - Refresh keeps the same time
        // - Copying the URL from the address bar includes the timestamp
        try {
          const newHash =
            '#' +
            encodeURIComponent(targetId) +
            '&t=' +
            encodeURIComponent(timeStr);

          if (window.location.hash !== newHash) {
            if (window.history && typeof window.history.replaceState === 'function') {
              window.history.replaceState(null, '', newHash);
            } else {
              window.location.hash = newHash;
            }
          }
        } catch (e) {
          // Ignore hash update errors
        }

        // Scroll to the corresponding player element if it exists
        const anchorEl = document.getElementById(targetId);
        if (anchorEl && typeof anchorEl.scrollIntoView === 'function') {
          anchorEl.scrollIntoView({
            behavior: 'smooth',
            block: 'center'
          });
        }
      }

      // Find the Plyr instance and perform seek + play
      const player = findPlayerById(targetId);
      if (player && player._isReady) {
        seekAndPlay(player, seconds);
      } else {
        // Player not ready yet (unlikely on click, but kept for safety)
        pendingHashJump = {
          id: targetId,
          seconds: seconds
        };
      }
    });
  });
})();

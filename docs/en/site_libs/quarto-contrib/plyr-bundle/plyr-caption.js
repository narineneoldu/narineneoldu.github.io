// /_extensions/media-short/plyr-caption.js

(function () {
  // Simple WebVTT parser -> [{ start, end, text }, ...]
  function parseVTT(vttText) {
    const lines = vttText.split(/\r?\n/);
    const cues = [];
    let i = 0;

    function tsToSec(ts) {
      const parts = ts.split(':');
      let h, m, s;
      if (parts.length === 3) {
        h = parseInt(parts[0], 10) || 0;
        m = parseInt(parts[1], 10) || 0;
        s = parseFloat(parts[2]) || 0;
      } else {
        h = 0;
        m = parseInt(parts[0], 10) || 0;
        s = parseFloat(parts[1]) || 0;
      }
      return h * 3600 + m * 60 + s;
    }

    while (i < lines.length) {
      let line = lines[i].trim();

      // Skip WEBVTT header / empty lines
      if (!line || /^WEBVTT/i.test(line)) {
        i++;
        continue;
      }

      const next = (lines[i + 1] || '').trim();
      let timecodeLine = null;

      if (next.includes('-->')) {
        // Current line is cue id, next line is timecode
        timecodeLine = next;
        i += 2;
      } else if (line.includes('-->')) {
        // Current line is timecode
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
      const endSec = tsToSec(match[2]);

      // Collect text lines until a blank line
      const textLines = [];
      while (i < lines.length && lines[i].trim() !== '') {
        textLines.push(lines[i]);
        i++;
      }
      // Skip the blank line
      i++;

      const text = textLines.join('\n').trim();
      cues.push({ start: startSec, end: endSec, text: text });
    }

    return cues;
  }

  async function resourceExists(url) {
    if (!url) return false;
    try {
      const res = await fetch(url, { method: 'HEAD' });
      return res.ok;
    } catch (e) {
      return false;
    }
  }

  async function initAudioCaptions(player) {
    if (!player || player._audioCaptionsInitialized) {
      return;
    }

    const mediaEl = player._mediaEl;
    const plyrRoot = player.elements && player.elements.container;
    const wrapper = player._wrapper || (plyrRoot && plyrRoot.closest('.plyr-wrapper'));

    if (!mediaEl || !plyrRoot || !wrapper) {
      return;
    }

    // Create live caption band above the player container (like old behavior)
    const liveCap = document.createElement('div');
    liveCap.className = 'plyr-audio-caption-live';
    liveCap.textContent = '';

    const refNode = wrapper.contains(plyrRoot)
      ? plyrRoot
      : wrapper.firstChild;

    if (refNode) {
      wrapper.insertBefore(liveCap, refNode);
    } else {
      wrapper.appendChild(liveCap);
    }

    // Find the first <track kind="subtitles"> element
    const firstTrack = mediaEl.querySelector('track[kind="subtitles"]');
    const captionURL = firstTrack ? firstTrack.getAttribute('src') : null;
    if (!captionURL || !(await resourceExists(captionURL))) {
      // No VTT available, hide band
      liveCap.style.display = 'none';
      player._audioCaptionsInitialized = true;
      return;
    }

    // Fetch and parse VTT
    let cues = [];
    try {
      const vttText = await fetch(captionURL, { credentials: 'same-origin' }).then(r => r.text());
      cues = parseVTT(vttText);
    } catch (e) {
      console.warn('VTT could not be loaded or parsed:', captionURL, e);
    }

    if (!cues.length) {
      liveCap.style.display = 'none';
      player._audioCaptionsInitialized = true;
      return;
    }

    // Fix height according to the tallest cue
    function computeCaptionHeight() {
      const measurer = document.createElement('div');
      measurer.style.position = 'absolute';
      measurer.style.visibility = 'hidden';
      measurer.style.pointerEvents = 'none';
      measurer.style.whiteSpace = 'normal';
      measurer.style.width = liveCap.clientWidth + 'px';

      const liveStyles = window.getComputedStyle(liveCap);
      measurer.style.lineHeight = liveStyles.lineHeight;
      measurer.style.fontSize = liveStyles.fontSize;
      measurer.style.fontFamily = liveStyles.fontFamily;
      measurer.style.padding = liveStyles.padding;

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

    // Initial height computation
    computeCaptionHeight();

    // Recompute on resize (with debounce)
    let resizeTimeout;
    const onResize = () => {
      clearTimeout(resizeTimeout);
      resizeTimeout = setTimeout(() => {
        computeCaptionHeight();
      }, 200);
    };
    window.addEventListener('resize', onResize);

    // Update caption according to current time
    let lastText = '';
    function updateCaption() {
      const t = player.currentTime;
      let active = '';
      for (let i = 0; i < cues.length; i++) {
        if (t >= cues[i].start && t <= cues[i].end) {
          active = cues[i].text;
          break;
        }
      }
      if (active !== lastText) {
        lastText = active;
        liveCap.innerHTML = active.replace(/\n/g, '<br>');
      }
    }

    // Initial update and subsequent updates
    updateCaption();
    player.on('timeupdate', updateCaption);
    player.on('seeked', updateCaption);

    // Mark as initialized to avoid duplicate wiring
    player._audioCaptionsInitialized = true;
  }

  function initVideoCaptions(player) {
    // Placeholder for future video caption handling.
    // For now we keep video behavior minimal and only
    // isolate the caption logic into this module.
  }

  // Run captions setup when core reports that a player is ready
  window.addEventListener('plyr-player-ready', (ev) => {
    const player = ev.detail && ev.detail.player;
    if (!player || player._isYouTube || !player._mediaEl) {
      return;
    }

    const tag = player._mediaEl.tagName.toLowerCase();

    if (tag === 'audio') {
      initAudioCaptions(player);
    } else if (tag === 'video') {
      initVideoCaptions(player);
    }
  });

  // Expose helpers for debugging if needed
  window.PlyrCaptions = window.PlyrCaptions || {
    parseVTT,
    resourceExists
  };
})();

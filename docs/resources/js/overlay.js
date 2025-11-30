// ../resources/js/overlay.js
// Shared overlay glass manager for all features (mobile TOC, wordcloud, image viewer, etc.)

(function () {
  /**
   * Ensure there is a single overlay element with the given id.
   * If it does not exist, create and append it to <body>.
   *
   * @param {string} id        - Element id to ensure (e.g. "mobile-toc-glass")
   * @returns {HTMLDivElement} - The overlay element
   */
  function ensureOverlay(id) {
    // Default id and class if not provided
    const finalId = id || "overlay-glass";

    let el = document.getElementById(finalId);
    if (!el) {
      el = document.createElement("div");
      el.id = finalId;
      el.setAttribute("aria-hidden", "true");
      document.body.appendChild(el);
    }
    return el;
  }

  /**
   * Show overlay (add "open" class, aria-hidden=false).
   */
  function showOverlay(el) {
    if (!el) return;
    el.classList.add("open");
    el.setAttribute("aria-hidden", "false");
  }

  /**
   * Hide overlay (remove "open" class, aria-hidden=true).
   */
  function hideOverlay(el) {
    if (!el) return;
    el.classList.remove("open");
    el.setAttribute("aria-hidden", "true");
  }

  /**
   * Convenience method: ensure + show.
   */
  function ensureAndShow(id) {
    const el = ensureOverlay(id);
    showOverlay(el);
    return el;
  }

  /**
   * Expose a small API on window.
   */
  window.AppOverlay = {
    ensureOverlay,
    showOverlay,
    hideOverlay,
    ensureAndShow,
  };
})();

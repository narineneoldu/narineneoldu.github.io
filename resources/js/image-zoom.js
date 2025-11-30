// ../resources/js/image-zoom.js
// Requires: overlay.js (for AppOverlay / overlay-glass)

window.addEventListener("DOMContentLoaded", () => {
  // Shared background overlay glass (Apple-style)
  // You have to load overlay.js before this script for AppOverlay to exist.
  const glass = window.AppOverlay ? AppOverlay.ensureOverlay() : null;

  // 1) Zoom panel (foreground container for the image)
  const zoomPanel = document.createElement("div");
  zoomPanel.className = "zoom-overlay";

  const bigImg = document.createElement("img");
  bigImg.alt = "";

  const closeBtn = document.createElement("button");
  closeBtn.className = "zoom-overlay-close";
  closeBtn.setAttribute("type", "button");
  closeBtn.setAttribute("aria-label", "Kapat");
  closeBtn.innerHTML = "&times;";

  const wrapper = document.createElement("div");
  wrapper.className = "zoom-wrapper";

  wrapper.appendChild(bigImg);
  wrapper.appendChild(closeBtn);
  zoomPanel.appendChild(wrapper);
  document.body.appendChild(zoomPanel);

  const openOverlay = (src, alt) => {
    bigImg.src = src;
    bigImg.alt = alt || "";
    zoomPanel.classList.add("open");
    document.body.classList.add("zoom-open");

    if (glass && window.AppOverlay) {
      // zoom-overlay'in z-index değerini oku
      const panelZ = parseInt(window.getComputedStyle(zoomPanel).zIndex, 10);

      // panelZ geçerli değilse fallback kullan
      const glassZ = Number.isFinite(panelZ) ? panelZ - 1 : 9998;

      // overlay-glass z-index'ini buna göre ayarla
      glass.style.zIndex = glassZ;

      AppOverlay.showOverlay(glass);
    }
  };

  const closeOverlay = () => {
    zoomPanel.classList.remove("open");
    document.body.classList.remove("zoom-open");

    // Hide shared glass overlay, if available
    if (glass && window.AppOverlay) {
      glass.style.zIndex = "";
      AppOverlay.hideOverlay(glass);
    }
  };

  closeBtn.addEventListener("click", closeOverlay);

  zoomPanel.addEventListener("click", (ev) => {
    // Close only when clicking background, not the image itself
    if (ev.target === zoomPanel) {
      closeOverlay();
    }
  });

  document.addEventListener("keydown", (ev) => {
    if (ev.key === "Escape") {
      closeOverlay();
    }
  });

  // 2) Zoom-enabled thumbnails:
  //   - figure.zoom-image img
  //   - or directly img.zoom-image
  const zoomTargets = document.querySelectorAll(
    "figure.zoom-image img, img.zoom-image"
  );

  zoomTargets.forEach((img) => {
    img.addEventListener("click", (ev) => {
      ev.preventDefault();
      ev.stopPropagation();

      const src = img.getAttribute("data-zoom-src") || img.currentSrc || img.src;
      const alt = img.alt || img.getAttribute("aria-label") || "";
      openOverlay(src, alt);
    });
  });
});

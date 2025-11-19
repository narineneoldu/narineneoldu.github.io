// assets/js/image-zoom.js
window.addEventListener("DOMContentLoaded", () => {
  // 1) Overlay'ı oluştur
  const overlay = document.createElement("div");
  overlay.className = "zoom-overlay";

  const bigImg = document.createElement("img");
  bigImg.alt = "";

  const closeBtn = document.createElement("button");
  closeBtn.className = "zoom-overlay-close";
  closeBtn.setAttribute("type", "button");
  closeBtn.setAttribute("aria-label", "Kapat");
  closeBtn.innerHTML = "&times;";

  overlay.appendChild(bigImg);
  overlay.appendChild(closeBtn);
  document.body.appendChild(overlay);

  const openOverlay = (src, alt) => {
    bigImg.src = src;
    bigImg.alt = alt || "";
    overlay.classList.add("open");
    document.body.classList.add("zoom-open");
  };

  const closeOverlay = () => {
    overlay.classList.remove("open");
    document.body.classList.remove("zoom-open");
  };

  closeBtn.addEventListener("click", closeOverlay);
  overlay.addEventListener("click", (ev) => {
    // sadece arka plana tıklayınca kapat (resmin üstüne tıklayınca değil)
    if (ev.target === overlay) {
      closeOverlay();
    }
  });

  document.addEventListener("keydown", (ev) => {
    if (ev.key === "Escape") {
      closeOverlay();
    }
  });

  // 2) Zoom özelliği olan küçük resimleri bul
  //   - figure.zoom-image içindeki img
  //   - ya da doğrudan img.zoom-image
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

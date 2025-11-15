// ../resources/js/mobile-toc-strip.js
// Sağ kenarda dikey "İçindekiler" şeridi + sağdan kayan TOC paneli (mobil)

document.addEventListener("DOMContentLoaded", function () {
  // Orijinal Quarto margin sidebar'ı al
  const sidebar = document.getElementById("quarto-margin-sidebar");
  if (!sidebar) return; // margin sidebar yoksa çık

  // DESKTOP TOC'u bul
  const desktopToc = sidebar.querySelector("nav#TOC");
  // TOC yoksa veya içinde link yoksa: buton/panel oluşturma
  if (!desktopToc) return;
  if (!desktopToc.querySelector("a, li")) return;

  // ---- Tetik butonu (dikey şerit) ----
  const trigger = document.createElement("button");
  trigger.type = "button";
  trigger.className = "mobile-toc-trigger";
  trigger.textContent = "İçindekiler";

  // ---- Panel ----
  const panel = document.createElement("aside");
  panel.className = "mobile-toc-panel";
  panel.setAttribute("aria-hidden", "true");

  const inner = document.createElement("div");
  inner.className = "mobile-toc-inner";

  // ---- GLASS OVERLAY (sadece bizim mobil TOC için) ----
  const glass = document.createElement("div");
  glass.className = "mobile-toc-glass";
  glass.setAttribute("aria-hidden", "true");

  // *** HEADER YÜKSEKLİĞİNE GÖRE PADDING-TOP AYARLA ***
  function updateInnerPadding() {
    const header =
      document.getElementById("quarto-header") ||
      document.querySelector(".navbar.fixed-top, header.navbar, .navbar");

    let pad = 0;
    if (header) {
      pad = header.getBoundingClientRect().height || 0;
      pad -= 20; // biraz yukarıdan başlasın demiştik
    }
    inner.style.paddingTop = pad + "px";
  }

  updateInnerPadding();
  window.addEventListener("resize", updateInnerPadding);

  // Sidebar'ı tüm yapısıyla kopyala
  const sidebarClone = sidebar.cloneNode(true);
  sidebarClone.id = "quarto-margin-sidebar-mobile";

  const tocNav = sidebarClone.querySelector("#TOC");
  if (tocNav) {
    tocNav.id = "TOC-mobile"; // id çakışmasını engelle
    tocNav.querySelectorAll("ul.collapse").forEach(function (ul) {
      ul.classList.remove("collapse"); // mobilde hep açık
    });
  }

  const mobileToc = tocNav; // TOC-mobile artık burada

  // --- DESKTOP TOC -> MOBIL TOC ACTIVE SYNC ---
  function syncMobileActive() {
    if (!desktopToc || !mobileToc) return;

    const desktopActive = desktopToc.querySelectorAll("a.nav-link.active");

    mobileToc.querySelectorAll("a.nav-link.active").forEach(function (a) {
      a.classList.remove("active");
    });

    desktopActive.forEach(function (d) {
      const targetSel =
        d.getAttribute("data-scroll-target") ||
        (d.getAttribute("href") || "").replace(/^[^#]*/, "");

      if (!targetSel) return;

      const selector =
        `[data-scroll-target="${targetSel}"], a[href="${targetSel}"]`;
      const m = mobileToc.querySelector(selector);
      if (m) {
        m.classList.add("active");
      }
    });
  }

  inner.appendChild(sidebarClone);
  panel.appendChild(inner);

  // Sırayla ekleyelim: glass, panel, trigger
  document.body.appendChild(glass);
  document.body.appendChild(panel);
  document.body.appendChild(trigger);

  // ---- Aç / Kapat yardımcıları ----
  function openToc() {
    updateInnerPadding();
    panel.classList.add("open");
    trigger.classList.add("open");
    panel.setAttribute("aria-hidden", "false");

    glass.classList.add("open");
    glass.setAttribute("aria-hidden", "false");
  }

  function closeToc() {
    panel.classList.remove("open");
    trigger.classList.remove("open");
    panel.setAttribute("aria-hidden", "true");

    glass.classList.remove("open");
    glass.setAttribute("aria-hidden", "true");
  }

  function toggleToc() {
    if (panel.classList.contains("open")) {
      closeToc();
    } else {
      openToc();
    }
  }

  // Tetik butonu
  trigger.addEventListener("click", function (e) {
    e.stopPropagation();
    toggleToc();
  });

  // Panel içindeki tıklamalar – hem bubbling’i kes, hem link davranışını koru
  panel.addEventListener("click", function (e) {
    e.stopPropagation();

    const a = e.target.closest("a");
    if (!a) return;

    let targetSel = a.getAttribute("data-scroll-target");

    if (!targetSel) {
      const href = a.getAttribute("href") || "";
      if (href.indexOf("#") !== -1) {
        targetSel = href.substring(href.indexOf("#"));
      }
    }

    if (!targetSel || !targetSel.startsWith("#")) {
      // Harici link ise sadece paneli kapat, normal navigation
      closeToc();
      return;
    }

    const id = targetSel.slice(1);
    const target = document.getElementById(id);
    if (!target) {
      closeToc();
      return;
    }

    const currentY = window.scrollY;
    const targetY = target.getBoundingClientRect().top + currentY;
    const goingUp = targetY < currentY;

    e.preventDefault();
    closeToc();

    setTimeout(function () {
      if (goingUp) {
        const header = document.querySelector(
          "#quarto-header, .navbar.fixed-top, header.navbar, .navbar"
        );

        let offset = 0;
        if (header) {
          offset = header.getBoundingClientRect().height || 0;
          offset += 8;
        } else {
          offset = 72;
        }

        const targetTop = targetY - offset;

        window.scrollTo({
          top: targetTop,
          behavior: "smooth",
        });
      } else {
        target.scrollIntoView({ behavior: "smooth", block: "start" });
      }
    }, 10);
  });

  // --- GLASS'A veya sayfanın geri kalanına tıklayınca kapat ---
  document.addEventListener("click", function (e) {
    if (!panel.classList.contains("open")) return;

    // Panelin içinde veya tetikleyicide tıklandıysa kapatma
    if (
      e.target.closest(".mobile-toc-panel") ||
      e.target.closest(".mobile-toc-trigger")
    ) {
      return;
    }

    // Glass da dahil, geri kalan her yerde tıklama paneli kapatsın
    closeToc();
  });

  // İlk sync
  syncMobileActive();

  // Scroll oldukça mobile TOC'u güncelle
  let syncTimeout;
  window.addEventListener("scroll", function () {
    if (!desktopToc) return;
    clearTimeout(syncTimeout);
    syncTimeout = setTimeout(syncMobileActive, 80);
  });
});

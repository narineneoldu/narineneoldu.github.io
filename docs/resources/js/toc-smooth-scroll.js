// ../resources/js/toc-smooth-scroll.js
// Margin sidebar (#quarto-margin-sidebar içindeki nav#TOC) için
// Quarto TOC linklerine smooth scroll + header offset uygular.

document.addEventListener("DOMContentLoaded", function () {
  const sidebar = document.getElementById("quarto-margin-sidebar");
  if (!sidebar) return;

  const toc = sidebar.querySelector("nav#TOC");
  if (!toc) return;

  // Ortak: hedeften offset'li/smooth scroll
  function smoothScrollToTarget(target) {
    const currentY = window.scrollY || window.pageYOffset || 0;
    const rect = target.getBoundingClientRect();
    const targetY = rect.top + currentY;
    const goingUp = targetY < currentY;

    // Header yüksekliğini bul (senin mobile script ile aynı mantık)
    const header = document.querySelector(
      "#quarto-header, .navbar.fixed-top, header.navbar, .navbar"
    );
    let offset = 0;

    if (header) {
      offset = header.getBoundingClientRect().height || 0;
      offset += 8; // azıcık tampon
    } else {
      offset = 72; // fallback
    }

    if (goingUp) {
      const targetTop = targetY - offset;
      window.scrollTo({
        top: targetTop,
        behavior: "smooth",
      });
    } else {
      // Aşağı inerken de header altında kalmasın istiyorsan
      // yine offset'li kullanabiliriz:
      const targetTop = targetY - offset;
      window.scrollTo({
        top: targetTop,
        behavior: "smooth",
      });
      // İstersen bunu yerine klasik:
      // target.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }

  function getTargetElementFromLink(a) {
    let targetSel = a.getAttribute("data-scroll-target");

    if (!targetSel) {
      const href = a.getAttribute("href") || "";
      if (href.indexOf("#") !== -1) {
        targetSel = href.substring(href.indexOf("#"));
      }
    }

    if (!targetSel || !targetSel.startsWith("#")) {
      return null;
    }

    const id = targetSel.slice(1);
    if (!id) return null;
    return document.getElementById(id);
  }

  // Event delegation: #TOC içindeki tüm a.nav-link'ler için
  toc.addEventListener("click", function (e) {
    const link = e.target.closest("a.nav-link");
    if (!link) return;

    const target = getTargetElementFromLink(link);
    if (!target) {
      // Harici link vs. ise Quarto'nun default davranışı çalışsın
      return;
    }

    e.preventDefault();
    smoothScrollToTarget(target);
  });
});

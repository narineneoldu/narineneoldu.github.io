// Yeni sayfada aç
document.addEventListener("DOMContentLoaded", function () {
  // Navbar ve footer sağ tarafındaki bağlantılar
  const selectors = [
    'nav a[href^="http"]',
    '.nav-footer-right a[href^="http"]'
  ];

  document.querySelectorAll(selectors.join(',')).forEach(link => {
    if (link.hostname !== location.hostname) {
      link.setAttribute("target", "_blank");
      link.setAttribute("rel", "noopener noreferrer");
    }
  });
});

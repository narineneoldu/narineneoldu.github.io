document.addEventListener("DOMContentLoaded", () => {

  // /foo/index.html → /foo/ normalizasyonu (Quarto bazen index.html sunabilir)
  function normalize(pathname) {
    return pathname.replace(/\/index\.html$/, "/");
  }

  function swapLangInPath(pathname, toLang) {
    const hasTrailing = pathname.endsWith("/");
    const parts = normalize(pathname).split("/").filter(Boolean);

    if (toLang === "en") {
      if (parts[0] !== "en") parts.unshift("en");   // TR → EN
    } else {
      if (parts[0] === "en") parts.shift();         // EN → TR
    }

    let newPath = "/" + parts.join("/");
    if (hasTrailing && newPath !== "/") newPath += "/";
    if (newPath === "") newPath = "/";              // kök garanti
    return newPath;
  }

  function go(lang) {
    const url = new URL(window.location.href);      // origin + subpath uyumlu
    url.pathname = swapLangInPath(url.pathname, lang);
    localStorage.setItem("preferredLang", lang);    // tercihi hatırla
    window.location.assign(url.toString());
  }

  document.querySelectorAll(".navbar .lang-switch").forEach(node => {
    const lang = node.dataset.lang;                 // "tr" | "en"
    (node.closest("a") || node).addEventListener("click", e => {
      e.preventDefault();
      go(lang);
    });
  });

});

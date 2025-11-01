document.addEventListener("DOMContentLoaded", () => {
  const tools = document.querySelector(
    "nav .quarto-navbar-tools, nav .navbar-tools, .navbar .quarto-navbar-tools, .navbar .navbar-tools"
  );
  if (!tools) return;

  // Mevcut dil tespiti
  const isEnglish = /^\/en(\/|$)/.test(location.pathname);
  const base = document.querySelector("base")?.href || location.origin + "/";

  // Hedef dil ve URL
  let targetLang, href, icon, title;

  if (isEnglish) {
    // EN → TR yönlendirme
    const url = new URL(location.href);
    const hadTrailing = url.pathname.endsWith("/");
    let seg = url.pathname.replace(/\/index\.html$/, "/").split("/").filter(Boolean);
    if (seg[0] === "en") seg.shift();
    url.pathname =
      "/" +
      seg.join("/") +
      (hadTrailing && seg.length ? "/" : seg.length ? "" : "/");

    targetLang = "tr";
    href = url.toString();
    icon = "/resources/icons/TR.svg";
    title = "Türkçe";
  } else {
    // TR → EN yönlendirme
    const url = new URL("en/", base);
    targetLang = "en";
    href = url.toString();
    icon = "/resources/icons/GB.svg";
    title = "English";
  }

  // Zaten varsa tekrar ekleme
  if (tools.querySelector(`.lang-switch[data-lang='${targetLang}']`)) return;

  // Buton oluştur
  const a = document.createElement("a");
  a.href = href;
  a.className = "quarto-navigation-tool px-1";
  a.innerHTML = `<img src="${icon}" alt="${targetLang.toUpperCase()}" class="lang-switch" title="${title}" data-lang="${targetLang}" width="20" height="15" loading="eager" decoding="async">`;

  a.addEventListener("click", (e) => {
    e.preventDefault();
    localStorage.setItem("preferredLang", targetLang);
    location.assign(href);
  });

  // Navbar'a ekle
  tools.prepend(a);
});

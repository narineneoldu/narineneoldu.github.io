document.addEventListener("DOMContentLoaded", () => {
  const tools = document.querySelector(
    "nav .quarto-navbar-tools, nav .navbar-tools, .navbar .quarto-navbar-tools, .navbar .navbar-tools"
  );
  if (!tools) return;
  const base = document.querySelector("base")?.href || (location.origin + "/");
  const href = new URL("en/", base).toString();

  if (tools.querySelector(".lang-switch[data-lang='en']")) return;

  const a = document.createElement("a");
  a.href = href;
  a.className = "quarto-navigation-tool px-1";
  a.innerHTML = "<img src='/resources/icons/GB.svg' alt='EN' class='lang-switch' title='İngilizce' data-lang='en' width='20' height='15' loading='eager' decoding='async'>";
  a.addEventListener("click", (e) => { e.preventDefault(); localStorage.setItem("preferredLang","en"); location.assign(href); });

  tools.prepend(a);
});

// ../resources/js/wordcloud-overlay.js
// Requires: overlay.js (for AppOverlay / overlay-glass)

(function () {
  // ------------------------------
  // 0. Lang / UI text helpers
  // ------------------------------
  const docLang = (document.documentElement.getAttribute("lang") || "en").toLowerCase();
  const uiLang = docLang.startsWith("tr") ? "tr" : "en";

  const UI_TEXT = uiLang === "tr"
    ? {
        title: "Kelime Bulutu",
        closeLabel: "Kapat",
        refresh: "Yenile",
        copy: "Kopyala",
        save: "Kaydet",
      }
    : {
        title: "Word Cloud",
        closeLabel: "Close",
        refresh: "Refresh",
        copy: "Copy",
        save: "Save",
      };

  function formatFrequencyTooltip(d) {
    const suffix =
      uiLang === "tr"
        ? " kez"
        : (d.value === 1 ? " time" : " times");

    return `${d.text} — ${d.value}${suffix}`;
  }

  // Shared glass overlay (Apple-style)
  const glass = window.AppOverlay ? AppOverlay.ensureOverlay() : null;

  // ------------------------------
  // 1. Simple in-memory JSON cache
  // ------------------------------
  const dataCache = new Map(); // url -> Promise(data)

  function getJsonOnce(url) {
    if (dataCache.has(url)) {
      // Return the same Promise – no extra fetch on resize
      return dataCache.get(url);
    }

    const p = (async () => {
      // Önce verilen URL'i dene
      let response = await fetch(url);

      // Olmadıysa ve /en/ ile başlıyorsa, prefix'i kaldırıp tekrar dene
      if (!response.ok && url.startsWith("/en/")) {
        const fallbackUrl = url.slice(3); // "/en" kısmını kaldır → "/trial/..."
        response = await fetch(fallbackUrl);

        if (!response.ok) {
          throw new Error(
            `Failed to load JSON from ${url} and fallback ${fallbackUrl}`
          );
        }
      } else if (!response.ok) {
        // /en/ ile başlamıyorsa normal hata
        throw new Error(`Failed to load JSON from ${url}`);
      }

      return response.json();
    })();

    dataCache.set(url, p);
    return p;
  }

  // Turkish-aware lowercase
  function turkishLower(str) {
    return str
      .replace(/I/g, "ı")
      .replace(/İ/g, "i")
      .toLowerCase();
  }

  // ------------------------------
  // 2. Overlay DOM creation
  // ------------------------------
  let overlay = null;
  let container = null;
  let closeBtn = null;

  function ensureWordcloudOverlay() {
    if (overlay) return;

    // <div id="wc-overlay" class="wc-overlay" hidden>
    overlay = document.createElement("div");
    overlay.id = "wc-overlay";
    overlay.className = "wc-overlay";
    overlay.hidden = true;

    const panel = document.createElement("div");
    panel.className = "wc-overlay-panel";

    // Close button
    closeBtn = document.createElement("button");
    closeBtn.type = "button";
    closeBtn.className = "wc-overlay-close";
    closeBtn.setAttribute("aria-label", UI_TEXT.closeLabel);
    closeBtn.textContent = "×";

    // ← EKLE: header + title
    const header = document.createElement("div");
    header.className = "wc-overlay-header";

    const titleEl = document.createElement("strong");
    titleEl.className = "wc-overlay-title";
    titleEl.textContent = UI_TEXT.title;

    header.appendChild(titleEl);
    header.appendChild(closeBtn);

    const body = document.createElement("div");
    body.className = "wc-overlay-body";

    const toolbar = document.createElement("div");
    toolbar.className = "wc-toolbar";

    const refreshBtn = document.createElement("button");
    refreshBtn.type = "button";
    refreshBtn.className = "wc-action wc-refresh";
    refreshBtn.textContent = UI_TEXT.refresh;

    const copyBtn = document.createElement("button");
    copyBtn.type = "button";
    copyBtn.className = "wc-action wc-copy";
    copyBtn.textContent = UI_TEXT.copy;

    const saveBtn = document.createElement("button");
    saveBtn.type = "button";
    saveBtn.className = "wc-action wc-save";
    saveBtn.textContent = UI_TEXT.save;

    toolbar.appendChild(refreshBtn);
    toolbar.appendChild(copyBtn);
    toolbar.appendChild(saveBtn);

    container = document.createElement("div");
    container.id = "wc-container";
    container.className = "wc-container";

    body.appendChild(toolbar);
    body.appendChild(container);
    panel.appendChild(header);
    panel.appendChild(body);
    overlay.appendChild(panel);
    document.body.appendChild(overlay);

    // Close handlers
    closeBtn.addEventListener("click", hideOverlay);

    overlay.addEventListener("click", evt => {
      // Click outside panel closes
      if (evt.target === overlay) {
        hideOverlay();
      }
    });

    // Toolbar bindings
    bindToolbar(overlay);
  }

  let currentResizeHandler = null;
  let currentState = null;

  function showOverlay() {
    ensureWordcloudOverlay();
    overlay.hidden = false;

    // Glass overlay (shared)
    if (glass && window.AppOverlay) {
      // zoom-overlay'in z-index değerini oku
      const panelZ = parseInt(window.getComputedStyle(overlay).zIndex, 10);

      // panelZ geçerli değilse fallback kullan
      const glassZ = Number.isFinite(panelZ) ? panelZ - 1 : 9998;

      // overlay-glass z-index'ini buna göre ayarla
      glass.style.zIndex = glassZ;

      AppOverlay.showOverlay(glass);
    }
  }

  function hideOverlay() {
    if (!overlay) return;

    overlay.hidden = true;
    // Optional: clear SVG when closing
    if (container) {
      container.innerHTML = "";
    }
    // Remove resize handler
    if (currentResizeHandler) {
      window.removeEventListener("resize", currentResizeHandler);
      currentResizeHandler = null;
    }
    currentState = null;

    if (glass && window.AppOverlay) {
      glass.style.zIndex = "";
      AppOverlay.hideOverlay(glass);
    }
  }

  // ------------------------------
  // 2b. Toolbar helpers (refresh / copy / save)
  // ------------------------------
  function getWordcloudBackgroundColor() {
    const panel = document.querySelector(".wc-overlay-panel");
    if (!panel) return null;

    const styles = getComputedStyle(panel);
    const bg = styles.backgroundColor;

    // Tamamen transparan ise fallback
    if (!bg || bg === "rgba(0, 0, 0, 0)" || bg === "transparent") {
      return "#ffffff"; // fallback
    }
    return bg;
  }

  function getWordcloudBodyColor() {
    const panel = document.querySelector(".wc-overlay-panel");
    const target = panel || document.body;
    const styles = getComputedStyle(target);

    // Önce CSS custom property'yi dene
    let c = styles.getPropertyValue("--bs-body-color");
    if (!c || !c.trim()) {
      // Yoksa normal text color'a düş
      c = styles.color;
    }
    return c && c.trim() ? c.trim() : "#000000";
  }

  function bindToolbar(overlayRoot) {
    if (!overlayRoot) return;

    const refreshBtn = overlayRoot.querySelector(".wc-refresh");
    const copyBtn    = overlayRoot.querySelector(".wc-copy");
    const saveBtn    = overlayRoot.querySelector(".wc-save");

    // Refresh: re-render with currentState
    if (refreshBtn) {
      refreshBtn.addEventListener("click", () => {
        if (currentState) {
          renderWordcloud(container, currentState);
        }
      });
    }

    // Copy: SVG → PNG → clipboard
    if (copyBtn) {
      copyBtn.addEventListener("click", copyPngToClipboard);
    }

    // Save: SVG → PNG → download
    if (saveBtn) {
      saveBtn.addEventListener("click", downloadPng);
    }
  }

  // Convert an SVG element to PNG Blob using a canvas
  function svgToPngBlob(svgElement, width, height, backgroundColor = "transparent") {
    const xml = new XMLSerializer().serializeToString(svgElement);
    const svgBlob = new Blob([xml], { type: "image/svg+xml;charset=utf-8" });
    const url = URL.createObjectURL(svgBlob);

    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => {
        const canvas = document.createElement("canvas");
        canvas.width = width;
        canvas.height = height;
        const ctx = canvas.getContext("2d");

        if (backgroundColor && backgroundColor !== "transparent") {
          ctx.fillStyle = backgroundColor;
          ctx.fillRect(0, 0, width, height);
        }

        ctx.drawImage(img, 0, 0);
        canvas.toBlob(blob => {
          URL.revokeObjectURL(url);
          if (blob) resolve(blob);
          else reject(new Error("canvas.toBlob failed"));
        }, "image/png");
      };
      img.onerror = err => {
        URL.revokeObjectURL(url);
        reject(err);
      };
      img.src = url;
    });
  }

  // Try to get SVG width/height from viewBox or bounding box
  function getSvgSize(svg) {
    const vb = svg.viewBox && svg.viewBox.baseVal;
    if (vb && vb.width && vb.height) {
      return { width: vb.width, height: vb.height };
    }
    const rect = svg.getBoundingClientRect();
    return {
      width: rect.width || 800,
      height: rect.height || 600
    };
  }

  // Copy visible wordcloud PNG to clipboard
  async function copyPngToClipboard() {
    if (!container) return;
    const svg = container.querySelector("svg");
    if (!svg) return;

    const { width, height } = getSvgSize(svg);
    const bgColor = getWordcloudBackgroundColor();
    const blob = await svgToPngBlob(svg, width, height, bgColor);

    if (!navigator.clipboard || !window.ClipboardItem) {
      alert(
        uiLang === "tr"
          ? "Tarayıcınız görselleri panoya kopyalamayı desteklemiyor."
          : "Your browser does not support copying images to the clipboard."
      );
      return;
    }

    await navigator.clipboard.write([
      new ClipboardItem({ "image/png": blob })
    ]);
  }

  // Download visible wordcloud as PNG
  async function downloadPng() {
    if (!container) return;
    const svg = container.querySelector("svg");
    if (!svg) return;

    const { width, height } = getSvgSize(svg);
    const bgColor = getWordcloudBackgroundColor();
    const blob = await svgToPngBlob(svg, width, height, bgColor);

    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "wordcloud.png";
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }

  // ------------------------------
  // 3. Debounce helper for resize
  // ------------------------------
  function debounce(fn, delay) {
    let timer = null;
    return function (...args) {
      if (timer) clearTimeout(timer);
      timer = setTimeout(() => fn.apply(this, args), delay);
    };
  }

  // ------------------------------
  // 4. Label-based color and opacity helpers
  // ------------------------------
  function buildLabelHelpers(labels, data) {
    // { label: [words...] } -> Map(word -> label)
    const otherColor = getWordcloudBodyColor();

    const labelByWord = new Map(
      Object.entries(labels).flatMap(([label, words]) =>
        words.map(w => [w, label])
      )
    );

    // Lower-case version of each word for matching
    const dataLower = data.map(d => turkishLower(d.text));

    // Frequency extent → opacity scale
    const valueExtent = d3.extent(data, d => d.value);
    const opacityScale = d3.scaleLinear()
      .domain(valueExtent)
      .range([0.4, 1]);   // low freq: faint, high freq: strong

    // Categories (= label keys) + "other"
    const labelDomain = [...Object.keys(labels), "other"];

    // Label → base categorical color
    const labelColor = d3.scaleOrdinal()
      .domain(labelDomain)
      .range(d3.schemeSet2);

    // Precompute lowercase patterns, sort by pattern length (desc)
    const labelPatterns = Array.from(labelByWord.entries())
      .map(([pattern, label]) => ({
        patternLower: turkishLower(pattern),
        label,
        length: pattern.length
      }))
      .sort((a, b) => d3.descending(a.length, b.length));

    function getLabel(lowerText) {
      for (const { patternLower, label } of labelPatterns) {
        if (lowerText.includes(patternLower)) {
          return label;
        }
      }
      return "other";
    }

    // Category-based color; "other" uses theme body color
    function colorFor(index) {
      const lowerText = dataLower[index];
      const label = getLabel(lowerText);

      if (label === "other") {
        return otherColor;
      }
      return labelColor(label);
    }

    // Frequency-driven opacity
    function opacityFor(value) {
      return opacityScale(value);
    }

    return { colorFor, opacityFor };
  }

  // ------------------------------
  // 5. Wordcloud renderer (d3 + d3-cloud)
  // ------------------------------
  // Map container width (px) → max font size
  const WC_MIN_CONTAINER = 303;
  const WC_MAX_CONTAINER = 686;
  const WC_MIN_MAX_FONT  = 30;
  const WC_MAX_MAX_FONT  = 65;

  function renderWordcloud(containerEl, state) {
    if (!containerEl || !window.d3 || !d3.layout || !d3.layout.cloud || !state) {
      return;
    }

    const { data, colorHelpers } = state;

    containerEl.innerHTML = "";

    const width = containerEl.clientWidth || 600;
    const height = containerEl.clientHeight || 400;

    const maxValue = d3.max(data, d => d.value);

    // Map container width [303, 686] → max font [30, 65], clamp ederek
    let maxFont;
    if (width <= WC_MIN_CONTAINER) {
      maxFont = WC_MIN_MAX_FONT;
    } else if (width >= WC_MAX_CONTAINER) {
      maxFont = WC_MAX_MAX_FONT;
    } else {
      const t = (width - WC_MIN_CONTAINER) / (WC_MAX_CONTAINER - WC_MIN_CONTAINER);
      maxFont = WC_MIN_MAX_FONT + t * (WC_MAX_MAX_FONT - WC_MIN_MAX_FONT);
    }

    const sizeScale = d3.scalePow().exponent(1.2)
      .domain([1, maxValue || 1])
      .range([10, maxFont]);

    const layout = d3.layout.cloud()
      .size([width, height])
      .words(
        data.map((d, idx) => ({
          text: d.text,
          size: sizeScale(d.value),
          value: d.value,
          index: idx
        }))
      )
      .padding(2)
      .rotate(() => 0)
      .font("sans-serif")
      .fontSize(d => d.size)
      .spiral("archimedean");

    layout.on("end", words => {
      const svg = d3.create("svg")
        .attr("viewBox", [-width / 2, -height / 2, width, height])
        .attr("width", width)
        .attr("height", height)
        .attr("style", "max-width: 100%; height: 100%; display: block;");

      svg.append("g")
        .selectAll("text")
        .data(words)
        .join("text")
          .attr("text-anchor", "middle")
          .attr("font-family", "sans-serif")
          .attr("font-size", d => d.size)
          .attr("fill", d => state.colorHelpers.colorFor(d.index))
          .attr("fill-opacity", d => state.colorHelpers.opacityFor(d.value))
          .attr("transform", d => `translate(${d.x},${d.y})rotate(${d.rotate})`)
          .text(d => d.text)
          .call(text => text.append("title")
                            .text(d => formatFrequencyTooltip(d)));

      containerEl.appendChild(svg.node());
    });

    layout.start();
  }

  // ------------------------------
  // 6. Trigger click handler
  // ------------------------------
  async function handleTriggerClick(btn) {
    const url = btn.getAttribute("data-json");
    if (!url) return;

    showOverlay();
    ensureWordcloudOverlay();

    try {
      // 1) Words JSON
      // 2) Label definitions (shared for all wordclouds)
      const [data, labels] = await Promise.all([
        getJsonOnce(url),
        getJsonOnce("/resources/json/word_labels.json")
      ]);

      const colorHelpers = buildLabelHelpers(labels, data);

      currentState = { data, colorHelpers };

      // Initial render
      renderWordcloud(container, currentState);

      // Resize listener (debounced)
      if (currentResizeHandler) {
        window.removeEventListener("resize", currentResizeHandler);
      }
      currentResizeHandler = debounce(() => {
        if (!overlay.hidden && currentState) {
          renderWordcloud(container, currentState);
        }
      }, 200);

      window.addEventListener("resize", currentResizeHandler);
    } catch (err) {
      console.error(err);
      hideOverlay();
    }
  }

  // ------------------------------
  // 7. Global event delegation for .wc-trigger
  // ------------------------------
  document.addEventListener("click", evt => {
    const btn = evt.target.closest(".wc-trigger");
    if (!btn) return;
    evt.preventDefault();
    handleTriggerClick(btn);
  });
})();

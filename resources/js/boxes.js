// Köşeli parantezli [metin] bölümlerini <span class="bracket-box">...</span> ile sarar
document.addEventListener("DOMContentLoaded", () => {
  const SKIP = new Set(['SCRIPT','STYLE','CODE','PRE','KBD','SAMP','NOSCRIPT', 'SUP']);
  const hasBracket = /\[/;

  const walker = document.createTreeWalker(
    document.body,
    NodeFilter.SHOW_TEXT,
    {
      acceptNode(node){
        const t = node.nodeValue;
        if (!t || !hasBracket.test(t)) return NodeFilter.FILTER_REJECT;

        let p = node.parentElement;
        while (p) {
          if (SKIP.has(p.tagName)) return NodeFilter.FILTER_REJECT;
          if (p.classList?.contains('bracket-box')) return NodeFilter.FILTER_REJECT;
          p = p.parentElement;
        }
        return NodeFilter.FILTER_ACCEPT;
      }
    }
  );

  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);

  nodes.forEach(node => {
    const original = node.nodeValue;
    const html = original.replace(/\[([^\[\]]+)\]/g, (_, inner) =>
      `<span class="bracket-box">${inner.trim()}</span>`
    );
    if (html !== original) {
      const span = document.createElement('span');
      span.innerHTML = html;
      node.replaceWith(...span.childNodes);
    }
  });
});

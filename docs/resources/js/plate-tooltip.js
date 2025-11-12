// tooltip.js (genel) — data-title olan HER öğe için çalışır
document.addEventListener('DOMContentLoaded', () => {
  const MARGIN = 8;
  const MAX_W  = 340;
  const SELECTOR = '[data-title]:not([data-title=""])';

  // Tek tooltip elemanı
  const tip = document.createElement('div');
  tip.id = 'plate-tip';            // mevcut CSS’inle uyum için adı koruyoruz
  document.body.appendChild(tip);

  let openFor = null;
  let locked  = false;
  let isTouch = matchMedia('(pointer: coarse)').matches;

  function clamp(v, a, b){ return Math.min(b, Math.max(a, v)); }

  function positionTip(el){
    const msg = el.getAttribute('data-title');
    if (!msg) return false;

    tip.textContent = msg;
    tip.style.maxWidth = Math.min(MAX_W, window.innerWidth - 2*MARGIN) + 'px';
    tip.style.display = 'block';

    const r  = el.getBoundingClientRect();
    const tr = tip.getBoundingClientRect();

    let x = r.left + r.width/2 - tr.width/2;   // merkez
    let y = r.top  - 6 - tr.height;            // üstte

    // Yatay taşma düzelt
    x = clamp(x, MARGIN, window.innerWidth - tr.width - MARGIN);

    // Üste sığmıyorsa alta
    if (y < MARGIN) {
      y = r.bottom + 6;
      if (y + tr.height > window.innerHeight - MARGIN) {
        tip.style.maxWidth = Math.min(tr.width, window.innerWidth - 2*MARGIN) + 'px';
      }
    }

    tip.style.left = Math.round(x) + 'px';
    tip.style.top  = Math.round(y) + 'px';
    return true;
  }

  function showFor(el){
    if (!positionTip(el)) return;
    openFor = el;
  }

  function closeTip(){
    tip.style.display = 'none';
    openFor = null;
    locked  = false;
  }

  // ---- Hover (desktop) ----
  document.addEventListener('mouseenter', (e) => {
    if (isTouch) return;
    const el = e.target.closest(SELECTOR);
    if (el) showFor(el);
  }, true);

  document.addEventListener('mouseleave', (e) => {
    if (isTouch) return;
    const el = e.target.closest(SELECTOR);
    if (el && !locked) closeTip();
  }, true);

  // ---- Touch / Click ----
  let touchStartY = 0;

  document.addEventListener('touchstart', (e) => {
    isTouch = true;
    if (e.touches && e.touches[0]) touchStartY = e.touches[0].clientY;
  }, { passive:true });

  document.addEventListener('touchmove', (e) => {
    if (!openFor) return;
    const y = e.touches && e.touches[0] ? e.touches[0].clientY : 0;
    if (Math.abs(y - touchStartY) > 6) { // scroll algıla -> kapat
      closeTip();
    }
  }, { passive:true });

  document.addEventListener('click', (e) => {
    const el = e.target.closest(SELECTOR);
    if (el) {
      // toggle: mobilde “kilitli” kalsın, tekrar tıklayınca kapansın
      if (openFor === el && locked) { closeTip(); }
      else { locked = true; showFor(el); }
      e.stopPropagation();
    } else {
      closeTip();
    }
  });

  // Yeniden konumlandır / kapat
  window.addEventListener('resize', () => { if (openFor) positionTip(openFor); });
  document.addEventListener('scroll', () => {
    if (!openFor) return;
    if (isTouch) closeTip();       // mobilde scroll -> kapat
    else positionTip(openFor);     // desktopta scroll -> yeniden konumla
  }, { passive:true });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') closeTip();
  });
});

// ../resources/js/plate-tooltip.js
document.addEventListener('DOMContentLoaded', () => {
  const MARGIN = 8;
  const MAX_W  = 340;
  const SELECTOR = '[data-title]:not([data-title=""])';

  const tip = document.createElement('div');
  tip.id = 'plate-tip';
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

    let x = r.left + r.width/2 - tr.width/2;
    let y = r.top  - 6 - tr.height;

    x = clamp(x, MARGIN, window.innerWidth - tr.width - MARGIN);

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

  // ---- küçük helper: event.target'ı güvenli şekilde ele al ----
  function closestTarget(e) {
    let t = e.target;
    // text node vs. ise parentElement'e çık
    if (t && t.nodeType !== 1) {
      t = t.parentElement;
    }
    if (!t || !t.closest) return null;
    return t.closest(SELECTOR);
  }

  // ---- Hover (desktop) ----
  document.addEventListener('mouseenter', (e) => {
    if (isTouch) return;
    const el = closestTarget(e);
    if (el) showFor(el);
  }, true);

  document.addEventListener('mouseleave', (e) => {
    if (isTouch) return;
    const el = closestTarget(e);
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
    if (Math.abs(y - touchStartY) > 6) {
      closeTip();
    }
  }, { passive:true });

  document.addEventListener('click', (e) => {
    const el = closestTarget(e);
    if (el) {
      if (openFor === el && locked) {
        closeTip();
      } else {
        locked = true;
        showFor(el);
      }
      e.stopPropagation();
    } else {
      closeTip();
    }
  });

  window.addEventListener('resize', () => {
    if (openFor) positionTip(openFor);
  });

  document.addEventListener('scroll', () => {
    if (!openFor) return;
    if (isTouch) closeTip();
    else positionTip(openFor);
  }, { passive:true });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') closeTip();
  });
});

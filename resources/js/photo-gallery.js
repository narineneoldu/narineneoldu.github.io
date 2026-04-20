/*
 * photo-gallery.js
 * Client-side behaviour for the photo-gallery shortcode output:
 * - Tag chip filter (multi-select OR across chips)
 * - Search box with && (AND) and || (OR) operators; AND > OR precedence
 * - Modal lightbox with keyboard navigation (Esc / ArrowLeft / ArrowRight)
 */

(function () {
  'use strict';

  function initGallery(gallery) {
    const chips = Array.from(gallery.querySelectorAll('.tag-chip'));
    const search = gallery.querySelector('.gallery-search');
    const cards = Array.from(gallery.querySelectorAll('.photo-card'));
    const modal = gallery.querySelector('.gallery-modal');
    const modalImg = modal.querySelector('.modal-img');
    const modalCaption = modal.querySelector('.modal-caption');
    const closeBtn = modal.querySelector('.modal-close');
    const prevBtn = modal.querySelector('.modal-prev');
    const nextBtn = modal.querySelector('.modal-next');

    const activeTags = new Set();
    let currentIndex = -1;
    let visibleCards = cards.slice();

    function matchesQuery(query, card) {
      if (!query) return true;
      const haystack = [
        card.dataset.tags || '',
        card.dataset.title || '',
        card.dataset.caption || '',
        card.dataset.date || ''
      ].join(' ').toLowerCase();

      // "a && b || c && d" == (a AND b) OR (c AND d)
      const orParts = query.split(/\s*\|\|\s*/).filter(Boolean);
      if (orParts.length === 0) return true;

      return orParts.some(function (orPart) {
        const terms = orPart
          .split(/\s*&&\s*/)
          .map(function (t) { return t.trim().toLowerCase(); })
          .filter(Boolean);
        if (terms.length === 0) return true;
        return terms.every(function (term) {
          return haystack.indexOf(term) !== -1;
        });
      });
    }

    function applyFilter() {
      const query = (search.value || '').trim();
      const hasChips = activeTags.size > 0;

      visibleCards = [];
      cards.forEach(function (card) {
        const cardTags = (card.dataset.tags || '').split(/\s+/).filter(Boolean);
        const chipMatch = !hasChips || cardTags.some(function (t) {
          return activeTags.has(t);
        });
        const searchMatch = matchesQuery(query, card);
        const visible = chipMatch && searchMatch;
        card.classList.toggle('hidden', !visible);
        if (visible) visibleCards.push(card);
      });
    }

    chips.forEach(function (chip) {
      chip.addEventListener('click', function () {
        const tag = chip.dataset.tag;
        if (activeTags.has(tag)) {
          activeTags.delete(tag);
          chip.classList.remove('active');
        } else {
          activeTags.add(tag);
          chip.classList.add('active');
        }
        applyFilter();
      });
    });

    search.addEventListener('input', applyFilter);

    function showCurrent() {
      if (currentIndex < 0 || currentIndex >= visibleCards.length) return;
      const card = visibleCards[currentIndex];
      const img = card.querySelector('img');
      modalImg.src = img.src;
      modalImg.alt = img.alt || '';
      modalCaption.innerHTML = card.dataset.description || '';
    }

    function openModal(card) {
      currentIndex = visibleCards.indexOf(card);
      if (currentIndex < 0) return;
      showCurrent();
      modal.setAttribute('aria-hidden', 'false');
      document.body.style.overflow = 'hidden';
    }

    function closeModal() {
      modal.setAttribute('aria-hidden', 'true');
      document.body.style.overflow = '';
    }

    function next() {
      if (visibleCards.length === 0) return;
      currentIndex = (currentIndex + 1) % visibleCards.length;
      showCurrent();
    }

    function prev() {
      if (visibleCards.length === 0) return;
      currentIndex = (currentIndex - 1 + visibleCards.length) % visibleCards.length;
      showCurrent();
    }

    cards.forEach(function (card) {
      card.addEventListener('click', function () { openModal(card); });
    });

    closeBtn.addEventListener('click', closeModal);
    prevBtn.addEventListener('click', prev);
    nextBtn.addEventListener('click', next);
    modal.addEventListener('click', function (e) {
      if (e.target === modal) closeModal();
    });

    document.addEventListener('keydown', function (e) {
      if (modal.getAttribute('aria-hidden') === 'true') return;
      if (e.key === 'Escape') closeModal();
      else if (e.key === 'ArrowRight') next();
      else if (e.key === 'ArrowLeft') prev();
    });

    applyFilter();
  }

  function initAll() {
    document.querySelectorAll('.photo-gallery[data-gallery]').forEach(initGallery);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initAll);
  } else {
    initAll();
  }
})();

document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('abbr[title]').forEach(el => {
    // title'ı koru (erişilebilirlik için), ayrıca data-title'a kopyala
    if (!el.hasAttribute('data-title')) el.setAttribute('data-title', el.getAttribute('title'));
    // mobilde tap ile odak alması için
    if (!el.hasAttribute('tabindex')) el.setAttribute('tabindex', '0');

    // iOS'ta dokunup tekrar dokununca kapanması için ufak dokunuş
    el.addEventListener('touchend', (e) => {
      if (document.activeElement === el) { el.blur(); }
      else { el.focus(); }
      e.preventDefault();
    }, {passive:false});
  });
});

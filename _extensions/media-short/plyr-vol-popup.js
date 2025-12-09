// /_extensions/media-short/plyr-ui.js

(function () {
  const NARROW_BREAKPOINT = 440; // px: media-block genişliği bunun altına inince dar layout

  // Her player için: bağlı media-block genişliğine göre .plyr-narrow class'ını güncelle
  function updateNarrowClass(player) {
    if (!player || !player.elements) return;

    const blockRoot =
      player._blockRoot ||
      player.elements.container.closest('.media-block');

    if (!blockRoot) return;

    const isNarrow = blockRoot.offsetWidth < NARROW_BREAKPOINT;
    blockRoot.classList.toggle('plyr-narrow', isNarrow);
  }

  // Mevcut volume slider'ı dar layout'ta popup gibi kullanan davranış
  function setupResponsiveVolume(player) {
    if (!player || player._responsiveVolumeInitialized) return;

    const plyrRoot = player.elements && player.elements.container;
    if (!plyrRoot) return;

    const blockRoot =
      player._blockRoot ||
      plyrRoot.closest('.media-block');

    const volContainer = plyrRoot.querySelector('.plyr__volume');
    const muteBtn = plyrRoot.querySelector('[data-plyr="mute"]');
    const volSlider = plyrRoot.querySelector(
      '.plyr__volume input[data-plyr="volume"]'
    );

    if (!blockRoot || !volContainer || !muteBtn || !volSlider) {
      return;
    }

    // Sayfada herhangi bir yere tıklanınca popup'ı kapat (dar layout'ta)
    document.addEventListener('click', (ev) => {
      // Dar layout değilse popup davranışını devreye sokma
      if (!blockRoot.classList.contains('plyr-narrow')) return;

      // Eğer tıklanan öğe mute butonu veya volume container içindeyse popup kapanmasın
      if (muteBtn.contains(ev.target) || volContainer.contains(ev.target)) {
        return;
      }

      // Diğer tüm durumlarda popup'ı kapat
      volContainer.classList.remove('volume-open');
    });

    // Mute butonuna tıklandığında:
    // - sadece dar layout'ta .volume-open class'ını toggle et
    muteBtn.addEventListener('click', () => {
      // Plyr kendi mute/unmute işini zaten yapıyor; biz sadece görünürlükle ilgileniyoruz
      if (!blockRoot.classList.contains('plyr-narrow')) {
        return;
      }

      // Eğer zaten açık ise class'ı değiştirme (kapatma)
      if (!volContainer.classList.contains('volume-open')) {
        volContainer.classList.add('volume-open');
      }
    });

    // Plyr kontrolleri tamamen gizlediğinde popup state'ini sıfırla
    if (player && player.on) {
      player.on('controlshidden', () => {
        volContainer.classList.remove('volume-open');
      });
    }

    // Genişlik değişince dar/geniş durumunu güncelle
    updateNarrowClass(player);
    window.addEventListener('resize', () => updateNarrowClass(player));

    player._responsiveVolumeInitialized = true;
  }

  function attachResponsiveHooks(player) {
    if (!player || !player.on) return;

    player.on('ready', () => {
      updateNarrowClass(player);
      setupResponsiveVolume(player);
    });
  }

  // Core script yeni player oluşturunca
  window.addEventListener('plyr-player-created', (ev) => {
    const player = ev.detail && ev.detail.player;
    if (!player) return;
    attachResponsiveHooks(player);
  });

  // Halihazırda oluşturulmuş player'lar için
  if (window.PlyrCore && Array.isArray(window.PlyrCore.players)) {
    window.PlyrCore.players.forEach((player) => {
      attachResponsiveHooks(player);
    });
  }


  // İstersen debug için dışarı aç
  window.PlyrUI = window.PlyrUI || {};
  window.PlyrUI.updateNarrowClass = updateNarrowClass;
  window.PlyrUI.setupResponsiveVolume = setupResponsiveVolume;
})();


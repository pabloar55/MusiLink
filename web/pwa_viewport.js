(() => {
  const isIos = /iPhone|iPad|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const isStandalone = window.matchMedia('(display-mode: standalone)').matches ||
    navigator.standalone === true;
  if (!isIos || !isStandalone) return;

  // Flutter scrolls inside its canvas. Restoring the HTML document's scroll
  // position can instead move its hit-test surface away from the visible UI.
  // Reproduced on iOS 26.5 with scrollY/visualViewport.offsetTop = 62 and the
  // Flutter view at y = -62; scrollTo(0, 0) restored correct taps immediately.
  if ('scrollRestoration' in window.history) {
    window.history.scrollRestoration = 'manual';
  }

  function isEditing() {
    let active = document.activeElement;
    while (active?.shadowRoot?.activeElement) {
      active = active.shadowRoot.activeElement;
    }
    return active && (
      active.matches('input, textarea, select') || active.isContentEditable
    );
  }

  function restoreOrigin() {
    // Safari needs to move the viewport for text entry and pinch zoom. Leave
    // those interactions alone; focusout/viewport events will retry afterwards.
    if (document.visibilityState !== 'visible' || isEditing()) return;
    const scale = window.visualViewport?.scale ?? 1;
    if (Math.abs(scale - 1) > 0.01) return;

    if (window.scrollX !== 0 || window.scrollY !== 0) {
      window.scrollTo(0, 0);
    }
  }

  let framePending = false;
  function scheduleRestore() {
    if (framePending) return;
    framePending = true;
    window.requestAnimationFrame(() => {
      framePending = false;
      restoreOrigin();
    });
  }

  window.addEventListener('pageshow', scheduleRestore);
  window.addEventListener('focus', scheduleRestore);
  window.addEventListener('scroll', scheduleRestore, { passive: true });
  document.addEventListener('visibilitychange', scheduleRestore);
  document.addEventListener('focusout', scheduleRestore);
  window.visualViewport?.addEventListener('resize', scheduleRestore);
  window.visualViewport?.addEventListener('scroll', scheduleRestore);

  restoreOrigin();
  scheduleRestore();
})();

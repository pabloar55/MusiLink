{{flutter_js}}
{{flutter_build_config}}

function hideAppLoader() {
  const loader = document.getElementById('app-loading');
  if (!loader) return;

  loader.classList.add('app-loading--hidden');
  loader.addEventListener('transitionend', () => loader.remove(), {
    once: true,
  });
  window.setTimeout(() => loader.remove(), 300);
}

_flutter.loader.load({
  config: {
    // Only applies to `flutter build web --wasm`. Flutter keeps Safari on
    // dart2js by default; Safari 26.2+ supports the required Wasm features and
    // older versions still fall back to dart2js + CanvasKit automatically.
    wasmAllowList: { blink: true, webkit: true },
  },
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();

    // Leave enough time for Flutter's first frame to reach the screen before
    // fading out the HTML loader.
    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(hideAppLoader);
    });
  },
});

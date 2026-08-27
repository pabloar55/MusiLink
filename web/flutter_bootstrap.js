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

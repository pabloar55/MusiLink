# Desfase de los toques en la PWA de iOS

## Diagnóstico (2026-09-05)

Se reprodujo en la PWA instalada de `musilink.app`, en el simulador iPhone 17
con iOS 26.5. El botón Atrás del perfil musical no respondía al tocar su
posición visible, incluso después de cerrar y volver a abrir la app.

El inspector remoto de Safari mostró:

- `window.scrollY = 62` y `visualViewport.offsetTop = 62`;
- `visualViewport.scale = 1`;
- `flutter-view.getBoundingClientRect().y = -62`;
- el único service worker que controlaba la página era
  `firebase-messaging-sw.js`.

Al ejecutar `window.scrollTo(0, 0)`, los tres desplazamientos pasaron a cero
y el mismo toque en Atrás volvió a navegar correctamente. Esto identifica un
desplazamiento del documento como causa inmediata; no demuestra qué evento
de iOS lo originó ni que los despliegues anteriores fueran responsables.

## Corrección

`web/pwa_viewport.js` se carga antes del bootstrap de Flutter y actúa solo
en una PWA de iOS. Desactiva la restauración del scroll HTML por el historial
y devuelve el documento al origen al arrancar, volver a primer plano o
recibir cambios del viewport. El desplazamiento de las listas sigue siendo
responsabilidad de Flutter.

No modifica el scroll mientras hay un editor enfocado o zoom. Reintenta al
perder el foco y al cambiar el viewport, agrupando los eventos por frame.
No recarga la app ni modifica almacenamiento, sesión o service workers.

## Verificación

```bash
npm run test:web-shell
flutter build web --release --base-href /
```

En el simulador, con el inspector remoto de Safari:

1. Abrir la PWA instalada con la nueva build y comprobar la navegación.
2. Sin ningún campo enfocado, ejecutar `window.scrollTo(0, 62)`. Tras el
   siguiente frame, comprobar que `scrollY` y el `y` de `flutter-view` son cero
   y que los botones siguen respondiendo en su posición visible.
3. Mandar la PWA a segundo plano, volver a abrirla y repetir los toques.
4. Abrir y cerrar el teclado en búsqueda/chat y comprobar que el campo sigue
   accesible, sin saltos durante la escritura.
5. Comprobar el zoom y el desplazamiento de las listas; repetir la prueba
   tras un arranque completo y, cuando sea posible, en un iPhone físico.

La reparación con `scrollTo` se verificó en la sesión que presentaba el fallo.
La persistencia tras reiniciar y el comportamiento en un dispositivo físico
deben validarse con la nueva build desplegada.

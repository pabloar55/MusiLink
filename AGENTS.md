# MusiLink

App social musical: Flutter/Dart, Riverpod, GoRouter y Firebase; backend TypeScript en `functions/`.

## Estructura

- `lib/screens/`, `lib/widgets/`, `lib/theme/`: interfaz; `lib/router/`: navegación y redirecciones.
- `lib/services/`: lógica e integraciones; `lib/providers/`: estado e inyección Riverpod; `lib/models/`: datos; `lib/utils/`: utilidades compartidas.
- `functions/src/`: backend por funcionalidad; `functions/src/index.ts`: exports. Edita TypeScript, no `functions/lib/`.
- `firestore.rules`, `storage.rules`, `firestore.indexes.json`: acceso e índices. Revisa su coherencia al cambiar lecturas/escrituras o esquemas.
- `web/`: shell PWA y service workers. Consulta `docs/ios_pwa_viewport.md` para viewport y `docs/firebase_hosting.md` para hosting.
- `lib/l10n/app_{en,es,fr,el}.arb`: textos. Actualiza los cuatro idiomas y ejecuta `flutter gen-l10n`; no edites localizaciones generadas a mano.
- `test/`: Flutter; `tests/`: reglas y PWA; `functions/test/`: backend.

## Convenciones

- Conserva los cambios existentes del usuario y mantén las modificaciones centradas en la tarea.
- Revisa la implementación relacionada y sus pruebas antes de modificar el comportamiento. Sigue los patrones del módulo afectado.
- Reutiliza servicios/providers y el tema existentes; evita lógica de negocio nueva en widgets.
- Spotify y Last.fm pasan por Cloud Functions; Spotify usa catálogo sin OAuth de usuario. Mantén credenciales en el backend.
- Usa `lib/utils/firestore_collections.dart` y `lib/utils/error_reporter.dart` para colecciones y errores.
- Mantén consistentes los contratos entre modelos Dart, Cloud Functions y reglas de Firebase.
- Modifica los archivos fuente y regenera sus derivados con las herramientas del proyecto.
- Consulta `docs/` para procedimientos de migración y despliegue. Ante discrepancias técnicas en README o `CLAUDE.md`, comprueba el código, los manifiestos y CI.

## Entorno

- Flutter/Dart: versiones en `pubspec.yaml` y `.github/workflows/ci.yml`. Instala dependencias con `flutter pub get`.
- Node: versión en `functions/package.json`. Instala dependencias con `npm ci` y `npm --prefix functions ci`.
- Las pruebas de emulación requieren Firebase CLI y Java 21. Usa los proyectos de prueba definidos en los scripts.
- CI crea un `.env` vacío antes del análisis y las pruebas; si falta localmente, créalo sin sobrescribir uno existente.

## Validación

Ejecuta desde la raíz los comandos correspondientes al cambio:

| Área | Comando |
| --- | --- |
| Formato Dart | `dart format <archivos_modificados>` |
| Análisis Flutter | `flutter analyze --no-fatal-infos` |
| Pruebas Flutter | `flutter test` o `flutter test <archivo_test>` |
| Google auth web | `flutter test --platform chrome test/services/google_reauthentication_test.dart` |
| Compilación backend | `npm --prefix functions run build` |
| Pruebas unitarias backend | `npm --prefix functions run test:unit` |
| Reglas Firestore | `npm run test:rules` |
| Reglas Storage | `npm run test:storage` |
| Shell PWA | `npm run test:web-shell` |

- Las pruebas de integración del backend están en los scripts `test:functions:*` de `package.json` y en `functions/package.json`. Estos scripts incluyen la compilación necesaria.
- Añade o actualiza pruebas al cambiar comportamiento y cubre los errores corregidos con pruebas de regresión. Valida también los consumidores de contratos compartidos.
- La validación completa de CI está definida en `.github/workflows/ci.yml`.
- Para cambios exclusivamente documentales, revisa contenido y diff.
- Al terminar, resume en español los cambios y la validación realizada; indica cualquier fallo o comprobación pendiente.

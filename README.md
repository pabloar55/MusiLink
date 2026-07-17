# MusiLink

**MusiLink** es una app social de música desarrollada en Flutter que conecta usuarios a través de sus gustos musicales. Los usuarios pueden descubrir personas con gustos compatibles, ver perfiles musicales públicos, chatear en tiempo real y compartir canciones con sus amigos.

## Características Principales

- **Descubrimiento Musical:** Encuentra personas afines gracias a un algoritmo de compatibilidad basado en artistas y géneros compartidos.
- **Perfil Musical:** Visualiza y edita tus artistas y géneros favoritos en tu perfil público.
- **Canción del Día:** Selecciona una pista diaria para compartir con tus amigos en el feed de descubrimiento.
- **Chat en Tiempo Real:** Comunícate con otras personas mediante mensajes gestionados por Firestore. Puedes compartir canciones directamente en el chat.
- **Gestión de Amistades:** Envía, acepta y gestiona solicitudes de amistad.
- **Búsqueda de Canciones y Artistas:** Busca en el catálogo de Spotify para enriquecer tu perfil y compartir música, sin necesidad de vincular tu cuenta de Spotify.
- **Notificaciones Push:** Recibe alertas de mensajes y solicitudes de amistad en tiempo real vía FCM.

## Tecnologías

- **Framework:** Flutter SDK ^3.11.5 (Dart)
- **Versión de app:** 1.0.6+10
- **Backend:** Firebase Auth, Firestore, Cloud Functions, Remote Config, Storage, Analytics, Crashlytics y FCM
- **Búsqueda musical:** Spotify Web API vía Cloud Functions, con apoyo de Last.fm para géneros y artistas similares
- **Internacionalización:** `flutter_localizations` + `intl` (EN, ES, FR, EL)
- **Gestión de estado:** Riverpod (`flutter_riverpod` ^3.3.1)
- **Navegación:** GoRouter (`go_router` ^17.2.3)
- **UI/UX:** Material Design 3, soporte nativo Dark/Light mode y paleta personalizada estilo Spotify

### Dependencias principales

| Paquete | Versión |
|---|---|
| flutter_riverpod | ^3.3.1 |
| go_router | ^17.2.3 |
| firebase_core | ^4.6.0 |
| firebase_auth | ^6.4.0 |
| cloud_firestore | ^6.3.0 |
| cloud_functions | ^6.2.0 |
| firebase_storage | ^13.3.0 |
| firebase_messaging | ^16.2.0 |
| firebase_crashlytics | ^5.2.0 |
| firebase_analytics | ^12.3.0 |
| flutter_local_notifications | ^21.0.0 |
| google_sign_in | ^7.2.0 |
| cached_network_image | ^3.4.1 |
| image_picker | ^1.2.2 |
| flutter_secure_storage | ^10.0.0 |
| shared_preferences | ^2.5.5 |
| lucide_icons_flutter | ^3.1.13 |
| font_awesome_flutter | ^11.0.0 |
| url_launcher | ^6.3.2 |

## Estructura del Proyecto

El proyecto sigue una arquitectura en capas con separación clara de responsabilidades:

```text
lib/
├── models/       # DTOs inmutables con serialización Firestore (User, Artist, Chat, Message, Track...)
├── services/     # Lógica de negocio e integración con Firebase, Spotify y Last.fm
├── providers/    # Wiring de Riverpod: Firebase, servicios, streams y estado de features
├── screens/      # Vistas completas (ConsumerWidget / ConsumerStatefulWidget)
├── widgets/      # Componentes UI reutilizables, organizados por feature
├── router/       # AppRouterNotifier y configuración de GoRouter
├── theme/        # Material 3, paleta Spotify-green y variantes dark/light
├── utils/        # Colecciones Firestore, ErrorReporter, cachés y helpers de normalización
└── l10n/         # Traducciones .arb y código generado (EN, ES, FR, EL)
```

### Pantallas

| Pantalla | Descripción |
|---|---|
| `splash_screen` | Pantalla de carga inicial |
| `auth_screen` | Login / registro con Google Sign-In y email |
| `username_setup_screen` | Configuración inicial del nombre de usuario |
| `artist_selector_screen` | Selección y edición de artistas favoritos |
| `onboarding_screen` | Flujo de bienvenida para nuevos usuarios |
| `photo_setup_screen` | Configuración de foto de perfil |
| `main_screen` | Hub principal con Discover, Chat, Friends y Stats |
| `discover_screen` | Feed de compatibilidad y canción del día |
| `messages_screen` | Bandeja de conversaciones |
| `chat_screen` | Chat en tiempo real con canciones compartidas y reacciones |
| `friends_screen` | Lista de amigos y solicitudes pendientes |
| `user_profile_screen` | Perfil público de otro usuario |
| `user_search_screen` | Búsqueda de usuarios |
| `stats_screen` | Estadísticas musicales del perfil |
| `account_settings_screen` | Configuración de cuenta, notificaciones y privacidad |
| `blocked_users_screen` | Gestión de usuarios bloqueados |
| `privacy_policy_screen` | Política de privacidad |

## Cloud Functions (`functions/src/`)

Las funciones están escritas en TypeScript, usan Node.js 24 y se despliegan en `europe-southwest1`.

**`index.ts` - Notificaciones y recomendaciones:**

- `onNewMessage` - notifica al destinatario cuando llega un mensaje nuevo.
- `onFriendRequest` - notifica al usuario objetivo ante una nueva solicitud de amistad.
- `onFriendRequestAccepted` - notifica al solicitante cuando la solicitud es aceptada y elimina el documento de solicitud.
- `onUserMusicProfileCreated` - crea el índice musical y las recomendaciones iniciales de un usuario nuevo.
- `onUserMusicProfileChanged` - actualiza el índice de recomendación, refresca recomendaciones propias y recalcula coincidencias recíprocas.

**`spotify.ts` - Catálogo musical:**

- `searchSpotifyArtists` - busca artistas en Spotify con ranking local, imágenes, géneros y enriquecimiento opcional vía Last.fm.
- `searchSpotifyTracks` - busca pistas en Spotify para compartirlas en chats o como canción del día.

**`lastfm.ts` - Artistas relacionados:**

- `getSimilarArtists` - devuelve artistas similares desde Last.fm, filtrando colaboraciones como `feat.` o `ft.`.

Las credenciales externas se almacenan en Google Secret Manager y nunca en el código fuente:

```bash
firebase functions:secrets:set SPOTIFY_CLIENT_ID
firebase functions:secrets:set SPOTIFY_CLIENT_SECRET
firebase functions:secrets:set LASTFM_API_KEY
```

## Algoritmo de Compatibilidad

El porcentaje de afinidad musical (rango 0-100) combina dos señales para no penalizar perfiles con listas grandes:

- **70%** - similitud de artistas compartidos
- **30%** - similitud de géneros compartidos

Para cada bloque se calcula:

```text
cobertura = coincidencias / min(total_usuario_a, total_usuario_b)
evidencia = min(coincidencias / umbral_de_evidencia, 1)
similitud = max(cobertura, evidencia)
```

Los umbrales actuales son **7 artistas** y **4 géneros**. Así, una coincidencia completa en perfiles pequeños sigue puntuando alto por cobertura, mientras que compartir muchas coincidencias reales también cuenta como una señal fuerte aunque ambos perfiles sean grandes.

Ejemplos:

- 2 de 2 artistas compartidos aportan `70` puntos por cobertura completa.
- 5 artistas compartidos entre perfiles de 15 artistas aportan `50` puntos: `min(5 / 7, 1) * 70`.
- 5 artistas y 2 géneros compartidos aportan `65` puntos: `50` por artistas + `15` por géneros.

Antes de comparar se normalizan nombres con `trim`, lowercase y deduplicado para evitar que mayúsculas, espacios o valores repetidos distorsionen la puntuación.

Las recomendaciones se almacenan en `users/{uid}/recommendations`, se limitan a 100 resultados, se muestran en páginas de 20 elementos y se cachean durante 30 minutos en `MusicProfileService`. Los usuarios bloqueados se filtran antes de mostrar resultados.

## Flujo de Navegación

El estado de autenticación dirige el enrutado:

```text
splash -> auth -> username-setup -> artist-select -> onboarding -> photo-setup -> main
```

Desde `main` se accede a búsqueda de usuarios, perfiles, chats, ajustes, usuarios bloqueados y política de privacidad. `AppRouterNotifier` escucha `FirebaseAuth.authStateChanges()` y redirige según si el usuario está autenticado y ha completado el onboarding.

## Actualizaciones obligatorias

Firebase Remote Config define la build mínima admitida. Android usa la interfaz nativa de Google Play In-App Updates en modo inmediato; iOS abre App Store. La configuración y el orden seguro de publicación están en [`docs/mandatory_updates.md`](docs/mandatory_updates.md).

## Privacidad y Seguridad

Las reglas de seguridad de Firestore garantizan la privacidad:

- Los usuarios pueden leer perfiles ajenos, pero solo el propietario puede modificar su propio documento en `users`.
- Las conversaciones (`chats` y `messages`) están bloqueadas para que únicamente los participantes tengan acceso.
- Las solicitudes de amistad restringen modificación y eliminación a los usuarios involucrados.
- Los datos privados, como tokens FCM, preferencias de notificación y usuarios bloqueados, viven en `user_private`.

---

*Desarrollado con Flutter.*

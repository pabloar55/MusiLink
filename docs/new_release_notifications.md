# Novedades de tus artistas

MusiLink sigue en Spotify a los artistas que cada usuario tiene en su perfil y:

- Muestra en «Descubrir» › «Novedades» tarjetas con los singles y álbumes de los
  últimos 7 días. Cada tarjeta abre el lanzamiento en Spotify.
- Envía un único aviso a la semana, **los sábados a las 11:30 hora local**:
  «Escucha la nueva canción de Rosalía», con el título como cuerpo. Si hay
  novedades de varios artistas, se destaca la más reciente y se nombra al resto:
  «Canción · También hay novedades de Aitana y Quevedo». Al pulsarlo se abre la
  sección «Novedades» (`/?tab=releases`).

El backend está en `functions/src/artist_releases.ts`; el cliente, en
`lib/services/artist_release_service.dart`, `lib/providers/artist_releases_provider.dart`
y `lib/widgets/releases/`.

## Datos: `artist_releases/{spotifyId}`

| Campo | Contenido |
| --- | --- |
| `name` | Nombre con el que se registró (solo diagnóstico). |
| `nextCheckAt`, `checkedAt` | Planificación de las revisiones. |
| `knownReleaseIds` | Hasta 50 lanzamientos ya vistos. Su ausencia indica que falta la primera revisión. |
| `recentReleases` | Hasta 10 lanzamientos de los últimos 30 días: `id`, `name`, `type` (`single`/`album`), `releaseDate` (`YYYY-MM-DD`), `imageUrl` (`i.scdn.co`), `detectedAt` y `announce`. |

Es catálogo público de Spotify: cualquier usuario autenticado puede leerlo y
solo Cloud Functions lo escribe. El contrato de `recentReleases` es
`StoredRelease` en TypeScript y `ArtistRelease` en Dart. La pausa por cuota se
guarda en `scheduler_state/artist_release_checks`, que solo usa el backend.

## Registro: `syncWatchedArtists`

A diario (03:20 UTC) recorre los perfiles y crea el documento de cada artista con
`spotifyId` que aún no se vigila, con revisión inmediata. Un artista nuevo
aparece en la sección como mucho al día siguiente; no hace falta migrar nada
tras el despliegue. Los artistas sin `spotifyId` (perfiles antiguos) no se
vigilan.

## Revisión: `checkArtistReleases`

Se ejecuta cada hora (minuto 7) y revisa hasta 150 artistas con `nextCheckAt`
vencido, del más antiguo al más reciente. Cada artista se revisa una vez al día:

1. Si ningún usuario lo tiene en `topArtistKeys`, borra el documento sin llamar
   a Spotify.
2. Consulta `GET /v1/artists/{id}/albums` dos veces (`single` y `album`, con
   `limit=10`, el máximo en Development Mode) usando el token de aplicación (Client
   Credentials).
3. Guarda en `recentReleases` lo publicado en los últimos 30 días, conservando
   el `detectedAt` y `announce` de cada lanzamiento ya conocido.
4. Marca `announce` en un lanzamiento si no estaba en `knownReleaseIds` y su
   fecha cae entre hace 7 días y mañana. La primera revisión de un artista no
   anuncia nada: lo anterior se muestra en la app pero no genera aviso. Así se
   descartan también las reediciones y los cambios de orden del catálogo.

La frecuencia de revisión no cambia el número de avisos, que siempre es uno a la
semana como máximo.

### Límites de Spotify

La cuota de Development Mode es por cuenta de desarrollador y **la comparten
estas revisiones y las búsquedas de los usuarios**. Para no quitársela a las
búsquedas:

- Un `429` normal detiene la ejecución; los artistas restantes se revisan en la
  siguiente hora.
- Un `429` con `"reason": "QUOTA_EXCEEDED"` pausa todas las revisiones durante
  el `Retry-After` (como mínimo una hora) o, si no lo hay, 6 horas
  (`quotaExceededPauseMs`), y lo registra como aviso.
- Un `400`/`404` aplaza al artista 7 días y cualquier otro error, una hora.

Capacidad aproximada: unos 3600 artistas distintos al día, con hasta 300
peticiones por ejecución. Si las búsquedas empiezan a recibir `429`, reduce
`releaseCheckBatchSize` o solicita Extended Quota.

## Aviso semanal: `sendWeeklyReleaseNotifications`

Se ejecuta cada 15 minutos los viernes y sábados UTC, que es cuando cae el sábado
a las 11:30 en algún huso. Selecciona los perfiles privados cuyo
`utcOffsetMinutes` corresponde a ese momento. Un usuario recibe el aviso si se
cumplen todas estas condiciones:

- No ha desactivado «Novedades semanales de tus artistas» en ajustes
  (`user_private/{uid}.notifNewReleases`).
- Alguno de sus artistas tiene un lanzamiento con `announce` detectado en los
  últimos 8 días y después del último aviso
  (`user_private/{uid}.newReleasePushAt`, solo del backend).
- La cuenta está activa y no tiene una baja pendiente.

La marca se escribe en una transacción antes de enviar: un reintento no repite
el aviso y, si el envío falla, esa semana se pierde. Usa el canal y las
preferencias de sonido y vibración habituales, con la etiqueta `new_release`.

## Sección «Novedades» en la app

`weeklyReleasesProvider` lee de una vez (`whereIn`, hasta 30 identificadores)
los documentos de los artistas del perfil y muestra lo publicado en los últimos 7
días, incluido hoy. Los lanzamientos se ordenan del más reciente al más antiguo y,
el mismo día, el álbum va antes. Una colaboración entre artistas seguidos aparece
una sola vez. El resultado se guarda durante la sesión y se vuelve a cargar al
cambiar la selección de artistas o al deslizar para actualizar.

## Despliegue

1. Publica `firestore.rules`: el cliente lee `artist_releases` y escribe
   `notifNewReleases`, y ambas cosas fallan con las reglas anteriores.
2. Despliega `syncWatchedArtists`, `checkArtistReleases` y
   `sendWeeklyReleaseNotifications`. Usan los secretos `SPOTIFY_CLIENT_ID` y
   `SPOTIFY_CLIENT_SECRET` ya existentes.
3. Ejecuta `syncWatchedArtists` a mano desde Cloud Scheduler para no esperar a
   las 03:20 y comprueba en los registros que `checkArtistReleases` completa
   ciclos sin `rateLimited: true`.
4. Distribuye el cliente.

Pruebas: `npm --prefix functions run test:unit`,
`npm --prefix functions run test:artist-releases` (emulador de Firestore),
`npm run test:rules` y `flutter test test/services/artist_release_service_test.dart`.

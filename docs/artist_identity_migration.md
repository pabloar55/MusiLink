# Migración de identidad de artistas

Las recomendaciones identifican ahora cada artista con una clave estable:

```text
spotify:{spotifyId}
name:{nombreNormalizado}
```

`spotify:` es la identidad principal. `name:` se usa para artistas de Last.fm,
datos antiguos o resultados que no pudieron resolverse en Spotify. Si ambos
artistas tienen un ID de Spotify, solo coinciden cuando los IDs son iguales. Si
uno de los dos no tiene ID, el nombre normalizado sirve como puente.

Los campos existentes (`topArtists` y `topArtistNames`) se conservan. Los campos
nuevos son:

```text
topArtistKeys
artistIdentityVersion: 1
```

## Qué hace el migrador

`backfill-artist-identity-keys.cjs` solo utiliza datos que ya existen en
Firestore:

- reutiliza `topArtists[].spotifyId` cuando está disponible;
- genera un fallback `name:` determinista cuando falta;
- no consulta Spotify, Last.fm ni ningún otro servicio;
- no elimina ni modifica los artistas existentes;
- es idempotente y escribe en lotes de 400 perfiles;
- genera un informe agregado sin UIDs.

El informe contiene dos listas completas:

- `artistsWithSpotifyId`, agrupada por ID de Spotify;
- `artistsWithoutSpotifyId`, agrupada por nombre normalizado.

Cada entrada indica variantes de nombre, selecciones totales y número de
usuarios afectados. Esto permite estimar el beneficio y coste de un
enriquecimiento posterior sin exponer qué usuario eligió cada artista.

## Preparación

El script usa Application Default Credentials:

```bash
gcloud auth application-default login
```

Antes de permitir que clientes escriban los campos nuevos, desplegar las reglas:

```bash
firebase deploy --only firestore:rules --project musi-link-e7759
```

Después, desplegar las Functions y publicar el cliente actualizado.

## Simulación e informe

Desde `functions`:

```bash
npm run migrate:artist-keys -- --project musi-link-e7759
```

No se escribe ningún documento. El informe completo se guarda por defecto en:

```text
functions/artist-key-migration-report.json
```

Se puede elegir otra ruta o imprimir todas las entradas:

```bash
npm run migrate:artist-keys -- \
  --project musi-link-e7759 \
  --report ../artist-report.json \
  --print-artists
```

## Aplicación

Después de revisar el informe:

```bash
npm run migrate:artist-keys -- \
  --project musi-link-e7759 \
  --apply
```

El script vuelve a leer todos los perfiles y verifica que no quede ninguno
pendiente. También se puede verificar por separado:

```bash
npm run migrate:artist-keys -- \
  --project musi-link-e7759 \
  --verify-only
```

## Alcance de esta primera fase

El backfill prepara los perfiles y permite que la app use las identidades
híbridas en nuevos cálculos. No consulta catálogos ni regenera masivamente el
índice de recomendaciones.

El índice existente conserva los tokens de nombre, que las Functions nuevas
siguen consultando por compatibilidad. Los documentos del índice incorporarán
`topArtistKeys` cuando el perfil musical vuelva a cambiar. Después de valorar
`artistsWithoutSpotifyId`, se debe decidir entre:

1. aceptar una transición gradual;
2. enriquecer primero los nombres sin ID y después reindexar;
3. ejecutar directamente un reindexado controlado.

Separar estas fases evita regenerar recomendaciones para todos los usuarios
antes de saber cuántos artistas requieren resolución externa.

## Rollback

Los campos son aditivos. Una versión anterior de la app y de las Functions los
ignora. No es necesario eliminarlos para revertir el código.

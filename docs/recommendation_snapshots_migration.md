# Migración de snapshots de recomendaciones

Discovery consume un resumen público incluido en cada documento de recomendación:

```text
users/{ownerUid}/recommendations/{candidateUid}
```

El contrato añadido es:

```text
snapshotVersion: 1
profileSnapshot:
  displayName
  username
  photoUrl
  topArtistNames
  topGenreNames
snapshotGeneratedAt
```

Los campos existentes (`userId`, `score`, `sharedArtistNames`,
`sharedGenreNames` y `generatedAt`) se conservan.

El cliente no consulta `users` como fallback para hidratar Discovery. Por eso el
orden de publicación es obligatorio.

## Preparación

El script utiliza Application Default Credentials:

```bash
gcloud auth application-default login
```

Todas las órdenes incluyen explícitamente el proyecto para evitar escrituras en
otro entorno.

## Orden de publicación

1. Desplegar el índice de colección necesario para sincronizar cambios de
   nombre, usuario y foto:

   ```bash
   firebase deploy --only firestore:indexes --project musi-link-e7759
   ```

2. Esperar a que el índice de `recommendations.userId` figure como habilitado
   en Firebase Console.

3. Desplegar las Functions nuevas antes de migrar. Así una regeneración no
   vuelve a escribir el formato antiguo:

   ```bash
   firebase deploy \
     --only functions:onUserMusicProfileCreated,functions:onUserMusicProfileChanged \
     --project musi-link-e7759
   ```

4. Ejecutar la simulación:

   ```bash
   cd functions
   npm run migrate:recommendation-snapshots -- --project musi-link-e7759
   ```

5. Revisar que no haya recomendaciones inválidas. El script cancela la
   escritura si falta un usuario o su perfil público no es válido.

6. Aplicar el backfill:

   ```bash
   npm run migrate:recommendation-snapshots -- \
     --project musi-link-e7759 \
     --apply
   ```

7. Repetir la verificación independientemente:

   ```bash
   npm run migrate:recommendation-snapshots -- \
     --project musi-link-e7759 \
     --verify-only
   ```

8. Publicar el cliente móvil y la web únicamente después de que la verificación
   termine con `Pendientes: 0` e `Inválidas: 0`.

## Propiedades del migrador

- Es idempotente: puede ejecutarse más de una vez.
- El modo predeterminado no escribe.
- Actualiza con `merge` y nunca elimina documentos.
- Conserva puntuaciones, coincidencias y fechas de generación.
- Escribe en lotes de 400 operaciones.
- Después de `--apply` vuelve a leer y verificar toda la migración.

## Rollback

Los snapshots son campos adicionales, por lo que no es necesario eliminarlos si
se revierte una Function. Antes de publicar el cliente, cualquier incidencia se
resuelve corrigiendo el backend y repitiendo el migrador.

Después de publicar el cliente sin fallback, la recuperación consiste en
restaurar o volver a generar los snapshots. En móvil se puede bloquear una build
mediante Remote Config cuando la sustituta ya esté disponible. Este bloqueo no
se aplica a Flutter web, por lo que una incidencia web requiere volver a
desplegar la versión anterior.

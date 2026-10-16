# Migración de notificaciones a Firebase Installation ID

El cliente usa `register()` / `onRegistered` y `unregister()`. El listener
se instala antes de registrar. Los eventos automáticos guardan el FID sin
volver a llamar a `register()`, que emite un evento incluso si el FID no cambia.
La espera del evento está acotada a 15 segundos y el cierre de sesión mantiene
su limpieza independiente de Firestore y FCM, con recuperación persistente.

## Datos y compatibilidad

Se conserva `user_private/{uid}/push_tokens/{installationId}`. Su ID sigue
siendo el identificador aleatorio local existente, no el FID. El registro
nuevo reemplaza `token` por `fid` en el mismo documento; no los mezcla.
El backend admite ambos formatos para que las versiones antiguas sigan
recibiendo notificaciones. Conserva los payloads, canales, sonido, navegación
y confirmaciones de entrega del chat.

El FID sobrevive a unregister/register. Una limpieza sin red podría dejar un
registro de la cuenta anterior. Por eso cada alta escribe atómicamente también
`push_installations/{fid}` con `uid`, `installationId` y `updatedAt`. El backend
solo envía al propietario actual y, si falta esa asociación, omite el envío.
Las reglas impiden leer y borrar las asociaciones desde el cliente. Cada
reclamación exige un registro privado con el mismo FID actualizado en la misma
operación; los registros privados deben coincidir con su asociación. El backend
comprueba además el propietario antes de cada envío, de forma independiente
por destino: un fallo de lectura no impide enviar a los demás dispositivos.
El cierre de sesión borra el registro privado; la asociación puede permanecer
hasta una nueva sesión o el borrado de cuenta.
No se usa esa asociación por sí sola como destino de notificaciones.
El borrado de cuenta retira sus asociaciones mediante una transacción para no
borrar una instalación transferida entretanto a otra cuenta.

No hay conversión masiva de tokens existentes: cada instalación migra al
abrir la nueva versión y registrar su FID. Los tokens de otras instalaciones
se conservan. El service worker usa Firebase JS 13.0.0, la versión de
`firebase_core_web` instalada. Android e iOS activan explícitamente FID en
sus manifiestos.

## Orden de publicación posterior

Esta migración se ha preparado sin hacer deploy. Cuando se autorice publicar:

1. Publicar primero las reglas que aceptan ambos formatos y las Functions
   que usan `sendNotification`, además de `processAccountDeletion`.
2. Publicar después los clientes Android/iOS y la web con su nuevo worker.
3. Mantener el soporte de tokens mientras existan versiones antiguas activas.

No publicar el cliente FID antes del backend y las reglas. No revertir el
backend a una versión que solo envía tokens tras haber migrado clientes.
No mezclar las APIs de registro antiguas y nuevas en la misma instalación.

## Validación

```bash
flutter analyze --no-fatal-infos
flutter test test/services/push_token_registry_test.dart test/services/notification_service_test.dart test/screens/notification_startup_test.dart
flutter test --platform chrome test/services/push_token_registry_test.dart
npm --prefix functions run test:unit
npm run test:rules
npm --prefix functions run test:push-registration
npm run test:web-shell
```

La integración FID también forma parte de CI. Las comprobaciones locales
se ejecutaron con Node 26 y Java 25; CI usa Node 24 y Java 21.

Antes de publicar, comprobar con dispositivos reales Android, iOS y PWA:
registro inicial, actualización desde token, permisos denegados, primer plano,
segundo plano/app cerrada, cambio de cuenta y cierre de sesión sin red. Los
emuladores validan los contratos y permisos, pero no la entrega real de FCM.

Referencias:
- [Registro FID en Flutter](https://firebase.google.com/docs/cloud-messaging/flutter/get-started#access_the_firebase_installation_id).
- [Administración de registros](https://firebase.google.com/docs/cloud-messaging/manage-tokens).

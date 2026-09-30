# Chats grupales: primera versión

Desde el botón flotante de Mensajes se eligen entre 2 y 19 amigos en una
primera pantalla con buscador. La flecha flotante permite pasar, al seleccionar
al menos dos amigos, a una segunda pantalla para poner el nombre y crear el grupo.
El creador también es miembro; el máximo total es 20. Los grupos vacíos aparecen
en la lista desde su creación. La cabecera abre la lista de miembros.
Se reutilizan el historial paginado, los mensajes de texto, las canciones,
las reacciones, las denuncias y el borrado suave personal.

## Contrato y permisos

- Los chats individuales existentes conservan su esquema y sus IDs deterministas.
- Los grupos usan un ID aleatorio de Firestore, `type: group`, `name`,
  `createdBy`, `participants` y `lastReadAt` por UID.
- `createGroupChat` exige autenticación y App Check. Valida en una transacción
  que todos estén activos, que sean amigos mutuos del creador y que no haya
  bloqueos entre miembros. Permite cinco creaciones por hora y usuario.
  El cliente reutiliza el ID al reintentar una creación.
- La pertenencia autoriza los envíos posteriores aunque termine una amistad.
  Un bloqueo entre el remitente y un miembro activo impide el envío al grupo.
  Una cuenta eliminada no impide conversar al resto.
- `sendChatMessage` conserva su cuota y añade `groupMessage: true` en los grupos.
  Los resúmenes, participantes y metadatos solo los escribe el backend.
- La lectura actualiza únicamente `lastReadAt[uid]` y `unreadCounts[uid]`.
  Su límite es el último mensaje confirmado mostrado; el trigger respeta esa
  marca aunque llegue tarde. Los grupos no usan los booleanos compartidos
  `read`/`delivered` ni muestran ticks de entrega o lectura.
- Las notificaciones se envían a los demás miembros y abren `/group-chat/:id`.
  Cada destinatario completado se registra para los reintentos del trigger.
- La eliminación de una cuenta conserva el grupo, incluso sin mensajes, y
  mantiene la referencia anonimizada como en los chats individuales.

## Activación y alcance pendiente

Requiere desplegar las funciones modificadas, incluida `createGroupChat`, y las
reglas de Firestore antes de publicar el cliente. No requiere migrar chats
existentes, nuevos índices ni cambios de Storage. El procedimiento general está
en [firebase_hosting.md](firebase_hosting.md).

Quedan para siguientes iteraciones: añadir o expulsar miembros, salir del grupo,
roles de administrador, editar nombre/foto y recibos de lectura por miembro.
Ocultar una conversación no equivale a abandonar el grupo.

Las pruebas de `ChatService` y `AuthenticatedCallableClient` cubren el transporte
de creación, sus errores, el timeout y la reutilización del ID al reintentar.
Queda pendiente verificar el flujo grupal completo con varias cuentas y las
notificaciones en dispositivos reales tras desplegar el backend.

## Creación desde Safari y la PWA

En el simulador iOS, el token FCM puede quedarse pendiente aun con el permiso de
notificaciones concedido. El SDK web de Functions espera ese token opcional antes
de enviar la petición y de iniciar su timeout. En la creación web se usa el
[protocolo callable de Firebase](https://firebase.google.com/docs/functions/callable-reference)
con los tokens de Auth y App Check, sin solicitar FCM. Las comprobaciones del
backend y las reglas conservan los mismos permisos.

La petición, incluida la obtención de tokens, tiene un límite de 30 segundos.
La lectura posterior del grupo tiene un límite de 10 segundos. Si se agota la
espera, se muestra un error de conexión y se permite reintentar con el mismo ID;
el backend mantiene la creación idempotente. Esta corrección requiere publicar
el cliente web; no modifica las funciones, las reglas ni el esquema.

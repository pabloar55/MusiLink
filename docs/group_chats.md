# Chats grupales: primera versión

Desde el botón flotante de Mensajes se eligen entre 2 y 19 amigos en una
primera pantalla con buscador. La flecha flotante permite pasar, al seleccionar
al menos dos amigos, a una segunda pantalla para poner el nombre, elegir
opcionalmente una foto y crear el grupo.
El creador también es miembro; el máximo total es 20. Los grupos vacíos aparecen
en la lista desde su creación. La cabecera abre los datos del grupo: foto,
miembros y las opciones de añadir miembros y de salir.
Se reutilizan el historial paginado, los mensajes de texto, las canciones,
las reacciones, las denuncias y el borrado suave personal.

## Contrato y permisos

- Los chats individuales existentes conservan su esquema y sus IDs deterministas.
- Los grupos usan un ID aleatorio de Firestore, `type: group`, `name`,
  `createdBy`, `participants`, `lastReadAt` por UID y, opcionalmente, `photoUrl`.
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
  mantiene la referencia anonimizada como en los chats individuales, mientras
  quede algún miembro con la cuenta sin eliminar (véase «Grupos sin cuentas
  activas»).

## Foto del grupo

- La foto se guarda en Storage como `group_photos/{chatId}` (JPEG, menos de
  5 MB). Solo los miembros pueden leerla o reemplazarla; las reglas de Storage
  consultan el grupo y la baja en curso, sus dos documentos permitidos.
- Cualquier miembro puede cambiarla. El cliente publica la URL de descarga en
  `photoUrl` y las reglas de Firestore solo aceptan la ruta de ese mismo grupo.
- Storage exige que el grupo exista, así que al crearlo la foto se sube después
  de `createGroupChat`. Si la subida falla, el grupo queda creado sin foto y se
  avisa al usuario, que puede añadirla desde los datos del grupo.

## Añadir miembros

- Cualquier miembro puede añadir a sus propios amigos desde los datos del
  grupo. La pantalla solo ofrece amigos que aún no están en él.
- `addGroupChatMembers` exige autenticación y App Check. En una transacción
  comprueba que quien llama es miembro y está activo, que cada persona añadida
  está activa y es amiga mutua suya, y que el total no supera 20. No hace falta
  que sea amiga del resto.
- Un bloqueo, en cualquier sentido, entre la persona añadida y cualquier
  miembro activo impide añadirla: los bloqueos impiden enviar al grupo.
- Permite 30 llamadas por hora y usuario. Repetir la llamada o incluir a quien
  ya es miembro no cambia nada ni consume cuota.
- Quien entra ve todo el historial del grupo y empieza sin mensajes pendientes:
  el alta escribe `unreadCounts[uid] = 0` y `lastReadAt[uid]` con la hora de
  incorporación. `onNewMessage` respeta esa marca, así que un trigger que se
  ejecute tarde para un mensaje anterior ni lo cuenta ni lo notifica.
  No recibe ninguna notificación por haber sido añadido.
- Volver a añadir a quien salió borra su registro en `departures`: al ser
  miembro de nuevo sus reacciones restantes vuelven a ser válidas, y la
  limpieza en curso se detiene porque lee ese registro en cada transacción.

## Salir del grupo

- `leaveGroupChat` exige autenticación y App Check. En una transacción retira
  al usuario de `participants`, elimina sus entradas de `unreadCounts`,
  `deletedAt` y `lastReadAt` y crea `chats/{chatId}/departures/{uid}`, el
  registro de la limpieza pendiente. Es idempotente ante reintentos.
- `onGroupMemberLeft` se dispara al crearse ese registro y limpia las
  reacciones de quien salió, porque las reglas validan las reacciones contra
  los participantes. Reescribe cada mensaje en su propia transacción, de modo
  que varias salidas simultáneas o una reacción concurrente no se pisan. Borra
  el registro al terminar; si falla, Firestore reintenta el trigger y el
  registro sigue indicando la limpieza pendiente.
- Los mensajes enviados se conservan. Quien sale deja de leer el grupo y de
  recibir sus notificaciones, y solo vuelve si un amigo del grupo lo añade.
- Al salir el último miembro la transacción elimina el grupo. `onGroupChatDeleted`
  borra después, también con reintentos, sus mensajes, los registros de salida
  y su foto.

## IDs de grupos eliminados

`createGroupChat` acepta el ID que elige el cliente, así que un ID eliminado
no debe poder reutilizarse: el grupo nuevo heredaría los mensajes antiguos aún
sin limpiar y una ejecución tardía de `onGroupChatDeleted` lo borraría.

- Toda eliminación de un grupo desde el backend escribe, en la misma
  transacción, `deleted_group_chats/{chatId}`. El registro es permanente y solo
  contiene la fecha.
- `createGroupChat` lee ese registro en su transacción y rechaza el ID con
  `already-exists`.
- `onGroupChatDeleted` comprueba antes de limpiar que no exista un grupo con
  ese ID; si existe, no borra nada. Si falta el registro (grupo borrado desde
  la consola), lo crea en ese momento. Hasta entonces ese ID sí podría
  recrearse, por lo que conviene no borrar grupos a mano.

## Grupos sin cuentas activas

Las cuentas eliminadas siguen en `participants`. Un grupo en el que todas lo
están ya no puede abrirlo nadie, así que se elimina junto con sus mensajes y
su foto:

- Una cuenta cuenta como eliminada cuando su perfil público es la lápida
  `deleted_user`. Un perfil ausente no basta y conserva el grupo.
- Al salir, `leaveGroupChat` lee en su misma transacción los perfiles de quienes
  quedan y elimina el grupo si todos están eliminados.
- Al eliminar una cuenta, la fase `chats` del job comprueba cada grupo con
  `deleteGroupIfAbandoned`. Se ejecuta después de anonimizar el perfil, por lo
  que la última de varias salidas o eliminaciones simultáneas ve que no queda
  nadie. Si la fase falla, el job la reintenta y la comprobación es repetible.
- El contenido lo borra `onGroupChatDeleted`, igual que al salir el último
  miembro.
- Los grupos que ya estaban huérfanos antes de este cambio no se limpian: no
  hay una ejecución puntual para ellos.
- El cliente vuelve a la lista de chats al confirmar, sin esperar al backend;
  si la llamada falla, lo indica y el grupo sigue en la lista.

## Activación y alcance pendiente

Requiere desplegar las funciones modificadas, incluidas `createGroupChat`,
`addGroupChatMembers`, `leaveGroupChat`, `onGroupMemberLeft`,
`onGroupChatDeleted` y `processAccountDeletion`, y las reglas de
Firestore y de Storage antes de publicar el cliente. No requiere migrar chats existentes ni nuevos índices. El procedimiento
general está en [firebase_hosting.md](firebase_hosting.md).

Quedan para siguientes iteraciones: expulsar miembros, roles de
administrador, editar el nombre, quitar la foto y recibos de lectura por miembro.
Ocultar una conversación no equivale a abandonar el grupo.

Queda pendiente verificar el flujo grupal completo con varias cuentas y las
notificaciones en dispositivos reales tras desplegar el backend.

## Creación del grupo

La creación usa el SDK de Firebase Functions en todas las plataformas, con un
límite de espera de 30 segundos.
La lectura posterior del grupo tiene un límite de 10 segundos. Si se agota la
espera, se muestra un error de conexión y se permite reintentar con el mismo ID;
el backend mantiene la creación idempotente.

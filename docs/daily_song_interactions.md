# Likes y respuestas a la canción del día

Los amigos pueden dar o quitar un like y responder desde Descubrir. En el perfil
solo se muestra la tarjeta de la canción, sin controles de interacción. Los amigos
ven un corazón de 32 px sin contador ni texto visible. Solo el titular ve el
contador en su canción de Descubrir y puede pulsarlo para consultar los nombres
y avatares de quienes dieron like, con actualizaciones en tiempo real.

Las respuestas se envían en privado al chat con el titular. Sobre la burbuja
aparece «Has respondido a su canción del día» para el remitente y «Ha respondido
a tu canción del día» para el receptor; la burbuja contiene solo la respuesta.
La notificación muestra «{usuario} ha respondido a tu canción» y el mensaje.
Se mantienen las notificaciones, los contadores y el límite de envíos del chat.

Cada publicación se identifica por `users/{uid}.dailySongUpdatedAt`, incluso
cuando se vuelve a elegir el mismo tema. Los perfiles antiguos sin esta fecha
siguen mostrando su canción, pero deben volver a publicarla para habilitar las
interacciones.

Los likes se guardan en `users/{ownerId}/daily_song_likes/{senderId}` con
`senderId`, `publishedAt` y `createdAt`. Hay un documento por amigo; dar like a
una nueva publicación sustituye el anterior. El cliente consulta únicamente los
likes cuya fecha corresponde a la publicación actual. Las reglas exigen amistad
mutua, cuentas activas, ausencia de bloqueos y una publicación vigente. El titular
puede leer el contador y la lista completa, pero no darse like. Los demás solo
pueden leer el documento de su propio like; no pueden consultar likes ajenos.

`onDailySongLiked` envía «A {usuario} le ha gustado tu canción del día» en el idioma
del destinatario y abre la pestaña de canción del día al pulsarla. Antes de enviar,
comprueba que el like, la publicación, la amistad y las cuentas siguen vigentes.
La marca `notificationSentFor` la escribe solo el backend tras enviar; el cliente
la conserva con escrituras merge. Los reintentos confirmados no vuelven a enviar
y las notificaciones usan una etiqueta por remitente para agruparse. Quitar un
like no notifica; dar like a una nueva publicación sí.

`sendChatMessage` acepta `type: daily_song_reply`, `text` (máximo 2000 bytes UTF-8)
y `dailySongReply: { ownerId, publishedAtMicros }`, además de los identificadores
habituales de chat y mensaje. El backend verifica la publicación dentro de la
transacción. Se almacena el texto sin prefijos y la referencia con
`formatVersion: 2`; el modelo, la caché y el mensaje pendiente conservan esa
referencia. El cliente sigue reconociendo las respuestas anteriores con su
prefijo musical. Las
respuestas permanecen en el historial cuando la canción caduca; los likes no se
transfieren a otra publicación.

La eliminación de cuentas limpia los likes enviados mediante un índice de grupo
sobre `daily_song_likes.senderId`; la limpieza recursiva del perfil público elimina
los recibidos.

Para activar la función, desplegar las reglas y el índice de Firestore, y las
funciones `sendChatMessage`, `onNewMessage`, `onDailySongLiked` y
`processAccountDeletion` antes de publicar el cliente
Flutter actualizado. El despliegue web sigue `docs/firebase_hosting.md`.

Validación: `flutter analyze --no-fatal-infos`, `flutter test`,
`npm run test:rules`, `npm --prefix functions run test:unit` y
`npm run test:functions:social`.

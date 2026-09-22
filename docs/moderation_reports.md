# Denuncias y moderación

MusiLink permite denunciar perfiles desde su menú y mensajes ajenos mediante
una pulsación larga. La callable `submitModerationReport` valida el contexto,
evita duplicados, limita cada cuenta a 10 denuncias nuevas por hora y guarda
una instantánea en la colección privada `moderation_reports`.

Cada denuncia nueva generará un correo de texto con el tipo, motivo, usuarios,
IDs y, en denuncias de mensaje, el contenido copiado. El envío usa una clave de
idempotencia para no duplicar correos durante reintentos. Si Resend falla, la
denuncia se conserva y `emailDelivery.status` queda en `failed`; si se entrega
correctamente queda en `sent` junto al ID devuelto por Resend.

## Revisión

Las denuncias no son legibles ni modificables por clientes. Revísalas desde
Firebase Console → Firestore Database → `moderation_reports`. Cada documento
incluye `status: open`, el motivo, las identidades implicadas y, para mensajes,
una instantánea del texto o canción. La moderación inicial puede gestionarse
editando `status` manualmente en la consola, por ejemplo a `resolved`.

No confundas `status`, que representa la revisión humana de la denuncia, con
`emailDelivery.status`, que solo describe el aviso por correo.

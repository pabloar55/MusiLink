# Resumen diario de amigos

`sendDailyFriendDigests` recuerda a las 21:00 hora local que los amigos ya han
publicado su canción del día: «Ana, Luis y 3 más han publicado su canción del
día. ¡Publica la tuya!». Con un solo amigo el texto va en singular: «Ana ha
publicado su canción del día. ¡Publica la tuya!». Al pulsarla se abre la pestaña de canción del día.

## Cuándo se envía

La función se ejecuta cada 15 minutos (`europe-west1`, UTC) y selecciona los
perfiles privados cuyo `utcOffsetMinutes` corresponde a las 21:00 en ese tramo.
Un usuario recibe el resumen solo si se cumplen todas las condiciones:

- No ha desactivado «Resumen diario de amigos» en ajustes
  (`user_private/{uid}.notifFriendDigest`).
- No tiene una canción del día vigente.
- Al menos un amigo no bloqueado tiene una canción publicada en las últimas
  24 horas (`friendDigestMinFriends`). Se nombran hasta tres, empezando por la publicación más reciente.
- No ha recibido hoy otro recordatorio para publicar. `expireDailySongs` y el
  resumen comparten `user_private/{uid}.engagementPushAt`, de modo que el aviso
  de canción caducada y el resumen nunca coinciden en el mismo día local.
- La cuenta está activa y no tiene una baja pendiente.

La marca `engagementPushAt` se escribe en una transacción antes de enviar. Un
reintento del tramo no repite el aviso; si el envío falla, ese día se pierde.

## Entrega

El resumen se envía sin sonido ni vibración, con prioridad normal y por el canal
de Android `musilink_digest` (importancia baja). Usa la etiqueta `friend_digest`,
así que un aviso nuevo sustituye al anterior. Con la app en primer plano no se
muestra en Android ni en web.

## Datos del cliente

`NotificationService` guarda `utcOffsetMinutes` junto a `preferredLocale` cada
vez que registra el token push. El desfase se actualiza al abrir la app; tras un
cambio de hora, quien no la abra recibe el resumen con una hora de diferencia.
Las versiones anteriores de la app no guardan el desfase y no reciben el resumen.

## Despliegue

Publica `firestore.rules` antes de distribuir el cliente. El desfase se escribe
en el mismo batch que el token push, por lo que con las reglas antiguas fallaría
también el registro del token.

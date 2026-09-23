# Cuotas del catálogo musical

Las funciones requieren autenticación y App Check. Cada usuario dispone de dos
cuotas independientes de 60 solicitudes por ventana de un minuto:

- `searchSpotifyArtists` y `searchSpotifyTracks` comparten `spotifySearch`.
- `getSimilarArtists` utiliza `lastFmSimilar`.

Los contadores y el inicio de cada ventana se guardan en `rate_limits/{uid}`.
La reserva es transaccional, posterior a la validación y anterior a consultar
los proveedores. Los errores externos también consumen cuota. El cliente
no puede elegir la cuota ni modificar estos documentos. Una búsqueda de artistas
puede completar los géneros de hasta diez resultados con Last.fm; esas consultas
pertenecen a la búsqueda de Spotify y no consumen la cuota de artistas similares.

Así, completar 30 artistas con 60 búsquedas de Spotify y 30 consultas de similares
dentro de un minuto ya no enfrenta las dos operaciones al mismo límite. Los
valores iniciales se definen en `functions/src/rate_limits.ts`; deben ajustarse
con mediciones de uso y errores `resource-exhausted`, no interpretarse como la
cuota garantizada del proveedor ni como un límite global entre todos los usuarios.

## Peticiones y errores

Las consultas de artistas similares y géneros llaman directamente a Last.fm,
sin guardar resultados en Firestore. Se mantienen el timeout, la validación de
respuestas y la conversión del error 29 de Last.fm a `resource-exhausted`.
El cliente propaga los fallos de similares para que su caché local y la pantalla
no los guarden como listas vacías; una nueva petición puede reintentarlos.

Firestore solo se utiliza para el control de cuota en estas consultas: normalmente
una lectura y una escritura por solicitud admitida, con posibles lecturas adicionales
si la transacción se reintenta. Eliminar la caché no elimina este coste del limitador.

## Despliegue y validación

Desplegar las funciones `searchSpotifyArtists`, `searchSpotifyTracks` y
`getSimilarArtists`. Si la caché anterior llegó a desplegarse, sus documentos y
la política TTL remota no se eliminan por retirar el código: comprobar ese estado
antes de retirar la política y limpiar los documentos restantes.

Validación: pruebas unitarias del backend y `test:social` para reservas concurrentes.
Las pruebas del catálogo verifican que solo se accede a `rate_limits/{uid}` y que
las llamadas a Last.fm respetan los límites solicitados.

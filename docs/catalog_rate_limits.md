# Cuotas y caché del catálogo musical

Las funciones requieren autenticación y App Check. Cada usuario dispone de dos
cuotas independientes de 60 solicitudes por ventana de un minuto:

- `searchSpotifyArtists` y `searchSpotifyTracks` comparten `spotifySearch`.
- `getSimilarArtists` utiliza `lastFmSimilar`.

Los contadores y el inicio de cada ventana se guardan en `rate_limits/{uid}`.
La reserva es transaccional, posterior a la validación y anterior a consultar
cachés o proveedores. Los errores externos también consumen cuota. El cliente
no puede elegir la cuota ni modificar estos documentos. Una búsqueda de artistas
puede completar los géneros de hasta diez resultados con Last.fm; esas consultas
pertenecen a la búsqueda de Spotify y no consumen la cuota de artistas similares.

Así, completar 30 artistas con 60 búsquedas de Spotify y 30 consultas de similares
dentro de un minuto ya no enfrenta las dos operaciones al mismo límite. Los
valores iniciales se definen en `functions/src/rate_limits.ts`; deben ajustarse
con mediciones de uso y errores `resource-exhausted`, no interpretarse como la
cuota garantizada del proveedor ni como un límite global entre todos los usuarios.

## Caché de Last.fm

`lastfm_cache/{sha256}` guarda listas de nombres similares o géneros normalizados,
con una clave por versión, método y nombre de artista normalizado. No guarda
usuarios ni credenciales. Se comparte entre usuarios e instancias; las solicitudes
idénticas en curso también se agrupan dentro de cada instancia. Dos instancias
pueden consultar simultáneamente una clave aún no almacenada.

La vigencia máxima es de 24 horas para listas con resultados y cinco minutos
para listas realmente vacías. Se respetan las restricciones de caché indicadas
por Last.fm (`Cache-Control`, `Age`, `Expires`). Las consultas de similares piden
los diez resultados admitidos y cada respuesta al cliente se recorta a su `limit`.
Los errores HTTP, errores de la API dentro del JSON y respuestas malformadas no
se almacenan. El cliente propaga los fallos de similares para que ni su caché ni
la pantalla los guarden como listas vacías; una nueva petición puede reintentarlos.

La caducidad se comprueba al leer, independientemente de cuándo Firestore elimine
el documento. La política TTL de `expiresAt` y las exclusiones de índices están
en `firestore.indexes.json`; las reglas prohíben cualquier acceso desde clientes.

## Despliegue y validación

No se requiere migrar perfiles ni contadores existentes. Desplegar las reglas,
los índices/TTL y las funciones `searchSpotifyArtists`, `searchSpotifyTracks` y
`getSimilarArtists`; publicar también el cliente actualizado. La política TTL
debe quedar activa para que se eliminen físicamente los documentos caducados.

Validación: pruebas unitarias del backend, `test:social` para reservas concurrentes
y caché compartida en el emulador, pruebas de reglas y pruebas Flutter de Last.fm,
catálogo y selector de artistas.

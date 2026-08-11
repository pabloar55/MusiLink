# Migración de reservas de username

Los perfiles activos deben tener una reserva `usernames/{username}` antes de
desplegar las nuevas reglas. De lo contrario, sus actualizaciones normales de
perfil serán rechazadas.

## Orden de despliegue

1. Desplegar la función `createUserProfile` sin desplegar todavía las reglas.
2. Auditar producción sin escrituras:

   ```sh
   cd functions
   npm run migrate:usernames -- --project musi-link-e7759
   ```

3. Resolver manualmente cualquier username duplicado, no normalizado, reserva
   huérfana o reserva asignada a otro UID. El script nunca decide un ganador ni
   elimina datos automáticamente.
4. Crear y verificar las reservas:

   ```sh
   npm run migrate:usernames -- --project musi-link-e7759 --apply
   npm run migrate:usernames -- --project musi-link-e7759 --verify-only
   ```

5. Publicar la app que usa la callable y la consulta por documento.
6. Forzar la actualización de clientes antiguos y desplegar las reglas. Desde
   ese momento el cliente ya no puede crear perfiles ni modificar usernames
   directamente.

La migración requiere credenciales de aplicación con acceso al proyecto. Los
perfiles anonimizados con `username == deleted_user` no reciben reserva.

# Migración de Flutter Web a Cloudflare

La web se desplegará como una SPA estática mediante **Cloudflare Workers
Static Assets**. Firestore, Authentication, Cloud Functions, Storage, FCM,
Remote Config, Analytics y App Check continúan en el proyecto de Firebase
`musi-link-e7759`.

GitHub Pages debe permanecer activo hasta completar las pruebas y el cambio de
dominio. El workflow de Cloudflare está desactivado por defecto para evitar
despliegues fallidos mientras se prepara la cuenta.

## 1. Preparar Cloudflare y GitHub

1. Crear la cuenta de Cloudflare y anotar el **Account ID**.
2. En **Workers & Pages**, localizar **Your subdomain**. Si todavía no está
   configurado, pulsar **Change** y elegir el subdominio de la cuenta.
   Como el Worker se llama `musilink-web`, su hostname provisional será:

   ```text
   musilink-web.SUBDOMINIO-DE-LA-CUENTA.workers.dev
   ```

3. Crear un API token desde **My Profile > API Tokens > Create Token** usando
   la plantilla **Edit Cloudflare Workers**. Limitar el token a la cuenta de
   MusiLink y, cuando sea posible, a los recursos necesarios.
4. En GitHub, abrir **Settings > Secrets and variables > Actions** y crear estos
   secretos del repositorio:

   - `CLOUDFLARE_ACCOUNT_ID`
   - `CLOUDFLARE_API_TOKEN`

5. No crear todavía `CLOUDFLARE_DEPLOY_ENABLED`. La ausencia de esta variable
   mantiene el workflow inactivo.

Las credenciales no deben añadirse a `.env`, `wrangler.jsonc` ni a ningún otro
archivo versionado.

## 2. Primer despliegue controlado

Antes de activar el workflow, registrar el dominio provisional o definitivo en
los servicios que validan el origen del navegador. Si el primer despliegue usa
el subdominio de Workers, registrar también el hostname derivado en el apartado
anterior. Firebase solicita únicamente el hostname, sin `https://` ni `/`.

1. En **Firebase Console > Authentication > Settings > Authorized domains**,
   añadir el hostname de Cloudflare.
2. En **Google Cloud Console > APIs & Services > Credentials**, abrir el cliente
   OAuth web usado por MusiLink y añadir `https://HOSTNAME` a **Authorized
   JavaScript origins**.
3. En **Google Cloud Console > reCAPTCHA Enterprise**, abrir la clave web usada
   por Firebase App Check y añadir el dominio a la lista permitida.
4. En GitHub, crear la variable de repositorio
   `CLOUDFLARE_DEPLOY_ENABLED` con el valor `true`.
5. Ejecutar manualmente **Deploy web to Cloudflare** desde la pestaña Actions.

El workflow también desplegará automáticamente después de cada ejecución
correcta de CI sobre `main` mientras la variable conserve el valor `true`.

## 3. Validación antes del cambio de DNS

Probar en la URL devuelta por Cloudflare:

- carga directa y recarga de `/auth`, `/profile/UID` y `/settings`;
- registro e inicio de sesión con email;
- inicio y cierre de sesión con Google;
- lecturas y escrituras de Firestore;
- llamadas a Cloud Functions;
- carga y visualización de fotos desde Firebase Storage;
- App Check sin errores `403` ni `app-check-token-is-invalid`;
- permisos y recepción de notificaciones FCM en segundo plano;
- instalación y actualización de la PWA;
- navegación desde una notificación a una ruta interna.

Cloudflare sirve `index.html` con estado `200` para rutas que no correspondan a
un fichero gracias a `not_found_handling: "single-page-application"`. No hay que
copiar `index.html` a `404.html`, como se hace para GitHub Pages.

## 4. Dominio y retirada de GitHub Pages

1. Añadir el dominio definitivo al Worker desde **Workers & Pages > musilink-web
   > Settings > Domains & Routes**.
2. Repetir las tres autorizaciones de dominio de Firebase Auth, Google OAuth y
   reCAPTCHA Enterprise para el dominio definitivo.
3. Validar de nuevo los flujos críticos en el dominio definitivo.
4. Cambiar o confirmar el DNS cuando la URL de Cloudflare esté verificada.
5. Mantener GitHub Pages disponible durante un periodo corto de observación.
6. Cuando no sea necesario el rollback, desactivar Pages y eliminar
   `.github/workflows/deploy-pages.yml` en un cambio independiente.

Para pausar inmediatamente los despliegues a Cloudflare sin tocar credenciales,
cambiar `CLOUDFLARE_DEPLOY_ENABLED` a `false`.

## Validación local de la configuración

Con un build existente en `build/web`, Wrangler puede validar el paquete sin
autenticarse ni desplegarlo:

```bash
npx --yes wrangler@4.127.1 deploy --dry-run
```

Para probar el enrutado localmente:

```bash
flutter build web --release --base-href /
npx --yes wrangler@4.127.1 dev
```

# Despliegue de Flutter Web en Firebase Hosting

La SPA web y los servicios backend usan el proyecto de Firebase
`musi-link-e7759`. El dominio canónico es `https://musilink.app` y
`https://www.musilink.app` redirige al dominio canónico desde Firebase Hosting.

## Despliegue manual

Desde la raíz del repositorio:

```bash
flutter pub get
flutter build web --release --base-href /
firebase deploy --only hosting --project musi-link-e7759
```

La configuración `hosting` de `firebase.json` publica `build/web` y reescribe
las rutas sin fichero a `index.html` para que la navegación directa de la SPA
funcione.

## Despliegue desde GitHub

El workflow `.github/workflows/deploy-firebase-hosting.yml` se ejecuta cuando
CI termina correctamente en `main` y también permite ejecución manual. GitHub
debe contener este secreto de Actions:

- `FIREBASE_SERVICE_ACCOUNT_MUSI_LINK_E7759`: JSON de una cuenta de servicio
  con permisos para desplegar Firebase Hosting en `musi-link-e7759`.

El secreto puede configurarse con la integración oficial:

```bash
firebase init hosting:github
```

No se debe guardar el JSON de la cuenta de servicio en el repositorio.

## Dominios

En Firebase Console > Hosting, la configuración esperada es:

- `musilink.app`: dominio personalizado conectado al sitio.
- `www.musilink.app`: dominio personalizado que redirige a `musilink.app`.

Los registros A, AAAA y TXT mostrados por Firebase deben existir en el
proveedor DNS autoritativo. Firebase administra el certificado TLS de ambos
hostnames.

## Comprobaciones

```bash
dig +short A musilink.app
dig +short A www.musilink.app
curl -I https://musilink.app
curl -I https://www.musilink.app
```

La segunda URL debe responder con una redirección a `https://musilink.app`.
Antes de dar por terminado un despliegue se deben comprobar el inicio de sesión,
Firestore, Functions, Storage, App Check, FCM y la navegación directa a rutas
internas.

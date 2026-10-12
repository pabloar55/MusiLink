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

Para desplegar también Cloud Functions, las reglas e índices de Firestore y las
reglas de Storage, una vez compilada la web:

```bash
firebase deploy --project musi-link-e7759
```

El hook `predeploy` compila las funciones automáticamente. Remote Config se
gestiona desde Firebase Console y está excluido de `firebase.json`; este comando
no necesita una plantilla local ni modifica sus parámetros.

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

## Enlaces compartidos

La card de invitación comparte dos enlaces (`AppInviteService`):

- `https://musilink.app/invite` (`inviteUrl`): solo la app.
- `https://musilink.app/u/<username>` (`profileUrl`): el perfil de quien invita.
  La app lo abre en la ruta `/u/:username`, que resuelve el uid en
  `usernames/{username}` y muestra el perfil sobre la pantalla principal.

Un script en línea de `web/index.html` resuelve ambos antes de cargar Flutter:
en el navegador de Android redirige a Google Play y en el resto de plataformas
continúa en la web: `/invite` en `/`, donde iOS muestra la instalación de la
PWA, y `/u/<username>` en `/#/u/<username>`. Una PWA instalada nunca se
redirige a Google Play.

En Android, la app instalada abre `/u/` directamente mediante App Links
(`intent-filter` con `autoVerify` en `AndroidManifest.xml`). La verificación usa
`https://musilink.app/.well-known/assetlinks.json`, que Hosting sirve desde
`web/well-known/assetlinks.json` mediante un rewrite porque `firebase.json`
ignora las rutas que empiezan por punto. El archivo debe contener la huella
SHA-256 de la clave de firma de Google Play (Play Console → Integridad de la
app → Firma de apps); mientras no coincida, Android abre el enlace en el
navegador. Comprobaciones:

```bash
curl -s https://musilink.app/.well-known/assetlinks.json
adb shell pm get-app-links app.musilink
adb shell am start -a android.intent.action.VIEW -d https://musilink.app/u/<username>
```

iOS abre los enlaces en Safari y no en la PWA instalada, por lo que allí el
mensaje compartido conserva el `@username` para buscarlo a mano.

La vista previa del enlace (título, descripción e imagen) sale de las etiquetas
Open Graph de `web/index.html` y de `web/og-image.jpg` (1200×630). Las apps de
mensajería guardan la vista previa en caché: al cambiar la imagen conviene
cambiar también su nombre de archivo.

## Confirmaciones de entrega del chat

Los mensajes aparecen localmente al enviar y se reconcilian por ID con
Firestore. `delivered: true` indica recepción; `read: true` indica apertura
visible del chat. La sincronización autenticada confirma mensajes pendientes
sin modificar el contador de no leídos. Los mensajes antiguos sin `delivered`
se interpretan como pendientes de entrega, salvo que ya estén leídos.

En la PWA cerrada, `firebase-messaging-sw.js` confirma la recepción de cada push
mediante `POST /api/chat-delivery`. Hosting dirige esta ruta a
`acknowledgeChatDelivery` en `europe-southwest1`. El push incluye un token
aleatorio de 256 bits limitado al mensaje; Firestore solo guarda su hash.
El endpoint únicamente permite poner `delivered: true`, de forma idempotente,
y no necesita reCAPTCHA ni una ventana abierta. Los tokens nunca se registran
en logs. No se interpreta la aceptación del envío por FCM como recepción.

Para activar esta funcionalidad hay que desplegar las reglas de Firestore,
las Functions (`onNewMessage`, `sendChatMessage`, `acknowledgeChatDelivery`) y
la nueva compilación web con su configuración de Hosting. Verificar con dos
cuentas: envío inmediato, receptor desconectado (un check), recepción en la
app o por push (dos checks sin azul), apertura del chat (dos azules). Si el
sistema no ejecuta el worker o interrumpe su red, la entrega se confirma en la
siguiente sincronización de la app.

# Actualizaciones obligatorias

MusiLink compara el número de build instalado con una política de Firebase Remote Config antes de cargar la aplicación. Si la versión está bloqueada:

- Android intenta primero Google Play In-App Updates con el flujo nativo `IMMEDIATE`.
- iOS abre la ficha configurada de App Store.
- La pantalla Flutter bloqueante queda como respaldo cuando Google Play no puede iniciar el flujo, por ejemplo en una APK instalada manualmente.

## Parámetros de Remote Config

| Parámetro | Tipo | Valor seguro inicial | Uso |
|---|---:|---:|---|
| `force_update_enabled` | Boolean | `false` | Interruptor global del bloqueo |
| `minimum_android_build` | Number | `0` | `versionCode` mínimo de Android |
| `minimum_ios_build` | Number | `0` | `CFBundleVersion` mínimo de iOS |
| `android_store_url` | String | URL de Google Play | Respaldo si Play Core no está disponible |
| `ios_store_url` | String | URL de App Store | Destino de actualización en iOS |

La plantilla versionada está en `remoteconfig.template.json` y se puede publicar con:

```bash
firebase deploy --only remoteconfig
```

Para bloquear builds inferiores a `11`, publica primero la build `11`, confirma que está disponible en las tiendas y después activa:

```text
force_update_enabled = true
minimum_android_build = 11
minimum_ios_build = 11
```

Un mínimo es inclusivo: `11` admite las builds `11` y superiores y bloquea `10` e inferiores.

Antes de bloquear iOS hay que reemplazar la URL de búsqueda incluida como valor inicial por la URL exacta de App Store Connect.

## Publicación inicial segura

La versión `1.0.6+10` es la primera que contiene el comprobador. Debe publicarse con el interruptor desactivado y mínimos a `0`.

Orden recomendado:

1. Publicar Cloud Functions nuevas y la plantilla segura de Remote Config.
2. Publicar `1.0.6+10` en Google Play y App Store.
3. Confirmar que ambas tiendas sirven realmente esa build.
4. Desplegar las reglas estrictas de Firestore.
5. En una actualización posterior, publicar la build siguiente y subir los mínimos solo cuando esté disponible.

### Limitación de las builds anteriores

Una build que no contiene este comprobador no puede recibir retroactivamente una pantalla de actualización. Por tanto, la build `9` no reaccionará a estos parámetros. Las reglas estrictas sí impedirán sus operaciones ya no permitidas, pero el cliente antiguo verá errores de permisos.

La build `10` actúa como versión puente: una vez instalada, sí podrá ser bloqueada remotamente cuando se publique la `11`. Si fuera imprescindible denegar todo acceso de la build `9`, haría falta además una barrera de autorización en el backend; eso no puede producir una interfaz nativa de Play dentro del binario antiguo.

## Prueba del flujo Android

Google Play solo ofrece In-App Updates cuando la app fue instalada desde Play y existe para esa cuenta una versión con `versionCode` superior. Para probarlo:

1. Subir dos builds a Internal App Sharing o a una pista interna.
2. Instalar la build inferior desde el enlace de Play.
3. Hacer disponible la build superior para la misma cuenta.
4. Configurar Remote Config para que el mínimo sea la build superior.
5. Abrir la build inferior y verificar el flujo nativo inmediato.

Una compilación debug instalada con ADB no cumple estas condiciones y utilizará el respaldo que abre la tienda.

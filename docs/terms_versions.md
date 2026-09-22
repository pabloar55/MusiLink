# Comprobación de versiones de términos

Ejecuta desde la raíz de MusiLink:

```sh
npm run test:terms-versions
```

El test compara los valores reales de estas tres fuentes, sin fijar una fecha
en el propio test:

- `lib/utils/terms_and_conditions.dart`: `TermsAndConditions.version`.
- `functions/src/terms_acceptance.ts`: `currentTermsVersion`.
- `musilink-site/terms-and-conditions/index.html`: la etiqueta
  `<meta name="terms-version" content="…">`.

Por defecto busca `musilink-site` junto al repositorio de MusiLink. Para usar
otra ubicación o una copia de trabajo con cambios de términos pendientes:

```sh
MUSILINK_SITE_DIR=/ruta/a/musilink-site npm run test:terms-versions
```

Solo necesita Node.js; no requiere Flutter, Firebase, emuladores ni instalar
dependencias npm. Falla si hay versiones diferentes, si falta alguna declaración
o si no está disponible el archivo del sitio. Nunca omite la comprobación por
no encontrar el repositorio.

El job `terms-versions` de CI descarga `pabloar55/musilink-site` en su rama
`main` y ejecuta el mismo test en cada push o pull request de MusiLink cubierto
por el workflow. Compara con el código de ese repositorio, no con el despliegue
de GitHub Pages. Un cambio solo en `musilink-site` no dispara el CI de MusiLink.

Cuando cambien los términos, actualiza las tres versiones y los textos visibles
del sitio. Para que el CI de MusiLink pase, la versión correspondiente del sitio
debe estar disponible en `main`. El test detecta diferencias; no publica la web,
la app ni la callable.

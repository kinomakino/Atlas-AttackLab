# Web pública: despliegue

Web pública del proyecto y catálogo de retos, en Azure Static Web Apps.

- **URL:** https://witty-rock-0c004b703.6.azurestaticapps.net (dominio propio, pendiente)
- **Suscripción:** LA BUENA 2025 (`184da419-5261-4409-9f88-808288fc1400`). Comprobar con `az account show` antes de desplegar.
- **Grupo de recursos:** `rg-atlas-attacklab` (West Europe)
  - `swa-atlas-attacklab`: Static Web App, plan Free. Web en `site/`, API en `api/` (Azure Functions, Node 20).
  - `statlasattacklab603`: Storage Account con la tabla `retos` (el catálogo). La API la lee con el ajuste `CATALOG_CONNECTION`.

## Qué hay

| Ruta | Acceso | Qué es |
|---|---|---|
| `/`, `/guia.html`, `/matriz.html`, `/descargar.html` | Público | Portada, guía del alumno, matriz ATLAS con los retos y descarga |
| `/api/catalog` | Público | Retos publicados. Lo lee la matriz y lo leerá la herramienta local |
| `/admin/` | Rol `admin` | Gestión del catálogo |
| `/api/admin/retos` | Rol `admin` | API de gestión (la función vuelve a comprobar el rol) |

El login es el de Microsoft (Entra ID) que trae Static Web Apps. Solo quien tenga el rol `admin` entra en `/admin`.

## Desplegar

```bash
cd api && npm ci && cd ..
TOKEN=$(az staticwebapp secrets list -n swa-atlas-attacklab -g rg-atlas-attacklab --query properties.apiKey -o tsv)
npx -y @azure/static-web-apps-cli@2.0.2 deploy ./site --api-location ./api --api-language node --api-version 20 --env production --deployment-token "$TOKEN"
```

## Dar acceso de administrador

```bash
az staticwebapp users invite -n swa-atlas-attacklab -g rg-atlas-attacklab \
  --authentication-provider AAD --user-details <correo> --roles admin \
  --domain witty-rock-0c004b703.6.azurestaticapps.net --invitation-expiration-in-hours 168
```

La persona abre el enlace que devuelve, inicia sesión con ese correo y queda con el rol.

## Regenerar la matriz

`site/data/atlas-matrix.json` sale de `data/atlas.json` (catálogo oficial de ATLAS). Al cambiar de versión de ATLAS: `uv run attacklab import-atlas --version <v>` y volver a generar el JSON de la web.

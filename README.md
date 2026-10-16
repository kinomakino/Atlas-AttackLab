# Atlas-AttackLab

Lab local para aprender y practicar las técnicas de [MITRE ATLAS](https://atlas.mitre.org) atacando sistemas de IA vulnerables. Todo corre en tu equipo con Docker, con el modelo incluido.

Estado: en construcción. Decisiones en [docs/decisiones.md](docs/decisiones.md) y arquitectura en [docs/arquitectura.md](docs/arquitectura.md).

## Instalar el lab

Para alumnos. Necesitas Docker (Docker Desktop en macOS y Windows) arrancado.

1. **Mientras la versión sea privada**, crea un token de GitHub (classic) con permiso `read:packages` desde la cuenta a la que te hemos dado acceso e inicia sesión en el registro. Cuando pida la contraseña, pega el token:

   ```bash
   docker login ghcr.io -u tu-usuario-de-github
   ```

2. Descarga el instalador de la [página de descarga](https://witty-rock-0c004b703.6.azurestaticapps.net/descargar.html), léelo y ejecútalo. En macOS y Linux:

   ```bash
   curl -fsSLO https://witty-rock-0c004b703.6.azurestaticapps.net/install.sh
   bash install.sh
   ```

   En Windows, desde PowerShell:

   ```powershell
   Invoke-WebRequest https://witty-rock-0c004b703.6.azurestaticapps.net/install.ps1 -OutFile install.ps1
   powershell -ExecutionPolicy Bypass -File install.ps1
   ```

3. El instalador abre http://127.0.0.1:8080. La primera vez, pulsa el botón para descargar el modelo (unos 2 GB).

Después tienes el comando `atlas-lab` (`start`, `stop`, `status`, `open`, `update`, `logs`, `doctor`, `uninstall`). `atlas-lab uninstall` lo borra todo: contenedores, imágenes, progreso, modelos, carpeta y comando. Cómo se juega, paso a paso, en la [guía](https://witty-rock-0c004b703.6.azurestaticapps.net/guia.html). Detalles del instalador en [docs/instalacion.md](docs/instalacion.md).

## Arrancar el lab desde el código

Solo necesitas Docker.

```bash
docker compose up -d --build
```

Abre http://127.0.0.1:8080. La primera vez la web te ofrece descargar el modelo (unos 2 GB).

- Todo escucha solo en `127.0.0.1`. Ollama no publica ningún puerto.
- Tu progreso se guarda en el volumen `progreso`; los modelos, en `modelos`.
- `ATTACKLAB_THREADS` fija los hilos de inferencia si quieres ajustarlos.

## Panel de administración

La web pública tiene un panel para gestionar el catálogo de retos en https://witty-rock-0c004b703.6.azurestaticapps.net/admin/. Se entra con una cuenta de Microsoft (Entra ID) y solo pasa quien tiene el rol `admin`; al resto le pide iniciar sesión o le niega el acceso.

Para dar acceso a alguien, invítalo con el rol `admin`:

```bash
az staticwebapp users invite -n swa-atlas-attacklab -g rg-atlas-attacklab \
  --authentication-provider AAD --user-details <correo> --roles admin \
  --domain witty-rock-0c004b703.6.azurestaticapps.net --invitation-expiration-in-hours 168
```

La persona abre el enlace que devuelve e inicia sesión con ese correo. Despliegue, recursos de Azure y rutas protegidas en [docs/despliegue.md](docs/despliegue.md).

## Desarrollo

```bash
uv run pytest                   # tests del motor
uv run attacklab list           # retos instalados (carpeta retos/)
uv run attacklab import-atlas   # catálogo oficial de ATLAS en data/atlas.json
```

Cada reto es un módulo en `retos/<id>/`: `module.yaml` (manifiesto) y su contenido.

Catálogo de ATLAS © MITRE, licencia Apache 2.0.

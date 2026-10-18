# Instalación en equipos de cliente

El lab se instala en equipos de usuario muy distintos. El instalador tiene que **detectar, decidir y explicar**: nunca dejar una instalación a medias ni un error críptico.

Con terminal enseña un menú (instalar o actualizar, comprobar el equipo, desinstalar, salir) y **acompaña**: ante un problema que el alumno puede arreglar, explica, ofrece abrir el enlace o lo arregla él, y espera a que el alumno pulse Enter para volver a comprobar. Sin terminal, o con `--yes` / `-Yes` (CI, `atlas-lab update`), no pregunta nada y se para con el mensaje y un código de salida propio.

## Qué descarga el cliente

| Pieza | De dónde | Qué es |
|---|---|---|
| `install.sh` / `install.ps1` | Web pública, con su SHA-256 publicado | El instalador. Se puede leer antes de ejecutarlo |
| `compose.yaml` | Lo genera el instalador | Versión fija de cada imagen |
| Imágenes | GHCR (`ghcr.io/kinomakino/atlas-attacklab`, público), firmadas con cosign | `lab` (motor, web y retos), multiplataforma amd64/arm64 |
| `ollama/ollama` | Docker Hub, versión fija | El servidor del modelo |
| Modelo | Registro de Ollama | Lo baja la web del lab cuando un reto lo pide |

Todo se instala en una carpeta del usuario (`~/.atlas-lab`, o `%LOCALAPPDATA%\atlas-lab` en Windows) más volúmenes de Docker. Nada fuera de ahí, y sin permisos de administrador.

## Casos de cliente y qué hace el instalador

### Sistema y Docker

| Caso | Qué hace |
|---|---|
| macOS Apple Silicon o Intel | Requiere Docker Desktop (u OrbStack/Colima con `docker` en el PATH) |
| Windows 10/11 | Requiere Docker Desktop con WSL 2 y contenedores Linux |
| Linux | Docker Engine o Desktop con Compose v2 |
| Docker no instalado | Da el enlace de descarga directa de Docker Desktop para su sistema y chip (en Linux, la guía de Docker Engine), ofrece abrirlo y espera a que lo instale |
| Docker instalado pero parado | En macOS y Windows ofrece arrancar Docker Desktop y espera hasta 3 minutos a que responda. En Linux explica cómo arrancar el servicio |
| Docker Desktop recién instalado, sin `docker` en el PATH de esa terminal | Lo busca en las rutas de Docker Desktop y lo usa |
| El registro pide iniciar sesión | Abre GitHub para crear un token `read:packages`, pide usuario y token y hace el `docker login` (las imágenes son públicas: no debería pasar) |
| Sin permiso para usar Docker (Linux, usuario fuera del grupo `docker`) | Se para y explica cómo añadirse al grupo |
| Compose v1 (`docker-compose`) o sin Compose | Se para y explica cómo actualizar |
| Windows con contenedores Windows | Se para: hay que cambiar a contenedores Linux |
| Podman sin Docker | No soportado en v1. Lo dice claramente |

### Recursos (los que tiene **Docker**, no el equipo)

En macOS y Windows, Docker corre en una máquina virtual con su propio límite de núcleos y memoria. Lo que cuenta es lo que da `docker info`.

| Caso | Qué hace |
|---|---|
| Memoria de Docker < 4 GiB | Se para. El modelo ocupa unos 3 GiB cargado. Explica cómo subirla en Docker Desktop |
| 4–6 GiB | Avisa: funcionará justo, mejor cerrar otras apps |
| Núcleos | Hilos de inferencia = 2/3 de los núcleos de Docker (mínimo 1). Con todos, la inferencia se hunde |
| 1–2 núcleos | Avisa: las respuestas tardarán bastante |
| Disco libre < 6 GiB | Se para (imágenes + modelo ≈ 4 GiB) |
| Arquitectura | Imágenes multiplataforma: Docker elige amd64 o arm64 solo |

### Aceleración

| Caso | Qué hace |
|---|---|
| Linux/Windows con NVIDIA y runtime de Docker para NVIDIA | Activa la GPU en Ollama |
| GPU NVIDIA sin runtime | Funciona en CPU y explica cómo activar la GPU |
| Mac (Docker no puede usar la GPU de Apple) | Si hay un Ollama nativo respondiendo en el equipo, ofrece usarlo en lugar del contenedor |
| AMD / Intel GPU | CPU en v1 |

### Red y entorno

| Caso | Qué hace |
|---|---|
| Puerto 8080 ocupado | Busca el siguiente libre (8080–8099) y lo guarda |
| Sin internet o proxy corporativo | Falla la descarga con un mensaje que lo nombra. El proxy se configura en Docker |
| Reinstalar o actualizar | Idempotente: conserva el progreso y los modelos |
| Desinstalar | `atlas-lab uninstall`: contenedores, volúmenes, carpeta y comando. No queda nada |

## Comando `atlas-lab`

`start`, `stop`, `status`, `open`, `update`, `logs`, `doctor` (repite las comprobaciones) y `uninstall`.

## Pruebas

Nunca en el equipo del desarrollador. En CI, en cada cambio:

- **Lógica de decisión:** tests que simulan cada caso de la tabla con un `docker` falso (sin Docker, parado, poca memoria, 1 núcleo, puerto ocupado, NVIDIA…).
- **Instalación real en Linux:** GitHub Actions instala de cero, comprueba que la web responde, descarga el modelo, juega un turno y desinstala.
- **Windows real:** las máquinas Windows de GitHub no ejecutan contenedores Linux. Antes de cada versión, en una máquina virtual efímera de Azure con virtualización anidada y Docker Desktop (script en `deploy/pruebas/`).
- **macOS real:** las máquinas macOS de GitHub no pueden ejecutar Docker y Azure no tiene macOS. La lógica se cubre con los tests; la instalación real, en un Mac de pruebas (un Mac físico o uno alquilado por horas) antes de cada versión.

#!/usr/bin/env bash
# Instalador de Atlas-AttackLab para macOS y Linux.
#
#   curl -fsSLO https://<web>/install.sh && less install.sh && bash install.sh
#
# Comprueba Docker y los recursos que Docker tiene en este equipo, decide la
# configuración, descarga el compose verificado, arranca y deja el comando `atlas-lab`.
# Todo queda en ~/.atlas-lab y en volúmenes de Docker. No necesita sudo.
#
# Opciones: --yes (sin preguntas)  --check (solo diagnóstico)  --dir <carpeta>
#           --port <n>  --no-open  --native-ollama | --no-native-ollama
set -euo pipefail

VERSION="__VERSION__"
BASE_URL="__BASE_URL__"
COMPOSE_SHA256="__COMPOSE_SHA256__"
COMPOSE_GPU_SHA256="__COMPOSE_GPU_SHA256__"

MIN_MEM_GIB=4
WARN_MEM_GIB=6
MIN_DISK_GIB="${ATTACKLAB_MIN_DISK_GIB:-6}"     # variable solo para las pruebas
PORT_FIRST=8080
PORT_LAST=8099

DOCKER="${ATTACKLAB_DOCKER:-docker}"        # las pruebas inyectan un docker simulado
NATIVE_OLLAMA_URL="${ATTACKLAB_NATIVE_OLLAMA_URL:-http://127.0.0.1:11434}"
INSTALL_DIR="${ATTACKLAB_DIR:-$HOME/.atlas-lab}"
BIN_DIR="${ATTACKLAB_BIN_DIR:-$HOME/.local/bin}"
ASSUME_YES=0; CHECK_ONLY=0; OPEN_BROWSER=1; NATIVE_CHOICE=""; PORT=""

# ---------------------------------------------------------------- utilidades
if [ -t 1 ]; then B=$'\033[1m'; Y=$'\033[33m'; R=$'\033[31m'; G=$'\033[32m'; N=$'\033[0m'; else B=; Y=; R=; G=; N=; fi
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✔%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '\n%s✖ %s%s\n' "$R" "$1" "$N" >&2; [ -n "${2:-}" ] && printf '  %s\n' "$2" >&2; exit "${3:-1}"; }

ask_yes() {  # ask_yes "pregunta" -> 0 si sí
  [ "$ASSUME_YES" = 1 ] && return 0
  [ -t 0 ] || return 1
  printf '%s [s/N] ' "$1"; read -r a || return 1
  case "$a" in s|S|si|SI|sí|Sí|y|Y) return 0 ;; *) return 1 ;; esac
}

sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

port_in_use() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

gib() { echo $(( $1 / 1073741824 )); }  # bytes -> GiB (redondeo hacia abajo)

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1 ;;
    --check) CHECK_ONLY=1 ;;
    --dir) INSTALL_DIR="$2"; shift ;;
    --port) PORT="$2"; shift ;;
    --no-open) OPEN_BROWSER=0 ;;
    --native-ollama) NATIVE_CHOICE=yes ;;
    --no-native-ollama) NATIVE_CHOICE=no ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) die "Opción desconocida: $1" "Usa --help para ver las opciones." 2 ;;
  esac
  shift
done

say "${B}Atlas-AttackLab ${VERSION}${N} · instalador"
say ""

# ---------------------------------------------------------------- sistema
OS="${ATTACKLAB_UNAME:-$(uname -s)}"            # variable solo para las pruebas
case "$OS" in
  Darwin) OS_NAME=macOS; DOCKER_HELP="https://docs.docker.com/desktop/setup/install/mac-install/" ;;
  Linux)  OS_NAME=Linux; DOCKER_HELP="https://docs.docker.com/engine/install/" ;;
  *) die "Sistema no soportado: $OS" "En Windows usa install.ps1 desde PowerShell." 10 ;;
esac
ok "Sistema: $OS_NAME ($(uname -m))"

# ---------------------------------------------------------------- Docker
if ! command -v "$DOCKER" >/dev/null 2>&1; then
  if command -v podman >/dev/null 2>&1; then
    die "Docker no está instalado (hay Podman, pero esta versión necesita Docker)." "Guía de instalación: $DOCKER_HELP" 11
  fi
  die "Docker no está instalado." "Instálalo y vuelve a ejecutar este instalador: $DOCKER_HELP" 11
fi

if ! info_err="$("$DOCKER" info 2>&1 >/dev/null)"; then
  case "$info_err" in
    *ermission*denied*)
      die "Tu usuario no tiene permiso para usar Docker." \
          "Ejecuta: sudo usermod -aG docker \$USER  y abre una sesión nueva." 12 ;;
    *)
      if [ "$OS_NAME" = macOS ]; then hint="Abre Docker Desktop, espera a que esté en marcha y vuelve a ejecutar el instalador."
      else hint="Arranca el servicio (sudo systemctl start docker) y vuelve a ejecutar el instalador."; fi
      die "Docker está instalado pero no responde." "$hint" 13 ;;
  esac
fi

if ! "$DOCKER" compose version >/dev/null 2>&1; then
  die "Falta Docker Compose v2 (el comando 'docker compose')." "Actualiza Docker: $DOCKER_HELP" 14
fi

read -r D_OSTYPE D_NCPU D_MEM D_ARCH <<EOF
$("$DOCKER" info --format '{{.OSType}} {{.NCPU}} {{.MemTotal}} {{.Architecture}}')
EOF
[ "$D_OSTYPE" = linux ] || die "Docker está usando contenedores $D_OSTYPE." "Cambia a contenedores Linux en Docker Desktop." 15
ok "Docker responde (Compose v2, arquitectura $D_ARCH)"

# ---------------------------------------------------------------- recursos de Docker
MEM_GIB=$(gib "$D_MEM")
if [ "$MEM_GIB" -lt "$MIN_MEM_GIB" ]; then
  die "Docker solo tiene ${MEM_GIB} GiB de memoria y el modelo necesita al menos ${MIN_MEM_GIB}." \
      "Súbela en Docker Desktop > Settings > Resources > Memory (recomendado 8 GiB) y vuelve a ejecutar el instalador." 20
elif [ "$MEM_GIB" -lt "$WARN_MEM_GIB" ]; then
  warn "Docker tiene ${MEM_GIB} GiB de memoria: funcionará justo. Mejor cierra otras aplicaciones pesadas."
else
  ok "Memoria para Docker: ${MEM_GIB} GiB"
fi

THREADS=$(( D_NCPU * 2 / 3 )); [ "$THREADS" -ge 1 ] || THREADS=1
if [ "$D_NCPU" -le 2 ]; then
  warn "Docker solo tiene ${D_NCPU} núcleo(s): las respuestas del modelo tardarán bastante."
else
  ok "Núcleos para Docker: ${D_NCPU} → ${THREADS} hilos para el modelo"
fi

DISK_DIR="$INSTALL_DIR"; [ -d "$DISK_DIR" ] || DISK_DIR="$HOME"
DISK_GIB=$(( $(df -Pk "$DISK_DIR" | awk 'NR==2 {print $4}') / 1048576 ))
[ "$DISK_GIB" -ge "$MIN_DISK_GIB" ] || die "Solo hay ${DISK_GIB} GiB libres y hacen falta ${MIN_DISK_GIB}." "Libera espacio y vuelve a intentarlo." 21
ok "Disco libre: ${DISK_GIB} GiB"

# ---------------------------------------------------------------- aceleración
GPU=no
if "$DOCKER" info --format '{{json .Runtimes}}' 2>/dev/null | grep -q nvidia; then
  GPU=yes; ok "GPU NVIDIA disponible para Docker: el modelo la usará"
elif command -v nvidia-smi >/dev/null 2>&1; then
  warn "Hay una GPU NVIDIA pero Docker no puede usarla: irá en CPU. Para activarla instala NVIDIA Container Toolkit."
fi

# Ollama nativo solo en macOS: Docker Desktop llega al Ollama del equipo sin exponerlo a la red.
# En Linux habría que abrirlo en 0.0.0.0, y no lo vamos a pedir.
USE_NATIVE=no
if [ "$OS_NAME" != macOS ]; then
  [ "$NATIVE_CHOICE" = yes ] && die "--native-ollama solo está soportado en macOS." "En Linux, la GPU NVIDIA se usa desde Docker." 22
elif [ "$NATIVE_CHOICE" != no ] && curl -fsS -m 2 "$NATIVE_OLLAMA_URL/api/version" >/dev/null 2>&1; then
  if [ "$NATIVE_CHOICE" = yes ] || ask_yes "Hay un Ollama instalado en este equipo. ¿Usarlo? (más rápido, sobre todo en Mac)"; then
    USE_NATIVE=yes; ok "Se usará el Ollama de este equipo"
  fi
elif [ "$NATIVE_CHOICE" = yes ]; then
  die "Has pedido usar el Ollama del equipo, pero no responde en $NATIVE_OLLAMA_URL." "Arráncalo o instala sin --native-ollama." 22
fi
if [ "$USE_NATIVE" = no ] && [ "$GPU" = no ] && [ "$OS_NAME" = macOS ]; then
  say "  En Mac, Docker no puede usar la GPU de Apple. Si quieres más velocidad, instala Ollama (https://ollama.com) y vuelve a ejecutar el instalador."
fi

# ---------------------------------------------------------------- puerto
EXISTING_PORT=""
[ -f "$INSTALL_DIR/.env" ] && EXISTING_PORT="$(sed -n 's/^ATTACKLAB_PORT=//p' "$INSTALL_DIR/.env")"
if [ -z "$PORT" ]; then
  if [ -n "$EXISTING_PORT" ] && "$DOCKER" compose --project-directory "$INSTALL_DIR" ps -q lab 2>/dev/null | grep -q .; then
    PORT="$EXISTING_PORT"                # ya es nuestro: reinstalación
  else
    p=$PORT_FIRST
    while [ "$p" -le "$PORT_LAST" ] && port_in_use "$p"; do p=$((p + 1)); done
    [ "$p" -le "$PORT_LAST" ] || die "Los puertos $PORT_FIRST-$PORT_LAST están ocupados." "Libera uno o usa --port <n>." 23
    PORT=$p
  fi
fi
[ "$PORT" = "$PORT_FIRST" ] || warn "El puerto $PORT_FIRST está ocupado: se usará el $PORT"
ok "Dirección: http://127.0.0.1:$PORT"

if [ "$CHECK_ONLY" = 1 ]; then
  say ""
  say "PLAN os=$OS_NAME arch=$D_ARCH ncpu=$D_NCPU threads=$THREADS mem_gib=$MEM_GIB disk_gib=$DISK_GIB gpu=$GPU native=$USE_NATIVE port=$PORT"
  exit 0
fi

# ---------------------------------------------------------------- instalar
say ""
mkdir -p "$INSTALL_DIR" "$BIN_DIR"
cd "$INSTALL_DIR"

fetch() {  # fetch <fichero> <sha256>
  curl -fsSL --retry 3 -o "$1.tmp" "$BASE_URL/lab/$VERSION/$1" \
    || die "No se ha podido descargar $1." "¿Hay conexión a internet? Si usas un proxy, configúralo en el sistema y en Docker." 30
  [ "$(sha256 "$1.tmp")" = "$2" ] || { rm -f "$1.tmp"; die "La suma de comprobación de $1 no coincide." "No se instala nada. Vuelve a descargar el instalador desde la web oficial." 31; }
  mv "$1.tmp" "$1"
}
fetch compose.yaml "$COMPOSE_SHA256"
FILES="-f compose.yaml"
if [ "$GPU" = yes ]; then fetch compose.gpu.yaml "$COMPOSE_GPU_SHA256"; FILES="$FILES -f compose.gpu.yaml"; fi

PROFILES=ollama; OLLAMA_URL=http://ollama:11434
if [ "$USE_NATIVE" = yes ]; then PROFILES=""; OLLAMA_URL="${NATIVE_OLLAMA_URL/127.0.0.1/host.docker.internal}"; fi

cat > .env <<EOF
# Generado por el instalador de Atlas-AttackLab. Para cambiarlo, vuelve a ejecutar el instalador.
ATTACKLAB_VERSION=$VERSION
ATTACKLAB_IMAGE=${ATTACKLAB_IMAGE:-ghcr.io/kinomakino/atlas-attacklab}
ATTACKLAB_PORT=$PORT
ATTACKLAB_THREADS=$THREADS
OLLAMA_URL=$OLLAMA_URL
COMPOSE_PROFILES=$PROFILES
COMPOSE_FILE=$(echo "$FILES" | sed 's/-f //g; s/ /:/g')
EOF
ok "Configuración guardada en $INSTALL_DIR/.env"

say "Descargando las imágenes (la primera vez tarda unos minutos)…"
"$DOCKER" compose pull --quiet || die "No se han podido descargar las imágenes." "Comprueba la conexión. Si usas un proxy, configúralo en Docker." 32

if command -v cosign >/dev/null 2>&1; then
  if cosign verify "${ATTACKLAB_IMAGE:-ghcr.io/kinomakino/atlas-attacklab}:$VERSION" \
       --certificate-identity-regexp '^https://github.com/kinomakino/Atlas-AttackLab/' \
       --certificate-oidc-issuer https://token.actions.githubusercontent.com >/dev/null 2>&1; then
    ok "Firma de la imagen verificada"
  else
    die "La firma de la imagen no es válida." "No se arranca nada. Avísanos: puede ser una imagen manipulada." 33
  fi
else
  say "  (Instala cosign si quieres que el instalador verifique la firma de las imágenes.)"
fi

"$DOCKER" compose up -d --remove-orphans >/dev/null || die "No se ha podido arrancar el lab." "Ejecuta 'atlas-lab logs' para ver qué ha pasado." 34

printf 'Arrancando'
for _ in $(seq 1 60); do
  curl -fsS -m 2 "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1 && break
  printf '.'; sleep 2
done
echo
curl -fsS -m 2 "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1 \
  || die "El lab no ha respondido a tiempo." "Ejecuta 'atlas-lab logs' para ver qué ha pasado." 35
ok "Lab en marcha"

# ---------------------------------------------------------------- comando atlas-lab
cp "$0" "$INSTALL_DIR/install.sh" 2>/dev/null || true
cat > "$BIN_DIR/atlas-lab" <<EOF
#!/usr/bin/env bash
# Atlas-AttackLab: gestión del lab local.
set -euo pipefail
DIR="$INSTALL_DIR"
cd "\$DIR"
url() { echo "http://127.0.0.1:\$(sed -n 's/^ATTACKLAB_PORT=//p' .env)"; }
case "\${1:-help}" in
  start)   docker compose up -d && echo "Lab en \$(url)" ;;
  stop)    docker compose stop ;;
  status)  docker compose ps ;;
  open)    (command -v open >/dev/null && open "\$(url)") || xdg-open "\$(url)" ;;
  logs)    docker compose logs --tail 200 "\${@:2}" ;;
  doctor)  bash "\$DIR/install.sh" --check ;;
  update)  curl -fsSL -o /tmp/atlas-lab-install.sh "$BASE_URL/install.sh" && bash /tmp/atlas-lab-install.sh --yes ;;
  uninstall)
    read -r -p "Se borrarán el lab, tus progresos y los modelos descargados. ¿Seguro? [s/N] " a
    case "\$a" in s|S|si|sí) ;; *) exit 0 ;; esac
    docker compose down -v --rmi all --remove-orphans || true
    rm -rf "\$DIR" "$BIN_DIR/atlas-lab"
    echo "Atlas-AttackLab desinstalado." ;;
  *) echo "Uso: atlas-lab {start|stop|status|open|logs|doctor|update|uninstall}" ;;
esac
EOF
chmod +x "$BIN_DIR/atlas-lab"
ok "Comando 'atlas-lab' instalado en $BIN_DIR"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) warn "Añade $BIN_DIR a tu PATH para usar 'atlas-lab' desde cualquier sitio." ;; esac

say ""
say "${B}Listo.${N} Abre http://127.0.0.1:$PORT"
say "La primera vez, la web te ofrecerá descargar el modelo (unos 2 GB)."
if [ "$OPEN_BROWSER" = 1 ] && [ -t 1 ]; then
  (command -v open >/dev/null 2>&1 && open "http://127.0.0.1:$PORT") || (command -v xdg-open >/dev/null 2>&1 && xdg-open "http://127.0.0.1:$PORT" >/dev/null 2>&1) || true
fi

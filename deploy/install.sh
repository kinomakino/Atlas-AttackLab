#!/usr/bin/env bash
# Instalador de Atlas-AttackLab para macOS y Linux.
#
#   curl -fsSLO https://<web>/install.sh && less install.sh && bash install.sh
#
# Con terminal enseña un menú y acompaña: si falta Docker da el enlace y espera, si está
# parado lo arranca, y si el registro pidiera acceso guía el inicio de
# sesión. Sin terminal (o con --yes) no pregunta nada y se para con un mensaje claro.
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
DOCKER_APP="${ATTACKLAB_DOCKER_APP:-/Applications/Docker.app}"
IMAGE="${ATTACKLAB_IMAGE:-ghcr.io/kinomakino/atlas-attacklab}"
WAIT_SECS="${ATTACKLAB_WAIT_SECS:-180}"     # las pruebas lo acortan
TOKEN_URL="https://github.com/settings/tokens/new?scopes=read:packages&description=atlas-attacklab"
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

ask_yes() {  # ask_yes "pregunta" [s] -> 0 si sí. Con "s", Enter vale como sí.
  [ "$ASSUME_YES" = 1 ] && return 0
  [ "$INTERACTIVE" = 1 ] || return 1
  if [ "${2:-}" = s ]; then printf '%s [S/n] ' "$1"; else printf '%s [s/N] ' "$1"; fi
  read -r a || return 1
  [ -z "$a" ] && [ "${2:-}" = s ] && return 0
  case "$a" in s|S|si|SI|sí|Sí|y|Y) return 0 ;; *) return 1 ;; esac
}

open_url() { [ "$OPEN_BROWSER" = 1 ] || return 0; (command -v open >/dev/null 2>&1 && open "$1") || (command -v xdg-open >/dev/null 2>&1 && xdg-open "$1" >/dev/null 2>&1) || true; }

# Un problema que se puede arreglar: sin terminal se para; con terminal explica,
# ofrece el enlace o el arreglo y deja volver a comprobar.
PROB_CODE=1; PROB_MSG=; PROB_HINT=; PROB_URL=; PROB_FIX=
problem() { PROB_CODE=$1; PROB_MSG=$2; PROB_HINT=$3; PROB_URL=${4:-}; PROB_FIX=${5:-}; return 1; }
resolve() {
  [ "$INTERACTIVE" = 1 ] || die "$PROB_MSG" "$PROB_HINT" "$PROB_CODE"
  printf '\n%s✖ %s%s\n  %s\n' "$R" "$PROB_MSG" "$N" "$PROB_HINT"
  if [ -n "$PROB_URL" ]; then
    say "  Enlace: ${B}$PROB_URL${N}"
    if ask_yes "  ¿Lo abro en tu navegador?" s; then open_url "$PROB_URL"; fi
  fi
  if [ -n "$PROB_FIX" ] && "$PROB_FIX"; then return 0; fi
  printf '  Cuando lo tengas, pulsa Enter para volver a comprobar (o escribe q para salir): '
  read -r a || die "$PROB_MSG" "$PROB_HINT" "$PROB_CODE"
  case "$a" in q|Q) die "$PROB_MSG" "$PROB_HINT" "$PROB_CODE" ;; esac
  say ""
}

wait_docker() {  # espera hasta 3 minutos a que Docker responda
  printf '  Esperando a Docker'
  for _ in $(seq 1 $(( (WAIT_SECS + 2) / 3 ))); do
    if "$DOCKER" info >/dev/null 2>&1; then echo; ok "Docker ya responde"; return 0; fi
    printf '.'; sleep 3
  done
  echo; warn "Docker todavía no responde."; return 1
}

start_docker_desktop() {  # lo intenta arrancar solo; si no puede, se lo pide al alumno
  say "  Intento arrancar Docker…"
  if { [ "$OS_NAME" = macOS ] && [ -d "$DOCKER_APP" ] && open -a "$DOCKER_APP" 2>/dev/null; } \
     || { command -v "$DOCKER" >/dev/null 2>&1 && "$DOCKER" desktop start >/dev/null 2>&1; } \
     || { [ "$OS_NAME" = Linux ] && command -v systemctl >/dev/null 2>&1 && systemctl --user start docker-desktop >/dev/null 2>&1; }; then
    say "  La primera vez, Docker Desktop pide aceptar sus condiciones: hazlo en su ventana."
    find_docker
    wait_docker && return 0
    warn "Docker no ha respondido en $WAIT_SECS segundos. Míralo tú: puede que su ventana esté pidiendo algo."
    return 1
  fi
  warn "No he podido arrancarlo yo. Arráncalo tú como se explica arriba."
  return 1
}

registry_login() {
  local host="${IMAGE%%/*}" user tok
  say "  En GitHub deja marcado solo ${B}read:packages${N}, pulsa ${B}Generate token${N} y copia el token."
  say "  Docker lo guardará en tu equipo, igual que con 'docker login'. Deja el usuario vacío para no hacerlo ahora."
  printf '  Tu usuario de GitHub: '; read -r user || return 1
  [ -n "$user" ] || return 1
  printf '  Token (al pegarlo no se ve nada, es normal): '; read -rs tok || return 1; echo
  [ -n "$tok" ] || return 1
  if printf '%s' "$tok" | "$DOCKER" login "$host" -u "$user" --password-stdin >/dev/null 2>&1; then
    ok "Sesión iniciada en $host como $user"; return 0
  fi
  warn "GitHub no ha aceptado ese usuario o ese token."; return 1
}

sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

port_in_use() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

gib() { echo $(( $1 / 1073741824 )); }  # bytes -> GiB (redondeo hacia abajo)

host_ram_gib() {  # RAM total del equipo (no la de Docker); 0 si no se sabe
  if [ -n "${ATTACKLAB_HOST_RAM_GIB:-}" ]; then echo "$ATTACKLAB_HOST_RAM_GIB"; return; fi   # pruebas
  case "$OS" in
    Darwin) gib "$(sysctl -n hw.memsize 2>/dev/null || echo 0)" ;;
    *) local k; k=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null); echo $(( ${k:-0} / 1048576 )) ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1 ;;
    --check) CHECK_ONLY=1 ;;
    --dir) INSTALL_DIR="$2"; shift ;;
    --port) PORT="$2"; shift ;;
    --no-open) OPEN_BROWSER=0 ;;
    --native-ollama) NATIVE_CHOICE=yes ;;
    --no-native-ollama) NATIVE_CHOICE=no ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) die "Opción desconocida: $1" "Usa --help para ver las opciones." 2 ;;
  esac
  shift
done

INTERACTIVE=0; FROM_MENU=0
if [ "$ASSUME_YES" = 0 ] && { [ -t 0 ] || [ "${ATTACKLAB_FORCE_INTERACTIVE:-}" = 1 ]; }; then INTERACTIVE=1; fi

logo() {  # el logotipo de seguridad/si: corchetes en blanco, la figura en gris
  local w g
  if [ -t 1 ]; then w=$'\033[1;37m'; g=$'\033[38;5;245m'; else w=; g=; fi
  printf '%s%s%s\n' "$w" '███████                    ███████' "$N"
  printf '%s%s%s%s%s%s%s\n' "$w" '██' "$g" '            ▄▄  ▄▄            ' "$w" '██' "$N"
  printf '%s%s%s%s%s%s%s\n' "$w" '██' "$g" '          ▄████████▄          ' "$w" '██' "$N"
  printf '%s%s%s%s%s%s%s\n' "$w" '██' "$g" '          ██████████          ' "$w" '██' "$N"
  printf '%s%s%s%s%s%s%s\n' "$w" '██' "$g" '          ▄▄▄▄▄▄▄▄▄▄          ' "$w" '██' "$N"
  printf '%s%s%s%s%s%s%s\n' "$w" '██' "$g" '    ▀▀██████████████████▀▀    ' "$w" '██' "$N"
  printf '%s%s%s%s%s%s%s\n' "$w" '██' "$g" '      ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄      ' "$w" '██' "$N"
  printf '%s%s%s%s%s%s%s\n' "$w" '██' "$g" '      ███████▀▀▀▀███████      ' "$w" '██' "$N"
  printf '%s%s%s%s%s%s%s\n' "$w" '██' "$g" '       ▀█████    █████▀       ' "$w" '██' "$N"
  printf '%s%s%s%s%s%s%s\n' "$w" '██' "$g" '         ▀████  ████▀         ' "$w" '██' "$N"
  printf '%s%s%s%s%s%s%s\n' "$w" '██' "$g" '           ██▄▄▄▄██           ' "$w" '██' "$N"
  printf '%s%s%s%s%s%s%s\n' "$w" '██' "$g" '            ▀████▀            ' "$w" '██' "$N"
  printf '%s%s%s%s%s%s%s\n' "$w" '██' "$g" '              ▀▀              ' "$w" '██' "$N"
  printf '%s%s%s\n' "$w" '███████                    ███████' "$N"
  printf '%s     s e g u r i d a d / s i%s\n' "$w" "$N"
  printf '%s   c i b e r s e g u r i d a d%s\n\n' "$g" "$N"
}
[ "$INTERACTIVE" = 1 ] && logo
say "${B}Atlas-AttackLab ${VERSION}${N} · instalador"
say ""

if [ "$INTERACTIVE" = 1 ] && [ "$CHECK_ONLY" = 0 ]; then
  while :; do
    say "¿Qué quieres hacer?"
    say "  1) Instalar el lab (o actualizarlo, sin perder tu progreso)"
    say "  2) Comprobar mi equipo, sin instalar nada"
    say "  3) Desinstalar el lab"
    say "  4) Salir"
    printf 'Elige una opción [1]: '; read -r opt || opt=4
    case "${opt:-1}" in
      1) break ;;
      2) CHECK_ONLY=1; FROM_MENU=1; break ;;
      3) if [ -x "$BIN_DIR/atlas-lab" ]; then exec "$BIN_DIR/atlas-lab" uninstall; fi
         say "El lab no está instalado en este equipo."; exit 0 ;;
      4|q|Q) exit 0 ;;
      *) say "Opción no válida."; say "" ;;
    esac
  done
  say ""
fi

# ---------------------------------------------------------------- sistema
OS="${ATTACKLAB_UNAME:-$(uname -s)}"            # variable solo para las pruebas
case "$OS" in
  Darwin) OS_NAME=macOS; DOCKER_HELP="https://docs.docker.com/desktop/setup/install/mac-install/"
          case "$(uname -m)" in arm64) DOCKER_DL="https://desktop.docker.com/mac/main/arm64/Docker.dmg"; CHIP="chip Apple" ;;
                                *) DOCKER_DL="https://desktop.docker.com/mac/main/amd64/Docker.dmg"; CHIP="Intel" ;; esac
          DOCKER_STEPS="Descarga Docker Desktop para Mac con $CHIP, ábrelo, arrástralo a Aplicaciones y arráncalo. Guía: $DOCKER_HELP" ;;
  Linux)  OS_NAME=Linux; DOCKER_HELP="https://docs.docker.com/engine/install/"; DOCKER_DL="$DOCKER_HELP"
          DOCKER_STEPS="Instala Docker Engine para tu distribución siguiendo la guía oficial." ;;
  *) die "Sistema no soportado: $OS" "En Windows usa install.ps1 desde PowerShell." 10 ;;
esac
ok "Sistema: $OS_NAME ($(uname -m))"

# ---------------------------------------------------------------- Docker
find_docker() {  # recién instalado, puede que el comando aún no esté en el PATH de esta terminal
  command -v "$DOCKER" >/dev/null 2>&1 && return 0
  [ "$DOCKER" = docker ] || return 0
  for c in /usr/local/bin/docker "$HOME/.docker/bin/docker" "$DOCKER_APP/Contents/Resources/bin/docker"; do
    if [ -x "$c" ]; then DOCKER="$c"; PATH="$(dirname "$c"):$PATH"; return 0; fi
  done
}

check_docker() {
  find_docker
  if ! command -v "$DOCKER" >/dev/null 2>&1; then
    if [ "$OS_NAME" = macOS ] && [ -d "$DOCKER_APP" ]; then
      problem 13 "Docker Desktop está instalado pero no está arrancado." \
        "Ábrelo desde Aplicaciones y espera a que diga que está en marcha." "" start_docker_desktop; return
    fi
    if command -v podman >/dev/null 2>&1; then
      problem 11 "Docker no está instalado (hay Podman, pero esta versión necesita Docker)." "$DOCKER_STEPS" "$DOCKER_DL"; return
    fi
    problem 11 "Docker no está instalado." "$DOCKER_STEPS" "$DOCKER_DL"; return
  fi

  if ! info_err="$("$DOCKER" info 2>&1 >/dev/null)"; then
    case "$info_err" in
      *ermission*denied*)
        problem 12 "Tu usuario no tiene permiso para usar Docker." \
          "Ejecuta: sudo usermod -aG docker \$USER  y abre una sesión nueva." ;;
      *)
        if [ "$OS_NAME" = macOS ]; then
          problem 13 "Docker está instalado pero no responde." "Abre Docker Desktop y espera a que esté en marcha." "" start_docker_desktop
        else
          problem 13 "Docker está instalado pero no responde." "Arranca el servicio: sudo systemctl start docker" "" start_docker_desktop
        fi ;;
    esac
    return
  fi

  if ! "$DOCKER" compose version >/dev/null 2>&1; then
    problem 14 "Falta Docker Compose v2 (el comando 'docker compose')." "Actualiza Docker a la última versión." "$DOCKER_HELP"; return
  fi

  read -r D_OSTYPE D_NCPU D_MEM D_ARCH <<EOF
$("$DOCKER" info --format '{{.OSType}} {{.NCPU}} {{.MemTotal}} {{.Architecture}}')
EOF
  [ "$D_OSTYPE" = linux ] || { problem 15 "Docker está usando contenedores $D_OSTYPE." "Cambia a contenedores Linux en Docker Desktop."; return; }

  MEM_GIB=$(gib "$D_MEM")
  if [ "$MEM_GIB" -lt "$MIN_MEM_GIB" ]; then
    HOST_GIB=$(host_ram_gib)
    if [ "$HOST_GIB" -gt 0 ] && [ "$HOST_GIB" -lt $((MIN_MEM_GIB + 2)) ]; then
      problem 20 "Docker solo tiene ${MEM_GIB} GiB de memoria y tu equipo tiene ${HOST_GIB} GiB de RAM en total: no llega para el lab." \
        "El modelo necesita ${MIN_MEM_GIB} GiB para Docker y algo más para el sistema: hace falta un equipo con al menos $((MIN_MEM_GIB + 2)) GiB de RAM (mejor 8)."; return
    fi
    problem 20 "Docker solo tiene ${MEM_GIB} GiB de memoria y el modelo necesita al menos ${MIN_MEM_GIB}." \
      "Súbela en Docker Desktop > Settings > Resources > Memory (recomendado 8 GiB) y pulsa Apply & restart."; return
  fi
}
until check_docker; do resolve; done
ok "Docker responde (Compose v2, arquitectura $D_ARCH)"

# ---------------------------------------------------------------- recursos de Docker
if [ "$MEM_GIB" -lt "$WARN_MEM_GIB" ]; then
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

# ---------------------------------------------------------------- acceso a las imágenes
# Las imágenes son públicas; si el registro pidiera iniciar sesión, se guía. Se comprueba antes de
# descargar nada; cualquier otro fallo (sin red, proxy) lo explicará la descarga.
check_registry() {
  local err
  err="$("$DOCKER" manifest inspect "$IMAGE:$VERSION" 2>&1 >/dev/null)" && return 0
  case "$err" in *denied*|*unauthorized*|*authentication*) ;; *) return 0 ;; esac
  problem 36 "El registro de imágenes no te deja descargar el lab." \
    "Pide iniciar sesión en ${IMAGE%%/*} con tu usuario de GitHub y un token con permiso read:packages." \
    "$TOKEN_URL" registry_login
}
until check_registry; do
  if [ "$INTERACTIVE" = 0 ] && [ "$CHECK_ONLY" = 1 ]; then warn "$PROB_MSG"; break; fi
  resolve
done

if [ "$CHECK_ONLY" = 1 ]; then
  say ""
  say "PLAN os=$OS_NAME arch=$D_ARCH ncpu=$D_NCPU threads=$THREADS mem_gib=$MEM_GIB disk_gib=$DISK_GIB gpu=$GPU native=$USE_NATIVE port=$PORT"
  if [ "$FROM_MENU" = 1 ] && ask_yes "${B}Tu equipo está listo para el lab.${N} ¿Lo instalo ahora?" s; then CHECK_ONLY=0; else exit 0; fi
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
ATTACKLAB_IMAGE=$IMAGE
ATTACKLAB_PORT=$PORT
ATTACKLAB_THREADS=$THREADS
OLLAMA_URL=$OLLAMA_URL
COMPOSE_PROFILES=$PROFILES
COMPOSE_FILE=$(echo "$FILES" | sed 's/-f //g; s/ /:/g')
EOF
ok "Configuración guardada en $INSTALL_DIR/.env"

# Con el progreso a la vista: son unos 4 GB y sin barras parece colgado. Si falla, se
# repite en silencio para leer el error y explicarlo.
say "Descargando las imágenes del lab: unos 4 GB la primera vez (casi todo es Ollama, el servidor del modelo)."
say "Según tu conexión, entre 5 y 30 minutos. Verás el progreso aquí abajo."
if ! "$DOCKER" compose pull && ! pull_err="$("$DOCKER" compose pull --quiet 2>&1)"; then
  case "$pull_err" in
    *denied*|*unauthorized*|*authentication*)
      die "El registro de imágenes pide iniciar sesión." \
          "Vuelve a ejecutar el instalador sin --yes: te guiará para iniciar sesión con tu usuario de GitHub y un token." 36 ;;
    *) die "No se han podido descargar las imágenes." "Comprueba la conexión. Si usas un proxy, configúralo en Docker." 32 ;;
  esac
fi

if command -v cosign >/dev/null 2>&1; then
  if cosign verify "$IMAGE:$VERSION" \
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
say "Para jugar: $BASE_URL/guia.html"
if [ -t 1 ]; then open_url "http://127.0.0.1:$PORT"; fi

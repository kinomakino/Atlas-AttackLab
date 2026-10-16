#!/usr/bin/env bash
# Pruebas del instalador con un `docker` simulado: cada caso de cliente de docs/instalacion.md.
# No toca Docker ni instala nada: usa --check y un HOME temporal.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="$HERE/../../deploy/install.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
FAKE="$WORK/docker"
GIB=1073741824
PASS=0; FAIL=0

cat > "$FAKE" <<'EOF'
#!/usr/bin/env bash
# docker simulado: responde según variables FAKE_*.
case "$1 ${2:-}" in
  "info --format")
    case "$3" in
      *Runtimes*) echo "${FAKE_RUNTIMES:-{\"runc\":{}}}" ;;
      *) echo "${FAKE_OSTYPE:-linux} ${FAKE_NCPU:-8} ${FAKE_MEM:-8589934592} ${FAKE_ARCH:-aarch64}" ;;
    esac ;;
  "info "*|"info") [ -n "${FAKE_INFO_ERR:-}" ] && { echo "$FAKE_INFO_ERR" >&2; exit 1; }; exit 0 ;;
  "compose version") exit "${FAKE_COMPOSE_RC:-0}" ;;
  "compose "*) exit 0 ;;
esac
EOF
chmod +x "$FAKE"

# run <nombre> <código esperado> <texto esperado en la salida> [VAR=valor ...] [-- args]
run() {
  local name="$1" want_rc="$2" want_text="$3"; shift 3
  local envs=() args=()
  while [ $# -gt 0 ]; do
    if [ "$1" = -- ]; then shift; args=("$@"); break; fi
    envs+=("$1"); shift
  done
  local out rc
  out="$(env HOME="$WORK/home" ATTACKLAB_DOCKER="$FAKE" ATTACKLAB_NATIVE_OLLAMA_URL="http://127.0.0.1:1" \
         ${envs[@]+"${envs[@]}"} bash "$INSTALLER" --check --yes ${args[@]+"${args[@]}"} 2>&1)"
  rc=$?
  if [ "$rc" = "$want_rc" ] && grep -qF -- "$want_text" <<<"$out"; then
    PASS=$((PASS + 1)); printf 'ok   %s\n' "$name"
  else
    FAIL=$((FAIL + 1)); printf 'FALLA %s (código %s, esperado %s)\n%s\n\n' "$name" "$rc" "$want_rc" "$out"
  fi
}
mkdir -p "$WORK/home"

run "equipo normal: 8 núcleos, 8 GiB" 0 "threads=5 mem_gib=8"
run "equipo grande: 12 núcleos, 16 GiB" 0 "threads=8 mem_gib=16" FAKE_NCPU=12 FAKE_MEM=$((16 * GIB))
run "1 núcleo: avisa y usa 1 hilo" 0 "threads=1" FAKE_NCPU=1
run "2 núcleos: avisa de lentitud" 0 "tardarán bastante" FAKE_NCPU=2
run "poca memoria (3 GiB): se para" 20 "al menos 4" FAKE_MEM=$((3 * GIB))
run "memoria justa (5 GiB): avisa" 0 "funcionará justo" FAKE_MEM=$((5 * GIB))
run "Docker no instalado" 11 "Docker no está instalado" ATTACKLAB_DOCKER=/no/existe
run "Docker parado" 13 "no responde" FAKE_INFO_ERR="Cannot connect to the Docker daemon"
run "sin permiso para Docker" 12 "usermod -aG docker" FAKE_INFO_ERR="permission denied while trying to connect"
run "sin Compose v2" 14 "Compose v2" FAKE_COMPOSE_RC=1
run "contenedores Windows" 15 "contenedores Linux" FAKE_OSTYPE=windows
run "GPU NVIDIA usable" 0 "gpu=yes" FAKE_RUNTIMES='{"nvidia":{},"runc":{}}'
run "arquitectura Intel" 0 "arch=x86_64" FAKE_ARCH=x86_64
run "disco lleno: se para" 21 "GiB libres" ATTACKLAB_MIN_DISK_GIB=999999
run "Linux no ofrece Ollama nativo" 22 "solo está soportado en macOS" ATTACKLAB_UNAME=Linux -- --native-ollama

# Ollama nativo en Mac: un servidor de prueba responde en /api/version.
NPORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
mkdir -p "$WORK/ollama/api"; echo '{"version":"x"}' > "$WORK/ollama/api/version"
python3 -m http.server "$NPORT" --bind 127.0.0.1 --directory "$WORK/ollama" >/dev/null 2>&1 &
OSRV=$!; sleep 1
run "Mac con Ollama nativo: lo usa" 0 "native=yes" ATTACKLAB_UNAME=Darwin ATTACKLAB_NATIVE_OLLAMA_URL="http://127.0.0.1:$NPORT"
run "Mac con Ollama nativo pero --no-native-ollama" 0 "native=no" ATTACKLAB_UNAME=Darwin ATTACKLAB_NATIVE_OLLAMA_URL="http://127.0.0.1:$NPORT" -- --no-native-ollama
run "Mac sin Ollama nativo: recomienda instalarlo" 0 "instala Ollama" ATTACKLAB_UNAME=Darwin
kill "$OSRV" 2>/dev/null; wait "$OSRV" 2>/dev/null

run "opción desconocida" 2 "Opción desconocida" -- --loquesea

# Puerto 8080 ocupado: se abre un servidor de prueba y el instalador debe elegir otro.
if python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",8080))' 2>/dev/null; then
  python3 -c 'import socket,time; s=socket.socket(); s.bind(("127.0.0.1",8080)); s.listen(); time.sleep(20)' &
  SRV=$!; sleep 0.5
  run "puerto 8080 ocupado: usa el siguiente" 0 "port=8081"
  kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null
else
  run "puerto 8080 ocupado: usa otro" 0 "ocupado: se usará"
fi
run "puerto elegido a mano" 0 "port=9123" -- --port 9123

echo
echo "$PASS correctas, $FAIL fallidas"
[ "$FAIL" = 0 ]

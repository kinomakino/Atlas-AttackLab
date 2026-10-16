# Instalador de Atlas-AttackLab para Windows (PowerShell 5.1 o superior).
#
#   Invoke-WebRequest https://<web>/install.ps1 -OutFile install.ps1
#   notepad install.ps1        # léelo antes de ejecutarlo
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# Comprueba Docker Desktop y los recursos que Docker tiene en este equipo, decide la
# configuración, descarga el compose verificado, arranca y deja el comando `atlas-lab`.
# Todo queda en %LOCALAPPDATA%\atlas-lab y en volúmenes de Docker. No necesita administrador.
[CmdletBinding()]
param(
  [switch]$Yes,          # sin preguntas
  [switch]$Check,        # solo diagnóstico
  [string]$Dir = $(if ($env:ATTACKLAB_DIR) { $env:ATTACKLAB_DIR } else { Join-Path $env:LOCALAPPDATA 'atlas-lab' }),
  [int]$Port = 0,
  [switch]$NoOpen
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$Version = '__VERSION__'
$BaseUrl = '__BASE_URL__'
$ComposeSha256 = '__COMPOSE_SHA256__'
$ComposeGpuSha256 = '__COMPOSE_GPU_SHA256__'

$MinMemGiB = 4; $WarnMemGiB = 6
$MinDiskGiB = $(if ($env:ATTACKLAB_MIN_DISK_GIB) { [int]$env:ATTACKLAB_MIN_DISK_GIB } else { 6 })   # variable solo para las pruebas
$PortFirst = 8080; $PortLast = 8099
$Docker = $(if ($env:ATTACKLAB_DOCKER) { $env:ATTACKLAB_DOCKER } else { 'docker' })              # las pruebas inyectan uno simulado
$DockerHelp = 'https://docs.docker.com/desktop/setup/install/windows-install/'

function Say($m) { Write-Host $m }
function Ok($m) { Write-Host "OK  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "!   $m" -ForegroundColor Yellow }
function Die($m, $hint, [int]$code = 1) {
  Write-Host "`nX  $m" -ForegroundColor Red
  if ($hint) { Write-Host "   $hint" }
  exit $code
}
function Invoke-Docker { param([Parameter(ValueFromRemainingArguments)]$a)
  # En PowerShell 5.1, con ErrorActionPreference=Stop, cualquier línea en stderr de un
  # comando externo se convierte en excepción. Aquí queremos el código de salida, no eso.
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    $out = & $Docker @a 2>&1
    return @{ Code = $LASTEXITCODE; Out = ($out | Out-String).Trim() }
  } finally { $ErrorActionPreference = $prev }
}
function Test-PortInUse([int]$p) {
  $c = New-Object System.Net.Sockets.TcpClient
  try { $c.Connect('127.0.0.1', $p); return $true } catch { return $false } finally { $c.Close() }
}

Say "Atlas-AttackLab $Version · instalador`n"
Ok "Sistema: Windows ($env:PROCESSOR_ARCHITECTURE)"

# ---------------------------------------------------------------- Docker
if (-not (Get-Command $Docker -ErrorAction SilentlyContinue)) {
  Die 'Docker no está instalado.' "Instala Docker Desktop (con WSL 2) y vuelve a ejecutar el instalador: $DockerHelp" 11
}
$info = Invoke-Docker info
if ($info.Code -ne 0) {
  Die 'Docker está instalado pero no responde.' 'Abre Docker Desktop, espera a que esté en marcha y vuelve a ejecutar el instalador.' 13
}
if ((Invoke-Docker compose version).Code -ne 0) { Die 'Falta Docker Compose v2.' "Actualiza Docker Desktop: $DockerHelp" 14 }

$parts = (Invoke-Docker info --format '{{.OSType}} {{.NCPU}} {{.MemTotal}} {{.Architecture}}').Out -split '\s+'
$OsType = $parts[0]; $NCpu = [int]$parts[1]; $Mem = [int64]$parts[2]; $Arch = $parts[3]
if ($OsType -ne 'linux') { Die "Docker está usando contenedores $OsType." 'En Docker Desktop: clic derecho en el icono > Switch to Linux containers.' 15 }
Ok "Docker responde (Compose v2, arquitectura $Arch)"

# ---------------------------------------------------------------- recursos de Docker
$MemGiB = [int][math]::Floor($Mem / 1GB)
if ($MemGiB -lt $MinMemGiB) {
  Die "Docker solo tiene $MemGiB GiB de memoria y el modelo necesita al menos $MinMemGiB." `
      'Con WSL 2, súbela en %USERPROFILE%\.wslconfig ([wsl2] memory=8GB) y reinicia Docker Desktop.' 20
} elseif ($MemGiB -lt $WarnMemGiB) {
  Warn "Docker tiene $MemGiB GiB de memoria: funcionará justo. Mejor cierra otras aplicaciones pesadas."
} else { Ok "Memoria para Docker: $MemGiB GiB" }

$Threads = [math]::Max(1, [int][math]::Floor($NCpu * 2 / 3))
if ($NCpu -le 2) { Warn "Docker solo tiene $NCpu núcleo(s): las respuestas del modelo tardarán bastante." }
else { Ok "Núcleos para Docker: $NCpu -> $Threads hilos para el modelo" }

$drive = (Split-Path -Qualifier $env:LOCALAPPDATA).TrimEnd(':')
$DiskGiB = [int][math]::Floor((Get-PSDrive $drive).Free / 1GB)
if ($DiskGiB -lt $MinDiskGiB) { Die "Solo hay $DiskGiB GiB libres y hacen falta $MinDiskGiB." 'Libera espacio y vuelve a intentarlo.' 21 }
Ok "Disco libre: $DiskGiB GiB"

# ---------------------------------------------------------------- aceleración
$Gpu = 'no'
if ((Invoke-Docker info --format '{{json .Runtimes}}').Out -match 'nvidia') {
  $Gpu = 'yes'; Ok 'GPU NVIDIA disponible para Docker: el modelo la usará'
} elseif (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
  Warn 'Hay una GPU NVIDIA pero Docker no puede usarla: irá en CPU. Actualiza el driver de NVIDIA y Docker Desktop.'
}

# ---------------------------------------------------------------- puerto
$envFile = Join-Path $Dir '.env'
if ($Port -eq 0) {
  $existing = $null
  if (Test-Path $envFile) { $existing = (Select-String -Path $envFile -Pattern '^ATTACKLAB_PORT=(\d+)').Matches | ForEach-Object { [int]$_.Groups[1].Value } }
  $ours = $existing -and (Invoke-Docker compose --project-directory $Dir ps -q lab).Out
  if ($ours) { $Port = $existing }
  else {
    $Port = $PortFirst
    while ($Port -le $PortLast -and (Test-PortInUse $Port)) { $Port++ }
    if ($Port -gt $PortLast) { Die "Los puertos $PortFirst-$PortLast están ocupados." 'Libera uno o usa -Port <n>.' 23 }
  }
}
if ($Port -ne $PortFirst) { Warn "El puerto $PortFirst está ocupado: se usará el $Port" }
Ok "Dirección: http://127.0.0.1:$Port"

if ($Check) {
  Say "`nPLAN os=Windows arch=$Arch ncpu=$NCpu threads=$Threads mem_gib=$MemGiB disk_gib=$DiskGiB gpu=$Gpu native=no port=$Port"
  exit 0
}

# ---------------------------------------------------------------- instalar
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Set-Location $Dir
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-Verified($name, $sha) {
  $tmp = "$name.tmp"
  try { Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/lab/$Version/$name" -OutFile $tmp }
  catch { Die "No se ha podido descargar $name." '¿Hay conexión a internet? Si usas un proxy, configúralo en Windows y en Docker Desktop.' 30 }
  if ((Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower() -ne $sha) {
    Remove-Item $tmp; Die "La suma de comprobación de $name no coincide." 'No se instala nada. Vuelve a descargar el instalador desde la web oficial.' 31
  }
  Move-Item -Force $tmp $name
}
Get-Verified 'compose.yaml' $ComposeSha256
$composeFiles = 'compose.yaml'
if ($Gpu -eq 'yes') { Get-Verified 'compose.gpu.yaml' $ComposeGpuSha256; $composeFiles += ';compose.gpu.yaml' }

@"
# Generado por el instalador de Atlas-AttackLab. Para cambiarlo, vuelve a ejecutar el instalador.
ATTACKLAB_VERSION=$Version
ATTACKLAB_PORT=$Port
ATTACKLAB_THREADS=$Threads
OLLAMA_URL=http://ollama:11434
COMPOSE_PROFILES=ollama
COMPOSE_FILE=$composeFiles
"@ | Set-Content -Encoding ASCII $envFile
Ok "Configuración guardada en $envFile"

Say 'Descargando las imágenes (la primera vez tarda unos minutos)...'
if ((Invoke-Docker compose pull --quiet).Code -ne 0) { Die 'No se han podido descargar las imágenes.' 'Comprueba la conexión. Si usas un proxy, configúralo en Docker Desktop.' 32 }

if (Get-Command cosign -ErrorAction SilentlyContinue) {
  & cosign verify "ghcr.io/kinomakino/atlas-attacklab:$Version" `
    --certificate-identity-regexp '^https://github.com/kinomakino/Atlas-AttackLab/' `
    --certificate-oidc-issuer https://token.actions.githubusercontent.com *> $null
  if ($LASTEXITCODE -ne 0) { Die 'La firma de la imagen no es válida.' 'No se arranca nada. Avísanos: puede ser una imagen manipulada.' 33 }
  Ok 'Firma de la imagen verificada'
} else { Say '  (Instala cosign si quieres que el instalador verifique la firma de las imágenes.)' }

if ((Invoke-Docker compose up -d --remove-orphans).Code -ne 0) { Die 'No se ha podido arrancar el lab.' "Ejecuta 'atlas-lab logs' para ver qué ha pasado." 34 }

Write-Host -NoNewline 'Arrancando'
$up = $false
for ($i = 0; $i -lt 60 -and -not $up; $i++) {
  try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 "http://127.0.0.1:$Port/api/health" | Out-Null; $up = $true }
  catch { Write-Host -NoNewline '.'; Start-Sleep 2 }
}
Write-Host ''
if (-not $up) { Die 'El lab no ha respondido a tiempo.' "Ejecuta 'atlas-lab logs' para ver qué ha pasado." 35 }
Ok 'Lab en marcha'

# ---------------------------------------------------------------- comando atlas-lab
$bin = Join-Path $Dir 'bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null
if ($PSCommandPath) { Copy-Item -Force $PSCommandPath (Join-Path $Dir 'install.ps1') }
@"
param([string]`$cmd = 'help')
`$ErrorActionPreference = 'Stop'
Set-Location '$Dir'
`$url = 'http://127.0.0.1:' + ((Select-String -Path .env -Pattern '^ATTACKLAB_PORT=(\d+)').Matches[0].Groups[1].Value)
switch (`$cmd) {
  'start'  { docker compose up -d; "Lab en `$url" }
  'stop'   { docker compose stop }
  'status' { docker compose ps }
  'open'   { Start-Process `$url }
  'logs'   { docker compose logs --tail 200 }
  'doctor' { powershell -ExecutionPolicy Bypass -File '$Dir\install.ps1' -Check }
  'update' { Invoke-WebRequest -UseBasicParsing '$BaseUrl/install.ps1' -OutFile "`$env:TEMP\atlas-lab-install.ps1"; powershell -ExecutionPolicy Bypass -File "`$env:TEMP\atlas-lab-install.ps1" -Yes }
  'uninstall' {
    if ((Read-Host 'Se borrarán el lab, tus progresos y los modelos descargados. ¿Seguro? [s/N]') -notmatch '^(s|si|sí)$') { return }
    docker compose down -v --rmi all --remove-orphans
    Set-Location `$env:TEMP
    `$p = [Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Where-Object { `$_ -and `$_ -ne '$bin' }
    [Environment]::SetEnvironmentVariable('Path', (`$p -join ';'), 'User')
    Remove-Item -Recurse -Force '$Dir'
    'Atlas-AttackLab desinstalado.'
  }
  default { 'Uso: atlas-lab {start|stop|status|open|logs|doctor|update|uninstall}' }
}
"@ | Set-Content -Encoding UTF8 (Join-Path $bin 'atlas-lab.ps1')
"@powershell -NoProfile -ExecutionPolicy Bypass -File ""%~dp0atlas-lab.ps1"" %*" | Set-Content -Encoding ASCII (Join-Path $bin 'atlas-lab.cmd')

$userPath = [string][Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $bin) {
  [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ";$bin"), 'User')
  Ok "Comando 'atlas-lab' instalado (abre una terminal nueva para usarlo)"
} else { Ok "Comando 'atlas-lab' instalado" }

Say "`nListo. Abre http://127.0.0.1:$Port"
Say 'La primera vez, la web te ofrecerá descargar el modelo (unos 2 GB).'
if (-not $NoOpen -and [Environment]::UserInteractive) { Start-Process "http://127.0.0.1:$Port" }

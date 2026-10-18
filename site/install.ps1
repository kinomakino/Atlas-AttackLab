# Instalador de Atlas-AttackLab para Windows (PowerShell 5.1 o superior).
#
#   Invoke-WebRequest https://<web>/install.ps1 -OutFile install.ps1
#   notepad install.ps1        # léelo antes de ejecutarlo
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# Con terminal enseña un menú y acompaña: si falta Docker Desktop da el enlace y espera,
# si está parado lo arranca, y si el registro pide acceso guía el inicio de sesión
# en el registro. Con -Yes (o sin terminal) no pregunta nada y se para con un mensaje claro.
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

$Version = '0.1.0'
$BaseUrl = 'https://witty-rock-0c004b703.6.azurestaticapps.net'
$ComposeSha256 = 'b21e3116a77ac96ec2a358f8754863fa72a0cbd0407d178f151128da1541c0bf'
$ComposeGpuSha256 = '04c2e33d734d876505fce966f974b763108754a07421e7fabf150b1b7bdd6569'

$MinMemGiB = 4; $WarnMemGiB = 6
$MinDiskGiB = $(if ($env:ATTACKLAB_MIN_DISK_GIB) { [int]$env:ATTACKLAB_MIN_DISK_GIB } else { 6 })   # variable solo para las pruebas
$PortFirst = 8080; $PortLast = 8099
$Docker = $(if ($env:ATTACKLAB_DOCKER) { $env:ATTACKLAB_DOCKER } else { 'docker' })              # las pruebas inyectan uno simulado
$DockerHelp = 'https://docs.docker.com/desktop/setup/install/windows-install/'
$DockerDownload = $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'https://desktop.docker.com/win/main/arm64/Docker%20Desktop%20Installer.exe' } else { 'https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe' })
$DockerDesktopExe = $(if ($env:ATTACKLAB_DOCKER_APP) { $env:ATTACKLAB_DOCKER_APP } else {
  $cands = @((Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'), (Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\Docker Desktop.exe'), (Join-Path $env:LOCALAPPDATA 'Programs\Docker\Docker\Docker Desktop.exe'))
  $found = @($cands | Where-Object { Test-Path $_ })
  if ($found.Count) { $found[0] } else { $cands[0] }
})
$WaitSecs = $(if ($env:ATTACKLAB_WAIT_SECS) { [int]$env:ATTACKLAB_WAIT_SECS } else { 180 })                   # las pruebas lo acortan
$WslConfig = $(if ($env:ATTACKLAB_WSLCONFIG) { $env:ATTACKLAB_WSLCONFIG } else { Join-Path $env:USERPROFILE '.wslconfig' })
$Wsl = $(if ($env:ATTACKLAB_WSL) { $env:ATTACKLAB_WSL } else { 'wsl' })
$Image = $(if ($env:ATTACKLAB_IMAGE) { $env:ATTACKLAB_IMAGE } else { 'ghcr.io/kinomakino/atlas-attacklab' })
$TokenUrl = 'https://github.com/settings/tokens/new?scopes=read:packages&description=atlas-attacklab'
# Con terminal se pregunta y se ayuda; las pruebas lo fuerzan con ATTACKLAB_FORCE_INTERACTIVE.
$Interactive = (-not $Yes) -and (($env:ATTACKLAB_FORCE_INTERACTIVE -eq '1') -or ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected))

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
    $out = & $script:Docker @a 2>&1
    return @{ Code = $LASTEXITCODE; Out = ($out | Out-String).Trim() }
  } finally { $ErrorActionPreference = $prev }
}
function Read-Line($prompt) {
  # Con la entrada redirigida (pruebas) se lee de stdin; si no, de la consola.
  Write-Host -NoNewline $prompt
  if ([Console]::IsInputRedirected) { $l = [Console]::In.ReadLine(); Write-Host ''; return $l }
  return (Read-Host)
}
function Read-Secret($prompt) {
  Write-Host -NoNewline $prompt
  if ([Console]::IsInputRedirected) { $l = [Console]::In.ReadLine(); Write-Host ''; return $l }
  $sec = Read-Host -AsSecureString
  return [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}
function Ask-Yes($q, [switch]$DefaultYes) {
  if ($Yes) { return $true }
  if (-not $Interactive) { return $false }
  $a = Read-Line ($q + $(if ($DefaultYes) { ' [S/n] ' } else { ' [s/N] ' }))
  if ($null -eq $a) { return $false }
  if ($a -eq '' -and $DefaultYes) { return $true }
  return ($a -match '^(s|si|sí|y)$')
}
function Open-Url($u) { if (-not $NoOpen) { try { Start-Process $u } catch { } } }

# Un problema que se puede arreglar: sin terminal se para; con terminal explica,
# ofrece el enlace o el arreglo y deja volver a comprobar.
$script:Prob = $null
function Set-Problem([int]$code, $msg, $hint, $url = '', $fix = '') {
  $script:Prob = @{ Code = $code; Msg = $msg; Hint = $hint; Url = $url; Fix = $fix }
  return $false
}
function Resolve-Problem {
  $p = $script:Prob
  if (-not $Interactive) { Die $p.Msg $p.Hint $p.Code }
  Write-Host "`nX  $($p.Msg)" -ForegroundColor Red
  Write-Host "   $($p.Hint)"
  if ($p.Url) {
    Write-Host "   Enlace: $($p.Url)" -ForegroundColor Cyan
    if (Ask-Yes '   ¿Lo abro en tu navegador?' -DefaultYes) { Open-Url $p.Url }
  }
  if ($p.Fix -and (& $p.Fix)) { return }
  $a = Read-Line '   Cuando lo tengas, pulsa Enter para volver a comprobar (o escribe q para salir): '
  if ($null -eq $a -or $a -match '^[qQ]$') { Die $p.Msg $p.Hint $p.Code }
  Say ''
}
function Find-Docker {
  # Recién instalado, el comando aún no está en el PATH de esta ventana.
  if (Get-Command $script:Docker -ErrorAction SilentlyContinue) { return }
  if ($script:Docker -ne 'docker') { return }
  $c = Join-Path (Split-Path $DockerDesktopExe) 'resources\bin\docker.exe'
  if (Test-Path $c) { $script:Docker = $c; $env:Path = (Split-Path $c) + ';' + $env:Path }
}
function Wait-Docker {
  Write-Host -NoNewline '   Esperando a Docker'
  for ($i = 0; $i -lt [math]::Ceiling($WaitSecs / 3); $i++) {
    if ((Invoke-Docker info).Code -eq 0) { Write-Host ''; Ok 'Docker ya responde'; return $true }
    Write-Host -NoNewline '.'; Start-Sleep 3
  }
  Write-Host ''; Warn 'Docker todavía no responde.'; return $false
}
function Start-DockerDesktop {
  # Lo intenta arrancar solo; si no puede, se lo pide al alumno.
  Say '   Intento arrancar Docker Desktop...'
  $started = $false
  if (Test-Path $DockerDesktopExe) { try { Start-Process $DockerDesktopExe; $started = $true } catch { } }
  if (-not $started -and (Get-Command $script:Docker -ErrorAction SilentlyContinue)) { $started = ((Invoke-Docker desktop start).Code -eq 0) }
  if (-not $started) { Warn 'No he podido arrancarlo yo. Ábrelo tú desde el menú Inicio (Docker Desktop) y espera a que ponga «Engine running».'; return $false }
  Say '   La primera vez, Docker Desktop pide aceptar sus condiciones: hazlo en su ventana.'
  Find-Docker
  if (Wait-Docker) { return $true }
  Warn "Docker no ha respondido en $WaitSecs segundos. Míralo tú: puede que su ventana esté pidiendo algo."
  return $false
}
function Get-HostRamGiB {
  # RAM total del equipo (no la de Docker); 0 si no se sabe.
  if ($env:ATTACKLAB_HOST_RAM_GIB) { return [int]$env:ATTACKLAB_HOST_RAM_GIB }
  try { return [int][math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB) } catch { return 0 }
}
function Test-WslBackend {
  # Docker Desktop usa WSL 2 salvo que en sus ajustes se haya elegido Hyper-V.
  $files = $(if ($env:ATTACKLAB_DOCKER_SETTINGS) { @($env:ATTACKLAB_DOCKER_SETTINGS) } else { @((Join-Path $env:APPDATA 'Docker\settings-store.json'), (Join-Path $env:APPDATA 'Docker\settings.json')) })
  foreach ($f in $files) { if ((Test-Path $f) -and ((Get-Content -Raw $f) -match '"[Ww]slEngineEnabled"\s*:\s*false')) { return $false } }
  return $true
}
function Set-WslMemory {
  # Con WSL 2, la memoria de Docker la fija %USERPROFILE%\.wslconfig. Se ajusta, se reinicia WSL y Docker Desktop.
  $hostGiB = Get-HostRamGiB
  $target = $(if ($hostGiB -gt 0) { [math]::Max($MinMemGiB, [math]::Min(8, $hostGiB - 2)) } else { 8 })
  if (-not (Ask-Yes "   ¿Lo arreglo yo? Pondré memory=${target}GB en $WslConfig (guardo una copia del que tengas) y reiniciaré WSL y Docker Desktop; se cerrarán las ventanas de WSL abiertas." -DefaultYes)) { return $false }
  $lines = @()
  if (Test-Path $WslConfig) { $lines = @(Get-Content $WslConfig); Copy-Item -Force $WslConfig "$WslConfig.atlas-lab.bak" }
  $out = New-Object System.Collections.Generic.List[string]
  $inWsl2 = $false; $seen = $false; $done = $false
  foreach ($l in $lines) {
    if ($l -match '^\s*\[(.+)\]\s*$') {
      if ($inWsl2 -and -not $done) { $out.Add("memory=${target}GB"); $done = $true }
      $inWsl2 = ($Matches[1].Trim() -eq 'wsl2'); if ($inWsl2) { $seen = $true }
      $out.Add($l); continue
    }
    if ($inWsl2 -and $l -match '^\s*memory\s*=') { if (-not $done) { $out.Add("memory=${target}GB"); $done = $true }; continue }
    $out.Add($l)
  }
  if (-not $done) { if (-not $seen) { $out.Add('[wsl2]') }; $out.Add("memory=${target}GB") }
  [IO.File]::WriteAllLines($WslConfig, [string[]]$out)   # UTF-8 sin BOM
  Ok "Guardado memory=${target}GB en $WslConfig"
  Say '   Reiniciando WSL y Docker Desktop...'
  Get-Process 'Docker Desktop' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { & $Wsl --shutdown 2>&1 | Out-Null } catch { } finally { $ErrorActionPreference = $prev }
  return (Start-DockerDesktop)
}
function Connect-Registry {
  $hostName = ($Image -split '/')[0]
  Say '   En GitHub deja marcado solo read:packages, pulsa Generate token y copia el token.'
  Say "   Docker lo guardará en tu equipo, igual que con 'docker login'. Deja el usuario vacío para no hacerlo ahora."
  $user = Read-Line '   Tu usuario de GitHub: '
  if (-not $user) { return $false }
  $tok = Read-Secret '   Token (al pegarlo no se ve nada, es normal): '
  if (-not $tok) { return $false }
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $tok | & $script:Docker login $hostName -u $user --password-stdin 2>&1 | Out-Null; $code = $LASTEXITCODE }
  finally { $ErrorActionPreference = $prev }
  if ($code -eq 0) { Ok "Sesión iniciada en $hostName como $user"; return $true }
  Warn 'GitHub no ha aceptado ese usuario o ese token.'; return $false
}

function Test-PortInUse([int]$p) {
  $c = New-Object System.Net.Sockets.TcpClient
  try { $c.Connect('127.0.0.1', $p); return $true } catch { return $false } finally { $c.Close() }
}

function Show-Logo {  # el logotipo de seguridad/si: corchetes en blanco, la figura en gris
  Write-Host '███████                    ███████' -ForegroundColor White
  Write-Host -NoNewline '██' -ForegroundColor White; Write-Host -NoNewline '            ▄▄  ▄▄            ' -ForegroundColor DarkGray; Write-Host '██' -ForegroundColor White
  Write-Host -NoNewline '██' -ForegroundColor White; Write-Host -NoNewline '          ▄████████▄          ' -ForegroundColor DarkGray; Write-Host '██' -ForegroundColor White
  Write-Host -NoNewline '██' -ForegroundColor White; Write-Host -NoNewline '          ██████████          ' -ForegroundColor DarkGray; Write-Host '██' -ForegroundColor White
  Write-Host -NoNewline '██' -ForegroundColor White; Write-Host -NoNewline '          ▄▄▄▄▄▄▄▄▄▄          ' -ForegroundColor DarkGray; Write-Host '██' -ForegroundColor White
  Write-Host -NoNewline '██' -ForegroundColor White; Write-Host -NoNewline '    ▀▀██████████████████▀▀    ' -ForegroundColor DarkGray; Write-Host '██' -ForegroundColor White
  Write-Host -NoNewline '██' -ForegroundColor White; Write-Host -NoNewline '      ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄      ' -ForegroundColor DarkGray; Write-Host '██' -ForegroundColor White
  Write-Host -NoNewline '██' -ForegroundColor White; Write-Host -NoNewline '      ███████▀▀▀▀███████      ' -ForegroundColor DarkGray; Write-Host '██' -ForegroundColor White
  Write-Host -NoNewline '██' -ForegroundColor White; Write-Host -NoNewline '       ▀█████    █████▀       ' -ForegroundColor DarkGray; Write-Host '██' -ForegroundColor White
  Write-Host -NoNewline '██' -ForegroundColor White; Write-Host -NoNewline '         ▀████  ████▀         ' -ForegroundColor DarkGray; Write-Host '██' -ForegroundColor White
  Write-Host -NoNewline '██' -ForegroundColor White; Write-Host -NoNewline '           ██▄▄▄▄██           ' -ForegroundColor DarkGray; Write-Host '██' -ForegroundColor White
  Write-Host -NoNewline '██' -ForegroundColor White; Write-Host -NoNewline '            ▀████▀            ' -ForegroundColor DarkGray; Write-Host '██' -ForegroundColor White
  Write-Host -NoNewline '██' -ForegroundColor White; Write-Host -NoNewline '              ▀▀              ' -ForegroundColor DarkGray; Write-Host '██' -ForegroundColor White
  Write-Host '███████                    ███████' -ForegroundColor White
  Write-Host '     s e g u r i d a d / s i' -ForegroundColor White
  Write-Host "   c i b e r s e g u r i d a d`n" -ForegroundColor DarkGray
}
if ($Interactive) { Show-Logo }
Say "Atlas-AttackLab $Version · instalador`n"

$FromMenu = $false
if ($Interactive -and -not $Check) {
  while ($true) {
    Say '¿Qué quieres hacer?'
    Say '  1) Instalar el lab (o actualizarlo, sin perder tu progreso)'
    Say '  2) Comprobar mi equipo, sin instalar nada'
    Say '  3) Desinstalar el lab'
    Say '  4) Salir'
    $opt = Read-Line 'Elige una opción [1]: '
    if ($null -eq $opt) { $opt = '4' }
    if ($opt -eq '' -or $opt -eq '1') { break }
    if ($opt -eq '2') { $Check = $true; $FromMenu = $true; break }
    if ($opt -eq '3') {
      $cmd = Join-Path $Dir 'bin\atlas-lab.ps1'
      if (Test-Path $cmd) { & powershell -NoProfile -ExecutionPolicy Bypass -File $cmd uninstall; exit 0 }
      Say 'El lab no está instalado en este equipo.'; exit 0
    }
    if ($opt -match '^(4|q|Q)$') { exit 0 }
    Say "Opción no válida.`n"
  }
  Say ''
}
Ok "Sistema: Windows ($env:PROCESSOR_ARCHITECTURE)"

# ---------------------------------------------------------------- Docker
function Test-Docker {
  Find-Docker
  if (-not (Get-Command $script:Docker -ErrorAction SilentlyContinue)) {
    if (Test-Path $DockerDesktopExe) {
      return (Set-Problem 13 'Docker Desktop está instalado pero no está arrancado.' 'Ábrelo desde el menú Inicio y espera a que diga que está en marcha.' '' 'Start-DockerDesktop')
    }
    return (Set-Problem 11 'Docker Desktop no está instalado.' "Descárgalo, ejecuta el instalador (deja marcada la opción de WSL 2), reinicia si te lo pide y arráncalo. Guía: $DockerHelp" $DockerDownload)
  }
  if ((Invoke-Docker info).Code -ne 0) {
    return (Set-Problem 13 'Docker está instalado pero no responde.' 'Abre Docker Desktop y espera a que esté en marcha.' '' 'Start-DockerDesktop')
  }
  if ((Invoke-Docker compose version).Code -ne 0) { return (Set-Problem 14 'Falta Docker Compose v2.' 'Actualiza Docker Desktop a la última versión.' $DockerHelp) }

  $parts = (Invoke-Docker info --format '{{.OSType}} {{.NCPU}} {{.MemTotal}} {{.Architecture}}').Out -split '\s+'
  $script:OsType = $parts[0]; $script:NCpu = [int]$parts[1]; $script:Mem = [int64]$parts[2]; $script:Arch = $parts[3]
  if ($script:OsType -ne 'linux') { return (Set-Problem 15 "Docker está usando contenedores $($script:OsType)." 'En Docker Desktop: clic derecho en el icono > Switch to Linux containers.') }

  $script:MemGiB = [int][math]::Floor($script:Mem / 1GB)
  if ($script:MemGiB -lt $MinMemGiB) {
    $hostGiB = Get-HostRamGiB
    if ($hostGiB -gt 0 -and $hostGiB -lt ($MinMemGiB + 2)) {
      return (Set-Problem 20 "Docker solo tiene $($script:MemGiB) GiB de memoria y tu equipo tiene $hostGiB GiB de RAM en total: no llega para el lab." "El modelo necesita $MinMemGiB GiB para Docker y algo más para Windows: hace falta un equipo con al menos $($MinMemGiB + 2) GiB de RAM (mejor 8).")
    }
    $msg = "Docker solo tiene $($script:MemGiB) GiB de memoria y el modelo necesita al menos $MinMemGiB."
    if (Test-WslBackend) {
      return (Set-Problem 20 $msg "Docker usa WSL 2 y WSL le da poca memoria. Se arregla con [wsl2] memory=8GB en $WslConfig y reiniciando WSL y Docker Desktop." '' 'Set-WslMemory')
    }
    return (Set-Problem 20 $msg 'Súbela en Docker Desktop > Settings > Resources > Advanced > Memory (recomendado 8 GiB) y pulsa Apply & restart.')
  }
  return $true
}
while (-not (Test-Docker)) { Resolve-Problem }
Ok "Docker responde (Compose v2, arquitectura $Arch)"

# ---------------------------------------------------------------- recursos de Docker
if ($MemGiB -lt $WarnMemGiB) {
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
  if (Test-WslBackend) { Warn 'Hay una GPU NVIDIA pero Docker no puede usarla: irá en CPU. Actualiza el driver de NVIDIA y Docker Desktop.' }
  else { Warn 'Hay una GPU NVIDIA, pero Docker Desktop usa Hyper-V y así no puede usarla: irá en CPU. Para usarla, activa Docker Desktop > Settings > General > Use the WSL 2 based engine.' }
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

# ---------------------------------------------------------------- acceso a las imágenes
# Las imágenes son públicas; si el registro pidiera iniciar sesión, se guía. Se comprueba antes de
# descargar nada; cualquier otro fallo (sin red, proxy) lo explicará la descarga.
function Test-Registry {
  $r = Invoke-Docker manifest inspect "${Image}:$Version"
  if ($r.Code -eq 0 -or $r.Out -notmatch 'denied|unauthorized|authentication') { return $true }
  return (Set-Problem 36 'El registro de imágenes no te deja descargar el lab.' "Pide iniciar sesión en $(($Image -split '/')[0]) con tu usuario de GitHub y un token con permiso read:packages." $TokenUrl 'Connect-Registry')
}
while (-not (Test-Registry)) {
  if (-not $Interactive -and $Check) { Warn $script:Prob.Msg; break }
  Resolve-Problem
}

if ($Check) {
  Say "`nPLAN os=Windows arch=$Arch ncpu=$NCpu threads=$Threads mem_gib=$MemGiB disk_gib=$DiskGiB gpu=$Gpu native=no port=$Port"
  if (-not ($FromMenu -and (Ask-Yes 'Tu equipo está listo para el lab. ¿Lo instalo ahora?' -DefaultYes))) { exit 0 }
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
ATTACKLAB_IMAGE=$Image
ATTACKLAB_PORT=$Port
ATTACKLAB_THREADS=$Threads
OLLAMA_URL=http://ollama:11434
COMPOSE_PROFILES=ollama
COMPOSE_FILE=$composeFiles
"@ | Set-Content -Encoding ASCII $envFile
Ok "Configuración guardada en $envFile"

Say 'Descargando las imágenes (la primera vez tarda unos minutos)...'
$pull = Invoke-Docker compose pull --quiet
if ($pull.Code -ne 0) {
  if ($pull.Out -match 'denied|unauthorized|authentication') {
    Die 'El registro de imágenes pide iniciar sesión.' 'Vuelve a ejecutar el instalador sin -Yes: te guiará para iniciar sesión con tu usuario de GitHub y un token.' 36
  }
  Die 'No se han podido descargar las imágenes.' 'Comprueba la conexión. Si usas un proxy, configúralo en Docker Desktop.' 32
}

if (Get-Command cosign -ErrorAction SilentlyContinue) {
  & cosign verify "${Image}:$Version" `
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
Say "Para jugar: $BaseUrl/guia.html"
if ([Environment]::UserInteractive) { Open-Url "http://127.0.0.1:$Port" }

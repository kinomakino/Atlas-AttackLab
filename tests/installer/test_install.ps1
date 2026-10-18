# Pruebas del instalador de Windows con un `docker` simulado. No toca Docker ni instala nada.
# Se ejecutan con Windows PowerShell 5.1 (`powershell`), la versión que trae cualquier Windows.
$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot '..\..\deploy\install.ps1'
$work = Join-Path ([IO.Path]::GetTempPath()) ("atlas-test-" + [guid]::NewGuid())
New-Item -ItemType Directory $work | Out-Null
$fake = Join-Path $work 'docker.ps1'
$GiB = 1073741824
$pass = 0; $fail = 0

@'
$a = $args -join ' '
if ($a -like 'info --format*Runtimes*') { if ($env:FAKE_RUNTIMES) { $env:FAKE_RUNTIMES } else { '{"runc":{}}' }; exit 0 }
if ($a -like 'info --format*') {
  # Tras reiniciar WSL (wsl --shutdown simulado), Docker tiene la memoria de FAKE_MEM_AFTER_WSL.
  $mem = $(if ($env:FAKE_MEM_AFTER_WSL -and (Test-Path (Join-Path $env:FAKE_STATE 'wsl'))) { $env:FAKE_MEM_AFTER_WSL } elseif ($env:FAKE_MEM) { $env:FAKE_MEM } else { 8589934592 })
  "{0} {1} {2} {3}" -f $(if ($env:FAKE_OSTYPE) { $env:FAKE_OSTYPE } else { 'linux' }), $(if ($env:FAKE_NCPU) { $env:FAKE_NCPU } else { 8 }), $mem, 'x86_64'
  exit 0
}
if ($a -eq 'info') {
  if ($env:FAKE_INFO_ERR) { [Console]::Error.WriteLine($env:FAKE_INFO_ERR); exit 1 }
  # Parado la primera vez; el alumno lo arranca y vuelve a comprobar.
  $once = Join-Path $env:FAKE_STATE 'info'
  if ($env:FAKE_INFO_ERR_ONCE -and -not (Test-Path $once)) { New-Item $once | Out-Null; [Console]::Error.WriteLine($env:FAKE_INFO_ERR_ONCE); exit 1 }
  exit 0
}
# Los errores que el instalador lee van por la salida normal: un .ps1 no pasa [Console]::Error por 2>&1 (docker.exe sí).
if ($a -like 'manifest inspect*') {
  if ($env:FAKE_PRIVATE -and -not (Test-Path (Join-Path $env:FAKE_STATE 'login'))) { 'unauthorized: authentication required'; exit 1 }
  exit 0
}
if ($a -like 'login *') {
  if ((@($input) -join '').Trim() -eq $env:FAKE_TOKEN) { New-Item (Join-Path $env:FAKE_STATE 'login') | Out-Null; 'Login Succeeded'; exit 0 }
  'Error response from daemon: unauthorized'; exit 1
}
if ($a -eq 'compose version') { exit $(if ($env:FAKE_COMPOSE_RC) { [int]$env:FAKE_COMPOSE_RC } else { 0 }) }
exit 0
'@ | Set-Content -Encoding UTF8 $fake
$fakeWsl = Join-Path $work 'wsl.ps1'
"if (`$args -contains '--shutdown') { New-Item (Join-Path `$env:FAKE_STATE 'wsl') | Out-Null }" | Set-Content -Encoding UTF8 $fakeWsl

# Run: sin preguntas (-Yes -Check). RunI: como si hubiera terminal, con lo que teclea el alumno en $typed.
function Run($name, [int]$wantCode, $wantText, [hashtable]$vars = @{}, [string[]]$extra = @(), $typed = $null) {
  $saved = @{}
  # Nada de esto toca el equipo: .wslconfig, wsl y los ajustes de Docker son de mentira.
  foreach ($d in @{ ATTACKLAB_WAIT_SECS = 1; ATTACKLAB_WSL = $fakeWsl; ATTACKLAB_WSLCONFIG = (Join-Path $work 'no-wslconfig'); ATTACKLAB_DOCKER_SETTINGS = (Join-Path $work 'no-settings.json') }.GetEnumerator()) {
    if (-not $vars.ContainsKey($d.Key)) { $vars[$d.Key] = $d.Value }
  }
  if (-not $vars.ContainsKey('ATTACKLAB_DOCKER_APP')) { $vars['ATTACKLAB_DOCKER_APP'] = 'C:\no\existe\Docker Desktop.exe' }
  $vars['FAKE_STATE'] = Join-Path $work ('state-' + [guid]::NewGuid())
  New-Item -ItemType Directory $vars['FAKE_STATE'] | Out-Null
  $vars['ATTACKLAB_DOCKER'] = $(if ($vars.ContainsKey('ATTACKLAB_DOCKER')) { $vars['ATTACKLAB_DOCKER'] } else { $fake })
  $vars['ATTACKLAB_DIR'] = Join-Path $work 'lab'
  foreach ($k in $vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, [string]$vars[$k]) }
  # stderr del instalador no debe convertirse en excepción aquí (PowerShell 5.1)
  $ErrorActionPreference = 'Continue'
  if ($null -eq $typed) { $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Check -Yes @extra 2>&1 | Out-String }
  else { $out = $typed | & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -NoOpen @extra 2>&1 | Out-String }
  $code = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
  if ($code -eq $wantCode -and $out.Contains($wantText)) { $script:pass++; "ok    $name" }
  else { $script:fail++; "FALLA $name (codigo $code, esperado $wantCode)`n$out`n" }
}

Run 'equipo normal: 8 nucleos, 8 GiB' 0 'threads=5 mem_gib=8'
Run 'equipo grande: 12 nucleos, 16 GiB' 0 'threads=8 mem_gib=16' @{ FAKE_NCPU = 12; FAKE_MEM = 16 * $GiB }
Run '1 nucleo' 0 'threads=1' @{ FAKE_NCPU = 1 }
Run 'poca memoria: se para' 20 'al menos 4' @{ FAKE_MEM = 3 * $GiB }
Run 'memoria justa: avisa' 0 'justo' @{ FAKE_MEM = 5 * $GiB }
Run 'Docker no instalado' 11 'no est' @{ ATTACKLAB_DOCKER = 'C:\no\existe\docker.exe' }
Run 'Docker parado' 13 'no responde' @{ FAKE_INFO_ERR = 'error during connect' }
Run 'sin Compose v2' 14 'Compose v2' @{ FAKE_COMPOSE_RC = 1 }
Run 'contenedores Windows' 15 'Linux containers' @{ FAKE_OSTYPE = 'windows' }
Run 'GPU NVIDIA usable' 0 'gpu=yes' @{ FAKE_RUNTIMES = '{"nvidia":{},"runc":{}}' }
Run 'disco lleno: se para' 21 'libres' @{ ATTACKLAB_MIN_DISK_GIB = 999999 }
Run 'puerto elegido a mano' 0 'port=9123' @{} @('-Port', '9123')

$listener = [System.Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 8080)
try {
  $listener.Start()
  Run 'puerto 8080 ocupado: usa el siguiente' 0 'port=8081'
} catch { Run 'puerto 8080 ocupado: usa otro' 0 'ocupado' }
finally { $listener.Stop() }

# Acceso al registro sin terminal: avisa y sigue
Run 'sin terminal y sin acceso al registro: avisa' 0 'no te deja' @{ FAKE_PRIVATE = 1 }

# Con terminal: menú y ayudas
function RunI($name, [int]$wantCode, $wantText, [string[]]$typed, [hashtable]$vars = @{}, [string[]]$extra = @()) {
  $vars['ATTACKLAB_FORCE_INTERACTIVE'] = 1
  $vars['ATTACKLAB_DOCKER_APP'] = 'C:\no\existe\Docker Desktop.exe'
  Run $name $wantCode $wantText $vars $extra $typed
}
RunI 'menu: salir' 0 'quieres hacer' @('4')
RunI 'menu: opcion no valida y salir' 0 'lida' @('9', '4')
RunI 'menu: comprobar sin instalar' 0 'threads=5' @('2', 'n')
RunI 'menu: desinstalar sin nada instalado' 0 'instalado en este equipo' @('3')
RunI 'Docker no instalado: enlace de descarga directa' 11 'desktop.docker.com/win/main/' @('n', 'q') @{ ATTACKLAB_DOCKER = 'C:\no\existe\docker.exe' } @('-Check')
RunI 'Docker parado: lo arranca y vuelve a comprobar' 0 'threads=5' @('') @{ FAKE_INFO_ERR_ONCE = 'error during connect' } @('-Check')
RunI 'Docker parado y el alumno sale' 13 'no responde' @('q') @{ FAKE_INFO_ERR = 'error during connect' } @('-Check')
RunI 'poca memoria: explica donde subirla' 20 'wslconfig' @('n', 'q') @{ FAKE_MEM = 3 * $GiB; ATTACKLAB_HOST_RAM_GIB = 16 } @('-Check')
RunI 'equipo con poca RAM: dice que no llega' 20 'no llega para el lab' @('q') @{ FAKE_MEM = 3 * $GiB; ATTACKLAB_HOST_RAM_GIB = 4 } @('-Check')
$hv = Join-Path $work 'settings-hyperv.json'; '{"WslEngineEnabled": false}' | Set-Content $hv
RunI 'poca memoria con Hyper-V: explica el ajuste' 20 'Advanced > Memory' @('q') @{ FAKE_MEM = 3 * $GiB; ATTACKLAB_HOST_RAM_GIB = 16; ATTACKLAB_DOCKER_SETTINGS = $hv } @('-Check')
RunI 'logotipo al arrancar con terminal' 0 'c i b e r s e g u r i d a d' @('4')

# Poca memoria con WSL 2: ajusta .wslconfig (conservando lo demás), reinicia WSL y Docker, y sigue.
$wc = Join-Path $work 'wslconfig'
@('[wsl2]', 'memory=1GB', 'processors=2', '[experimental]', 'autoMemoryReclaim=gradual') | Set-Content $wc
RunI 'poca memoria con WSL 2: lo arregla y sigue' 0 'threads=5' @('', 'n') @{ FAKE_MEM = 1 * $GiB; FAKE_MEM_AFTER_WSL = 8 * $GiB; ATTACKLAB_HOST_RAM_GIB = 16; ATTACKLAB_WSLCONFIG = $wc } @('-Check')
$got = (Get-Content $wc) -join '|'
$want = '[wsl2]|memory=8GB|processors=2|[experimental]|autoMemoryReclaim=gradual'
if ($got -eq $want -and (Test-Path "$wc.atlas-lab.bak")) { $pass++; 'ok    .wslconfig: memory=8GB, resto intacto y copia guardada' }
else { $fail++; "FALLA .wslconfig`n  tiene: $got`n  quería: $want" }
$wc2 = Join-Path $work 'wslconfig-nuevo'
RunI 'sin .wslconfig: lo crea' 0 'threads=5' @('', 'n') @{ FAKE_MEM = 1 * $GiB; FAKE_MEM_AFTER_WSL = 8 * $GiB; ATTACKLAB_HOST_RAM_GIB = 6; ATTACKLAB_WSLCONFIG = $wc2 } @('-Check')
if (((Get-Content $wc2) -join '|') -eq '[wsl2]|memory=4GB') { $pass++; 'ok    .wslconfig nuevo con memory=4GB (equipo de 6 GiB)' }
else { $fail++; "FALLA .wslconfig nuevo: $((Get-Content $wc2) -join '|')" }
RunI 'sin acceso: inicia sesion con el token' 0 'ghcr.io como alumno' @('n', 'alumno', 'ghp_bueno') @{ FAKE_PRIVATE = 1; FAKE_TOKEN = 'ghp_bueno' } @('-Check')
RunI 'token rechazado y el alumno sale' 36 'no ha aceptado' @('n', 'alumno', 'malo', 'q') @{ FAKE_PRIVATE = 1; FAKE_TOKEN = 'ghp_bueno' } @('-Check')

Remove-Item -Recurse -Force $work
"`n$pass correctas, $fail fallidas"
if ($fail -gt 0) { exit 1 }

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
  "{0} {1} {2} {3}" -f $(if ($env:FAKE_OSTYPE) { $env:FAKE_OSTYPE } else { 'linux' }), $(if ($env:FAKE_NCPU) { $env:FAKE_NCPU } else { 8 }), $(if ($env:FAKE_MEM) { $env:FAKE_MEM } else { 8589934592 }), 'x86_64'
  exit 0
}
if ($a -eq 'info') { if ($env:FAKE_INFO_ERR) { [Console]::Error.WriteLine($env:FAKE_INFO_ERR); exit 1 }; exit 0 }
if ($a -eq 'compose version') { exit $(if ($env:FAKE_COMPOSE_RC) { [int]$env:FAKE_COMPOSE_RC } else { 0 }) }
exit 0
'@ | Set-Content -Encoding UTF8 $fake

function Run($name, [int]$wantCode, $wantText, [hashtable]$vars = @{}, [string[]]$extra = @()) {
  $saved = @{}
  $vars['ATTACKLAB_DOCKER'] = $(if ($vars.ContainsKey('ATTACKLAB_DOCKER')) { $vars['ATTACKLAB_DOCKER'] } else { $fake })
  $vars['ATTACKLAB_DIR'] = Join-Path $work 'lab'
  foreach ($k in $vars.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, [string]$vars[$k]) }
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Check @extra 2>&1 | Out-String
  $code = $LASTEXITCODE
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

Remove-Item -Recurse -Force $work
"`n$pass correctas, $fail fallidas"
if ($fail -gt 0) { exit 1 }

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Join-Path $repoRoot 'toolchain'

# Prefer the project-local HashLink runtime; fall back to PATH.
$hashLinkDir = Join-Path $toolchain 'hashlink'
$hlExe = if (Test-Path (Join-Path $hashLinkDir 'hl.exe')) { Join-Path $hashLinkDir 'hl.exe' } else { 'hl' }

Push-Location $repoRoot
try {
    $output = 'bin/boltspark.hl'
    if (-not (Test-Path $output)) { throw "Build output not found ($output). Run .\tools\build-windows.ps1 first." }
    & $hlExe $output
    if ($LASTEXITCODE -ne 0) { throw "Boltspark exited with code $LASTEXITCODE." }
}
finally {
    Pop-Location
}

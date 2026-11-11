$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Join-Path $repoRoot 'toolchain'

# Prefer the project-local pinned toolchain; fall back to PATH.
$haxeDevDir = Join-Path $toolchain 'haxe-dev'
$hashLinkDir = Join-Path $toolchain 'hashlink'
$haxeExe = if (Test-Path (Join-Path $haxeDevDir 'haxe.exe')) { Join-Path $haxeDevDir 'haxe.exe' } else { 'haxe' }

$env:HAXE_STD_PATH = Join-Path $haxeDevDir 'std'
$env:HAXELIB_PATH = Join-Path $toolchain 'haxelib'
$env:NEKOPATH = Join-Path $toolchain 'neko'
if (Test-Path (Join-Path $toolchain 'neko')) {
    $env:Path = "$haxeDevDir;$(Join-Path $toolchain 'neko');$env:Path"
} else {
    $env:Path = "$haxeDevDir;$env:Path"
}

Push-Location $repoRoot
try {
    New-Item -ItemType Directory -Force 'bin' | Out-Null
    & $haxeExe compile.hxml
    if ($LASTEXITCODE -ne 0) { throw "Haxe compilation failed with exit code $LASTEXITCODE." }
    if (-not (Test-Path 'bin/boltspark.hl')) { throw 'Expected output bin/boltspark.hl was not created.' }
    Write-Host 'Build succeeded: bin/boltspark.hl' -ForegroundColor Green
    & (Join-Path $PSScriptRoot 'build-release-windows.ps1')
    Write-Host 'Run with .\tools\run-windows.ps1' -ForegroundColor Green
    Write-Host 'Release executable: .\release\Boltspark.exe' -ForegroundColor Green
}
finally {
    Pop-Location
}

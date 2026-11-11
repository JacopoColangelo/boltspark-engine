$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Join-Path $repoRoot 'toolchain'

# Installs the pinned Haxelib packages into the project-local repository.
# The Haxe toolchain itself (haxe-dev, hashlink, neko) is shipped inside
# toolchain/ and is not reinstalled here.

$haxeDevDir = Join-Path $toolchain 'haxe-dev'
if (-not (Test-Path (Join-Path $haxeDevDir 'haxe.exe'))) {
    throw "Project toolchain not found at $haxeDevDir. Extract the pinned Haxe dev build (2025-10-23, dcda605) there first."
}

$env:HAXE_STD_PATH = Join-Path $haxeDevDir 'std'
$env:HAXELIB_PATH = Join-Path $toolchain 'haxelib'
$env:NEKOPATH = Join-Path $toolchain 'neko'
$env:Path = "$haxeDevDir;$(Join-Path $toolchain 'neko');$env:Path"

$haxelib = Join-Path $haxeDevDir 'haxelib.exe'

Write-Host 'Installing Boltspark Haxe libraries into the project-local repository...' -ForegroundColor Cyan
if (-not (Test-Path $env:HAXELIB_PATH)) {
    & $haxelib setup $env:HAXELIB_PATH
    if ($LASTEXITCODE -ne 0) { throw 'haxelib setup failed.' }
}
& $haxelib install heaps 2.1.0
if ($LASTEXITCODE -ne 0) { throw 'Failed to install Heaps 2.1.0.' }
& $haxelib install format
if ($LASTEXITCODE -ne 0) { throw 'Failed to install format.' }
& $haxelib install hldx 1.16.0
if ($LASTEXITCODE -ne 0) { throw 'Failed to install hldx 1.16.0.' }

Write-Host 'Haxe libraries installed.' -ForegroundColor Green
Write-Host 'Note: the HashLink 1.16.0 runtime (with directx.hdll and dx12.hdll) ships inside toolchain/hashlink.' -ForegroundColor Green
Write-Host 'Run .\tools\check-windows.ps1, then .\tools\build-windows.ps1.' -ForegroundColor Green

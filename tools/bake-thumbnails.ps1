param(
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Join-Path $repoRoot 'toolchain'
$haxeDevDir = Join-Path $toolchain 'haxe-dev'
$hashLinkDir = Join-Path $toolchain 'hashlink'
$nekoDir = Join-Path $toolchain 'neko'
$haxeExe = Join-Path $haxeDevDir 'haxe.exe'
$hlExe = Join-Path $hashLinkDir 'hl.exe'
$bytecode = Join-Path $repoRoot 'bin\bake-thumbnails.hl'

if (-not (Test-Path $haxeExe)) {
    throw "Pinned Haxe compiler not found at $haxeExe."
}
if (-not (Test-Path $hlExe)) {
    throw "HashLink runtime not found at $hlExe."
}

$env:HAXE_STD_PATH = Join-Path $haxeDevDir 'std'
$env:HAXELIB_PATH = Join-Path $toolchain 'haxelib'
$env:NEKOPATH = $nekoDir
$env:HASHLINK = $hashLinkDir
$env:Path = "$haxeDevDir;$nekoDir;$hashLinkDir;$env:Path"

$targetDirectory = if ($OutputDirectory) { $OutputDirectory } else { Join-Path $repoRoot 'src\res\thumbnails\bundles' }
if (-not (Test-Path -LiteralPath $targetDirectory)) {
    New-Item -ItemType Directory -Force $targetDirectory | Out-Null
}
# The HL process runs from bin\, so pass an absolute path explicitly.
$env:BOLTSPARK_THUMBNAIL_DIR = (Resolve-Path -LiteralPath $targetDirectory).Path

Push-Location $repoRoot
try {
    Write-Host '[bake] compiling thumbnail baker...' -ForegroundColor Cyan
    & $haxeExe (Join-Path $repoRoot 'tools\bake\bake-thumbnails.hxml')
    if ($LASTEXITCODE -ne 0) { throw 'Thumbnail baker compilation failed.' }
    if (-not (Test-Path $bytecode)) { throw 'Baker bytecode was not generated.' }

    Write-Host '[bake] rendering offline thumbnails (requires a DX12 display device)...' -ForegroundColor Cyan
    Push-Location (Join-Path $repoRoot 'bin')
    try {
        & $hlExe $bytecode
    }
    finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0) { throw 'Thumbnail baking failed.' }
    Write-Host '[bake] done. Rebuild the editor to embed the new bundles.' -ForegroundColor Green
}
finally {
    Pop-Location
}

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$source = Join-Path $repoRoot 'tools\font-source\JetBrainsMono.ttf'
$destination = Join-Path $repoRoot 'src\res\fonts\jetbrains_mono.ttf'

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "JetBrains Mono source is missing: $source"
}

New-Item -ItemType Directory -Force (Split-Path -Parent $destination) | Out-Null
Copy-Item -LiteralPath $source -Destination $destination -Force

$sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
$destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
if ($sourceHash -ne $destinationHash) {
    throw 'Embedded JetBrains Mono resource does not match its pinned source.'
}

Write-Host 'Synced JetBrains Mono TTF for exact-size runtime FreeType rendering.' `
    -ForegroundColor Green
Write-Host "SHA256: $destinationHash" -ForegroundColor DarkGray

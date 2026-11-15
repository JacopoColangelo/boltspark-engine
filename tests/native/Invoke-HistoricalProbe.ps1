param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        'verify-move-loop',
        'verify-first-keybindings-open',
        'verify-gizmo-drag',
        'verify-transform-gizmo',
        'verify-gizmo-space-arcball',
        'verify-arcball-direction'
    )]
    [string]$Name
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$source = Join-Path $PSScriptRoot "historical\$Name.ps1"
$staged = Join-Path $repoRoot "bin\$Name.ps1"
$closeHelper = Join-Path $PSScriptRoot 'historical\close-boltspark.ps1'
if (-not (Test-Path $source)) { throw "Tracked probe source missing: $source" }

# The historical probes were originally authored under bin/ and intentionally
# derive both repository paths and evidence destinations from PSScriptRoot.
# Stage an ignored copy there so a clean checkout can reproduce those exact
# runs without writing generated evidence into the tracked tests directory.
Copy-Item -LiteralPath $source -Destination $staged -Force
if (Test-Path $closeHelper) {
    Copy-Item -LiteralPath $closeHelper `
        -Destination (Join-Path $repoRoot 'bin\close-boltspark.ps1') -Force
}
Push-Location $repoRoot
try {
    & $staged
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

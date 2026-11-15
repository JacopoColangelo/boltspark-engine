$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $repoRoot
try {
    $compile = Get-Content (Join-Path $repoRoot 'compile.hxml') -Raw
    if ($compile -notmatch '(?m)^\s*-lib\s+hldx\s*$' -or
            $compile -notmatch '(?m)^\s*-D\s+dx12\s*$') {
        throw 'compile.hxml must keep the native hldx + DX12 configuration.'
    }
    if ($compile -match '(?i)hlsdl|opengl') {
        throw 'compile.hxml contains a prohibited alternate graphics backend.'
    }

    $prohibitedRoots = @('package.json', 'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml')
    foreach ($file in $prohibitedRoots) {
        if (Test-Path (Join-Path $repoRoot $file)) {
            throw "Prohibited browser/Node dependency manifest found: $file"
        }
    }

    $sourceFiles = Get-ChildItem (Join-Path $repoRoot 'src') -Recurse -File -Filter '*.hx'
    foreach ($source in $sourceFiles) {
        $match = Select-String -Path $source.FullName `
            -Pattern '^\s*(import|using)\s+(js\.|electron|cef|webview|sdl\.)' `
            -CaseSensitive:$false
        if ($null -ne $match) {
            throw "Prohibited browser/SDL import in $($source.FullName): $($match.Line.Trim())"
        }
    }

    Write-Host '[policy] Native H2D + hldx + DX12 policy passed.' -ForegroundColor Green
}
finally {
    Pop-Location
}

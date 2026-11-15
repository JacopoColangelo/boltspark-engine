param(
    [switch]$Portable,
    [switch]$Build,
    [switch]$NativeSmoke,
    [switch]$CommandHistory,
    [switch]$WindowLifecycle,
    [switch]$DpiProbe,
    [switch]$DeviceReset
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Join-Path $repoRoot 'toolchain'
$haxeDevDir = Join-Path $toolchain 'haxe-dev'
$hashLinkDir = Join-Path $toolchain 'hashlink'
$nekoDir = Join-Path $toolchain 'neko'
$haxeExe = Join-Path $haxeDevDir 'haxe.exe'
$hlExe = Join-Path $hashLinkDir 'hl.exe'
$binDir = Join-Path $repoRoot 'bin'
$testOutput = Join-Path $binDir 'test-results'
$validationPolicyPath = Join-Path $repoRoot 'tests\validation-policy.json'

function Assert-LastExitCode([string]$message) {
    if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "$message (exit code $LASTEXITCODE)."
    }
}

function Invoke-Haxe([string[]]$arguments, [string]$description) {
    Write-Host "[test] $description" -ForegroundColor Cyan
    & $haxeExe @arguments
    Assert-LastExitCode "$description failed"
}

function Invoke-HashLink([string]$bytecode, [string]$description) {
    Write-Host "[test] $description" -ForegroundColor Cyan
    & $hlExe $bytecode
    Assert-LastExitCode "$description failed"
}

if (-not (Test-Path $haxeExe)) {
    throw "Pinned Haxe compiler not found at $haxeExe."
}
$compilerRuntimes = [ordered]@{
    'libmbedcrypto.dll' = 'C66623ED439BC779C09BECF76278EB6615C05D42374AA75CB0592B86D4C9AD62'
    'libmbedtls.dll' = '6E329DB9D8B65B859D89D295D37A2ECCB93EE09E4A3AE17B203EBB14F1DEF18B'
    'libmbedx509.dll' = '1248D18B14471D606AA11A97039252CFDADB8D1712CA18D49A36A76317F683C3'
    'libpcre2-8-0.dll' = 'A794A85AEBE6784AB3491F7EFF353CCE7AF2CB799619E635B49E0C55276A0911'
    'zlib1.dll' = 'A9ADF9FEFE5CA7F283A3BF0488C99AB845B74310C32C6F64025F324676743660'
}
foreach ($compilerRuntime in $compilerRuntimes.Keys) {
    $runtimePath = Join-Path $haxeDevDir $compilerRuntime
    if (-not (Test-Path $runtimePath)) {
        throw "Pinned Haxe compiler runtime missing: $runtimePath"
    }
    $actualHash = (Get-FileHash $runtimePath -Algorithm SHA256).Hash
    if ($actualHash -ne $compilerRuntimes[$compilerRuntime]) {
        throw "Pinned Haxe compiler runtime hash mismatch: $runtimePath"
    }
}

New-Item -ItemType Directory -Force $testOutput | Out-Null

if (-not (Test-Path $validationPolicyPath)) {
    throw "Tracked validation policy is missing: $validationPolicyPath"
}
$validationPolicy = Get-Content $validationPolicyPath -Raw | ConvertFrom-Json
if ($validationPolicy.version -ne 1) {
    throw "Unsupported validation policy version in $validationPolicyPath."
}
if ($validationPolicy.ignoreExternalHardwareValidation -eq $true) {
    Write-Host "[policy] External hardware validation deferred until $($validationPolicy.revisitAt)." -ForegroundColor Yellow
}

Push-Location $repoRoot
try {
    & (Join-Path $PSScriptRoot 'check-policy.ps1')
    if (-not $?) { throw 'Native platform policy check failed.' }

    $directClassPaths = @(
        '-cp', 'src',
        '-cp', 'tests/repro',
        '-cp', 'toolchain/haxelib/heaps/2,1,0',
        '-cp', 'toolchain/haxelib/format/3,8,0'
    )

    if ($Portable) {
        # This path intentionally avoids haxelib/Neko and native runtime DLLs.
        # It is suitable for a clean GitHub-hosted Windows worker: the pinned
        # compiler and Haxelib source trees are tracked, while runtime modules
        # remain a designated-machine test concern.
        Invoke-Haxe @(
            '-cp', 'src',
            '-cp', 'third_party/hlfreetype',
            '-cp', 'toolchain/haxelib/heaps/2,1,0',
            '-cp', 'toolchain/haxelib/format/3,8,0',
            '-cp', 'toolchain/haxelib/hldx/1,16,0',
            '--macro', 'freetype.heaps.Macro.main()',
            '-D', 'heaps=2.1.0',
            '-D', 'format=3.8.0',
            '-D', 'hldx=1.16.0',
            '-D', 'dx12',
            '-D', 'hl_ver=1.16.0',
            '-D', 'windowSize=1440x900',
            '-debug',
            '-hl', 'bin/test-results/portable-boltspark.hl',
            '-main', 'Main'
        ) 'Portable full-project HashLink compilation'

        foreach ($test in @(
            'ArcballRotationRepro',
            'RotationEulerRepro',
            'BoltUiCoreRepro',
            'CommandHistoryRepro',
            'EditorSessionRepro',
            'ComponentSystemRepro',
            'SceneHierarchyRepro',
            'KeybindingsMigrationRepro',
            'ProjectSerializationRepro'
        )) {
            Invoke-Haxe ($directClassPaths + @('--interp', '-main', $test)) `
                "Portable $test"
        }

        Write-Host '[test] Portable compilation and tests passed.' -ForegroundColor Green
        return
    }

    $env:HAXE_STD_PATH = Join-Path $haxeDevDir 'std'
    $env:HAXELIB_PATH = Join-Path $toolchain 'haxelib'
    $env:NEKOPATH = $nekoDir
    $env:HASHLINK = $hashLinkDir
    $env:Path = "$binDir;$haxeDevDir;$nekoDir;$hashLinkDir;$env:Path"

    if ($Build) {
        & (Join-Path $PSScriptRoot 'build.ps1')
        Assert-LastExitCode 'Full Boltspark build'
    } else {
        & (Join-Path $PSScriptRoot 'build.ps1') -Check
        Assert-LastExitCode 'Boltspark environment check'
    }

    $hlTests = @(
        @{ Name = 'ArcballRotationRepro'; Output = 'arcball-rotation-repro.hl'; Args = @('-cp', 'src', '-cp', 'tests/repro', '-lib', 'heaps') },
        @{ Name = 'RotationEulerRepro'; Output = 'rotation-euler-repro.hl'; Args = @('-cp', 'src', '-cp', 'tests/repro', '-lib', 'heaps') },
        @{ Name = 'BoltUiCoreRepro'; Output = 'bolt-ui-core-repro.hl'; Args = @('-cp', 'src', '-cp', 'tests/repro') },
        @{ Name = 'CommandHistoryRepro'; Output = 'command-history-repro.hl'; Args = @('-cp', 'src', '-cp', 'tests/repro') },
        @{ Name = 'EditorSessionRepro'; Output = 'editor-session-repro.hl'; Args = @('-cp', 'src', '-cp', 'tests/repro') },
        @{ Name = 'ComponentSystemRepro'; Output = 'component-system-repro.hl'; Args = @('-cp', 'src', '-cp', 'tests/repro') },
        @{ Name = 'SceneHierarchyRepro'; Output = 'scene-hierarchy-repro.hl'; Args = @('-cp', 'src', '-cp', 'tests/repro') },
        @{ Name = 'SceneObjectAffineRepro'; Output = 'scene-object-affine-repro.hl'; Args = @('-cp', 'src', '-cp', 'tests/repro', '-lib', 'heaps') },
        @{ Name = 'KeybindingsMigrationRepro'; Output = 'keybindings-migration-repro.hl'; Args = @('-cp', 'src', '-cp', 'tests/repro', '-lib', 'heaps') },
        @{ Name = 'ProjectSerializationRepro'; Output = 'project-serialization-repro.hl'; Args = @('-cp', 'src', '-cp', 'tests/repro') }
    )
    foreach ($test in $hlTests) {
        $output = Join-Path $testOutput $test.Output
        Invoke-Haxe ($test.Args + @('-D', 'hl_ver=1.16.0', '-hl', $output, '-main', $test.Name)) `
            "Compile $($test.Name)"
        Invoke-HashLink $output "Run $($test.Name)"
    }

    $dxOutput = Join-Path $testOutput 'dx-carray-repro.hl'
    Invoke-Haxe @(
        '-cp', 'tests/repro', '-lib', 'hldx', '-D', 'dx12',
        '-D', 'hl_ver=1.16.0', '-hl', $dxOutput, '-main', 'DxCArrayRepro'
    ) 'Compile DxCArrayRepro'
    Invoke-HashLink $dxOutput 'Run DxCArrayRepro'

    $freeTypeModule = Join-Path $binDir 'freetype.hdll'
    if (-not (Test-Path $freeTypeModule)) {
        throw 'bin\freetype.hdll is required for FreeTypeRuntimeRepro. Run tools\test.ps1 -Build.'
    }
    $freeTypeOutput = Join-Path $testOutput 'freetype-runtime-repro.hl'
    Invoke-Haxe @(
        '-cp', 'tests/repro', '-cp', 'third_party/hlfreetype', '-lib', 'heaps',
        '-D', 'hl_ver=1.16.0', '--macro', 'freetype.heaps.Macro.main()',
        '-hl', $freeTypeOutput, '-main', 'FreeTypeRuntimeRepro'
    ) 'Compile FreeTypeRuntimeRepro'
    Invoke-HashLink $freeTypeOutput 'Run FreeTypeRuntimeRepro'

    if ($NativeSmoke) {
        & (Join-Path $repoRoot 'tests\native\Test-NativeSmoke.ps1')
        Assert-LastExitCode 'Native smoke test'
    }
    if ($CommandHistory) {
        & (Join-Path $repoRoot 'tests\native\Test-CommandHistory.ps1')
        Assert-LastExitCode 'Native command-history test'
    }
    if ($WindowLifecycle) {
        & (Join-Path $repoRoot 'tests\native\Test-WindowLifecycle.ps1')
        Assert-LastExitCode 'Window/layout lifecycle test'
    }
    if ($DpiProbe) {
        & (Join-Path $repoRoot 'tests\native\Test-DpiAwareness.ps1')
        Assert-LastExitCode 'DPI-awareness test'
    }
    if ($DeviceReset) {
        & (Join-Path $repoRoot 'tests\native\Test-DeviceReset.ps1')
        Assert-LastExitCode 'DX12 device-reset test'
    }

    Write-Host '[test] All requested Boltspark tests passed.' -ForegroundColor Green
}
finally {
    Pop-Location
}

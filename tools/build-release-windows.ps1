$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Join-Path $repoRoot 'toolchain'
$haxeDevDir = Join-Path $toolchain 'haxe-dev'
$hashLinkDir = Join-Path $toolchain 'hashlink'
$nekoDir = Join-Path $toolchain 'neko'
$haxeExe = Join-Path $haxeDevDir 'haxe.exe'
$haxelibExe = Join-Path $haxeDevDir 'haxelib.exe'

foreach ($requiredFile in @($haxeExe, $haxelibExe, (Join-Path $hashLinkDir 'libhl.lib'))) {
    if (-not (Test-Path $requiredFile)) {
        throw "Required native build dependency not found: $requiredFile. Run .\tools\install-dependencies.ps1 and .\tools\check-windows.ps1."
    }
}

$env:HAXE_STD_PATH = Join-Path $haxeDevDir 'std'
$env:HAXELIB_PATH = Join-Path $toolchain 'haxelib'
$env:NEKOPATH = $nekoDir
$env:HASHLINK = $hashLinkDir
$env:Path = "$haxeDevDir;$nekoDir;$hashLinkDir;$env:Path"

cmd /c "`"$haxelibExe`" path hashlink >nul 2>nul"
if ($LASTEXITCODE -ne 0) {
    throw "The project-local HashLink 1.16 haxelib is missing. Run .\tools\install-dependencies.ps1."
}

$pixRuntime = Join-Path $hashLinkDir 'WinPixEventRuntime.dll'
$pixRuntimeHash = '81ADCFD8253C3489BE720DA7E30F16004DC9A1F02A8B418C6C3AEF4993032E6D'
if (-not (Test-Path $pixRuntime)) {
    throw "Missing $pixRuntime. Run .\tools\install-dependencies.ps1 to install the pinned PIX runtime."
}
if ((Get-FileHash $pixRuntime -Algorithm SHA256).Hash -ne $pixRuntimeHash) {
    throw "Unexpected PIX runtime at $pixRuntime. Run .\tools\install-dependencies.ps1 to restore the pinned version."
}

$programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
$vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) {
    throw 'Visual Studio 2022 or newer with the Desktop C++ workload is required for native releases.'
}

$vsRequirements = @('-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64')
$vsPath = (& $vswhere @vsRequirements '-property' 'installationPath' | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($vsPath)) {
    throw 'Could not find Visual Studio with the x64 C++ toolset. Install the Desktop C++ workload.'
}
$vsPath = $vsPath.Trim()
$vsVersion = (& $vswhere @vsRequirements '-property' 'installationVersion' | Select-Object -First 1).Trim()
$vsMajor = [int]$vsVersion.Split('.')[0]

if ($vsMajor -ge 18) {
    $vsTemplate = 'vs2026'
    $platformToolset = 'v145'
} elseif ($vsMajor -eq 17) {
    $vsTemplate = 'vs2022'
    $platformToolset = 'v143'
} else {
    throw "Unsupported Visual Studio version '$vsVersion'. Install Visual Studio 2022 or newer."
}

$msbuild = Join-Path $vsPath 'MSBuild\Current\Bin\MSBuild.exe'
if (-not (Test-Path $msbuild)) {
    throw "MSBuild was not found at $msbuild. Install the Visual Studio C++ workload."
}

$buildRoot = Join-Path $repoRoot 'bin\native-release'
$nativeSource = Join-Path $buildRoot 'Boltspark.c'
$nativeSolution = Join-Path $buildRoot 'Boltspark.sln'
$nativeProject = Join-Path $buildRoot 'Boltspark.vcxproj'
$nativeConfigPath = Join-Path $buildRoot 'hlc.json'
New-Item -ItemType Directory -Force $buildRoot | Out-Null

$compileArgs = @(
    '-cp', 'src',
    '-lib', 'heaps',
    '-lib', 'format',
    '-lib', 'hldx',
    '-lib', 'hashlink',
    '-D', 'dx12',
    '-D', 'hl_ver=1.16.0',
    '-D', 'windowSize=1440x900',
    '-D', "hlgen.makefile=$vsTemplate",
    '-hl', $nativeSource,
    '-main', 'Main'
)

Push-Location $repoRoot
try {
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $haxeOutput = & $haxeExe @compileArgs 2>&1
        $haxeExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $haxeOutput |
        Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } |
        ForEach-Object { Write-Host $_ }
    $generatedFiles = @($nativeSource, $nativeSolution, $nativeProject, $nativeConfigPath)
    foreach ($generatedFile in $generatedFiles) {
        if (-not (Test-Path $generatedFile)) {
            throw "Haxe did not generate the expected native build file: $generatedFile"
        }
    }

    $haxeOutputText = ($haxeOutput | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            [string]$_.TargetObject
        } else {
            [string]$_
        }
    }) -join "`n"
    $expectedMsbuildLookupFailure = $haxeOutputText -match
        "Failed to find a valid MSbuild installation for template $vsTemplate"
    if ($haxeExitCode -ne 0 -and -not $expectedMsbuildLookupFailure) {
        throw "Haxe native code generation failed with exit code $haxeExitCode.`n$haxeOutputText"
    }
    if ($expectedMsbuildLookupFailure) {
        Write-Warning 'HashLink generated the C source and project, but its helper could not locate MSBuild. Building the generated project directly.'
    }

    $nativeConfig = Get-Content $nativeConfigPath -Raw | ConvertFrom-Json
    $nativeModules = @(
        $nativeConfig.libs |
            Where-Object { $_ -ne 'std' } |
            Select-Object -Unique
    )
    if ($nativeModules.Count -eq 0) {
        throw 'Haxe produced no native runtime module list.'
    }

    & $msbuild $nativeSolution "-t:Boltspark" '-nologo' '-verbosity:minimal' `
        '-property:Configuration=Release' '-property:Platform=x64' `
        "-property:PlatformToolset=$platformToolset"
    if ($LASTEXITCODE -ne 0) {
        throw "MSBuild failed with exit code $LASTEXITCODE."
    }

    $nativeExe = Join-Path $buildRoot 'x64\Release\Boltspark.exe'
    if (-not (Test-Path $nativeExe)) {
        throw "MSBuild succeeded but the expected executable was not created: $nativeExe"
    }

    $releaseDir = Join-Path $repoRoot 'release'
    $stagingDir = Join-Path $buildRoot 'package'
    New-Item -ItemType Directory -Force $stagingDir | Out-Null
    Copy-Item -LiteralPath $nativeExe -Destination (Join-Path $stagingDir 'Boltspark.exe') -Force

    $runtimeFiles = @(
        @{ Source = (Join-Path $hashLinkDir 'libhl.dll'); Name = 'libhl.dll' },
        @{ Source = (Join-Path $hashLinkDir 'dxcompiler.dll'); Name = 'dxcompiler.dll' },
        @{ Source = (Join-Path $hashLinkDir 'dxil.dll'); Name = 'dxil.dll' },
        @{ Source = (Join-Path $hashLinkDir 'vcruntime140.dll'); Name = 'vcruntime140.dll' },
        @{ Source = (Join-Path $nekoDir 'vcruntime140_1.dll'); Name = 'vcruntime140_1.dll' },
        @{ Source = (Join-Path $nekoDir 'msvcp140.dll'); Name = 'msvcp140.dll' },
        @{ Source = $pixRuntime; Name = 'WinPixEventRuntime.dll' },
        @{ Source = (Join-Path $hashLinkDir 'WinPixEventRuntime.LICENSE.txt'); Name = 'WinPixEventRuntime-LICENSE.txt' }
    )

    foreach ($runtimeFile in $runtimeFiles) {
        if (-not (Test-Path $runtimeFile.Source)) {
            throw "Required runtime file not found: $($runtimeFile.Source)"
        }
        Copy-Item -LiteralPath $runtimeFile.Source -Destination (Join-Path $stagingDir $runtimeFile.Name) -Force
    }

    foreach ($module in $nativeModules) {
        $moduleFile = "$module.hdll"
        $modulePath = Join-Path $hashLinkDir $moduleFile
        if (-not (Test-Path $modulePath)) {
            throw "Required HashLink module not found: $modulePath"
        }
        Copy-Item -LiteralPath $modulePath -Destination (Join-Path $stagingDir $moduleFile) -Force
    }

    New-Item -ItemType Directory -Force $releaseDir | Out-Null
    $replaceNames = @(
        'Boltspark.exe',
        'libhl.dll',
        'dxcompiler.dll',
        'dxil.dll',
        'vcruntime140.dll',
        'vcruntime140_1.dll',
        'msvcp140.dll',
        'WinPixEventRuntime.dll',
        'WinPixEventRuntime-LICENSE.txt'
    )
    $replaceNames += Get-ChildItem $hashLinkDir -Filter '*.hdll' -File | Select-Object -ExpandProperty Name
    foreach ($name in ($replaceNames | Select-Object -Unique)) {
        $oldFile = Join-Path $releaseDir $name
        if (Test-Path $oldFile) {
            Remove-Item -LiteralPath $oldFile -Force
        }
    }
    Copy-Item -Path (Join-Path $stagingDir '*') -Destination $releaseDir -Force

    Write-Host "Native release built: release\Boltspark.exe" -ForegroundColor Green
}
finally {
    Pop-Location
}

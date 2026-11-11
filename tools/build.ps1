param(
    [switch]$InstallDependencies,
    [switch]$Check,
    [switch]$Run
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Join-Path $repoRoot 'toolchain'
$haxeDevDir = Join-Path $toolchain 'haxe-dev'
$hashLinkDir = Join-Path $toolchain 'hashlink'
$nekoDir = Join-Path $toolchain 'neko'
$haxeExe = Join-Path $haxeDevDir 'haxe.exe'
$haxelibExe = Join-Path $haxeDevDir 'haxelib.exe'
$hlExe = Join-Path $hashLinkDir 'hl.exe'
$pixVersion = '1.0.240308001'
$pixPackageHash = '726ACC93D6968E2146261A1E415521747D50AD69894C2B42B5D0D4C29FD66EC4'
$pixRuntimeHash = '81ADCFD8253C3489BE720DA7E30F16004DC9A1F02A8B418C6C3AEF4993032E6D'

$actionCount = 0
foreach ($requestedAction in @($InstallDependencies, $Check, $Run)) {
    if ($requestedAction) { $actionCount++ }
}
if ($actionCount -gt 1) {
    throw 'Choose only one of -InstallDependencies, -Check, or -Run.'
}

$env:HAXE_STD_PATH = Join-Path $haxeDevDir 'std'
$env:HAXELIB_PATH = Join-Path $toolchain 'haxelib'
$env:NEKOPATH = $nekoDir
$env:HASHLINK = $hashLinkDir
$env:Path = "$haxeDevDir;$nekoDir;$hashLinkDir;$env:Path"

function Install-Dependencies {
    if (-not (Test-Path $haxeExe)) {
        throw "Project Haxe compiler not found at $haxeExe. Restore the pinned toolchain first."
    }

    $haxelibDir = $env:HAXELIB_PATH
    Write-Host 'Installing pinned project-local Haxe dependencies...' -ForegroundColor Cyan
    if (-not (Test-Path $haxelibDir)) {
        & $haxelibExe setup $haxelibDir
        if ($LASTEXITCODE -ne 0) { throw 'haxelib setup failed.' }
    }
    & $haxelibExe install heaps 2.1.0
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install Heaps 2.1.0.' }
    & $haxelibExe install format
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install format.' }
    & $haxelibExe install hldx 1.16.0
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install hldx 1.16.0.' }

    $hashlinkPath = (cmd /c "`"$haxelibExe`" path hashlink 2>nul") -join ''
    if ($LASTEXITCODE -eq 0) {
        if ($hashlinkPath -notmatch '-D hashlink=1\.16\.0') {
            throw "Expected HashLink/C haxelib 1.16.0, found '$hashlinkPath'. Remove the incompatible local package before continuing."
        }
    } else {
        & $haxelibExe git hashlink https://github.com/HaxeFoundation/hashlink.git 1.16 other/haxelib/
        if ($LASTEXITCODE -ne 0) { throw 'Failed to install the HashLink 1.16.0 Haxe/C support library.' }
    }

    $pixRuntime = Join-Path $hashLinkDir 'WinPixEventRuntime.dll'
    $pixLicense = Join-Path $hashLinkDir 'WinPixEventRuntime.LICENSE.txt'
    $refreshPixRuntime = $true
    if (Test-Path $pixRuntime) {
        $refreshPixRuntime = (Get-FileHash $pixRuntime -Algorithm SHA256).Hash -ne $pixRuntimeHash
    }

    if ($refreshPixRuntime -or -not (Test-Path $pixLicense)) {
        $tempRoot = Join-Path $env:TEMP ('boltspark-winpix-' + [guid]::NewGuid().ToString('N'))
        $packageFile = Join-Path $tempRoot 'WinPixEventRuntime.zip'
        $packageContents = Join-Path $tempRoot 'package'
        try {
            New-Item -ItemType Directory -Force $tempRoot | Out-Null
            $packageUrl = "https://api.nuget.org/v3-flatcontainer/winpixeventruntime/$pixVersion/winpixeventruntime.$pixVersion.nupkg"
            Invoke-WebRequest -Uri $packageUrl -OutFile $packageFile
            if ((Get-FileHash $packageFile -Algorithm SHA256).Hash -ne $pixPackageHash) {
                throw "Downloaded PIX package $pixVersion failed SHA256 verification."
            }
            Expand-Archive -LiteralPath $packageFile -DestinationPath $packageContents

            $sourceRuntime = Join-Path $packageContents 'bin\x64\WinPixEventRuntime.dll'
            $sourceLicense = Join-Path $packageContents 'license.txt'
            if (-not (Test-Path $sourceRuntime) -or -not (Test-Path $sourceLicense)) {
                throw "PIX package $pixVersion is missing its x64 runtime or license file."
            }
            if ((Get-FileHash $sourceRuntime -Algorithm SHA256).Hash -ne $pixRuntimeHash) {
                throw "PIX runtime $pixVersion failed SHA256 verification."
            }

            New-Item -ItemType Directory -Force $hashLinkDir | Out-Null
            Copy-Item -LiteralPath $sourceRuntime -Destination $pixRuntime -Force
            Copy-Item -LiteralPath $sourceLicense -Destination $pixLicense -Force
        }
        finally {
            if (Test-Path $tempRoot) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }

    Write-Host "Dependencies ready: Heaps 2.1.0, format, hldx 1.16.0, HashLink/C 1.16.0, PIX $pixVersion." -ForegroundColor Green
}

function Get-RequiredFile([string]$Path, [string]$Message) {
    if (-not (Test-Path $Path)) { throw "Missing file: $Path`n$Message" }
    return (Resolve-Path $Path).Path
}

function Get-VisualStudioConfiguration {
    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) {
        throw 'Visual Studio 2022 or newer with the Desktop C++ workload is required for native builds.'
    }

    $vsRequirements = @('-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64')
    $vsPathOutput = & $vswhere @vsRequirements '-property' 'installationPath'
    $vswhereExitCode = $LASTEXITCODE
    $vsPath = ($vsPathOutput | Select-Object -First 1)
    if ($vswhereExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($vsPath)) {
        throw 'Could not find Visual Studio with the x64 C++ toolset. Install the Desktop C++ workload.'
    }
    $vsPath = $vsPath.Trim()

    $vsVersionOutput = & $vswhere @vsRequirements '-property' 'installationVersion'
    $vswhereExitCode = $LASTEXITCODE
    $vsVersion = ($vsVersionOutput | Select-Object -First 1)
    if ($vswhereExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($vsVersion)) {
        throw "Could not determine the Visual Studio version at $vsPath."
    }
    $vsVersion = $vsVersion.Trim()
    $vsMajor = [int]$vsVersion.Split('.')[0]
    if ($vsMajor -ge 18) {
        $vsTemplate = 'vs2026'
        $platformToolset = 'v145'
        $cmakeGenerator = 'Visual Studio 18 2026'
    } elseif ($vsMajor -eq 17) {
        $vsTemplate = 'vs2022'
        $platformToolset = 'v143'
        $cmakeGenerator = 'Visual Studio 17 2022'
    } else {
        throw "Unsupported Visual Studio version '$vsVersion'. Install Visual Studio 2022 or newer."
    }

    $msbuild = Join-Path $vsPath 'MSBuild\Current\Bin\MSBuild.exe'
    if (-not (Test-Path $msbuild)) {
        throw "MSBuild was not found at $msbuild. Install the Visual Studio C++ workload."
    }

    return [PSCustomObject]@{
        InstallationPath = $vsPath
        Version = $vsVersion
        Template = $vsTemplate
        PlatformToolset = $platformToolset
        CMakeGenerator = $cmakeGenerator
        MSBuild = $msbuild
        VSWhere = $vswhere
    }
}

function Apply-HashLinkPatch([string]$SourceRoot, [string]$PatchPath, [string]$Description) {
    if (-not (Test-Path $PatchPath)) {
        throw "$Description patch was not found: $PatchPath"
    }

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $null = & git -C $SourceRoot apply --check $PatchPath 2>&1
        $patchCheckExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($patchCheckExitCode -eq 0) {
        & git -C $SourceRoot apply $PatchPath
        if ($LASTEXITCODE -ne 0) {
            throw "Could not apply the $Description patch to HashLink."
        }
        Write-Host "$Description patch applied." -ForegroundColor DarkGray
        return
    }

    try {
        $ErrorActionPreference = 'Continue'
        $null = & git -C $SourceRoot apply --reverse --check $PatchPath 2>&1
        $reversePatchCheckExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($reversePatchCheckExitCode -ne 0) {
        throw "HashLink source differs from the expected version; the $Description patch cannot be applied."
    }
    Write-Host "$Description patch is already applied." -ForegroundColor DarkGray
}

function Test-Environment {
    Write-Host 'Boltspark Windows 11 / DirectX 12 environment check' -ForegroundColor Cyan
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'This build configuration targets Windows 11 x64.'
    }
    if (-not [Environment]::Is64BitOperatingSystem) {
        throw 'Boltspark foundation currently targets Windows x64 only.'
    }
    $os = Get-CimInstance Win32_OperatingSystem
    if ([int]$os.BuildNumber -lt 22000) {
        throw "Windows 11 is required. Detected build $($os.BuildNumber)."
    }
    Write-Host "OS: $($os.Caption) build $($os.BuildNumber) x64"

    $compiler = Get-RequiredFile $haxeExe `
        'Restore the pinned Haxe dev compiler (2025-10-23, dcda605) into toolchain/haxe-dev.'
    $runtime = Get-RequiredFile $hlExe 'Restore the HashLink 1.16.0 runtime into toolchain/hashlink.'
    Get-RequiredFile $haxelibExe 'The pinned Haxe distribution must include haxelib.exe.' | Out-Null

    $haxeVersion = (& $compiler --version).Trim()
    $hlVersion = (& $runtime --version).Trim()
    Write-Host "Haxe version: $haxeVersion"
    Write-Host "HashLink version: $hlVersion"
    if ($haxeVersion -notmatch '^5\.0\.0-preview\.1\+dcda605') {
        throw "Haxe 5.0.0-preview.1+dcda605 is pinned. Found '$haxeVersion'."
    }
    if ($hlVersion -ne '1.16.0') {
        throw "HashLink 1.16.0 is pinned. Found '$hlVersion' at $runtime."
    }

    foreach ($library in @('heaps', 'format', 'hldx', 'hashlink')) {
        cmd /c "`"$haxelibExe`" path $library 2>nul" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Haxelib package '$library' is missing. Run .\tools\build.ps1 -InstallDependencies."
        }
        Write-Host "Haxelib package OK: $library"
    }
    $hldxVersion = (cmd /c "`"$haxelibExe`" list hldx 2>nul") -join ''
    if ($hldxVersion -notmatch '1\.16\.0') {
        throw "hldx 1.16.0 is pinned. Found '$hldxVersion'."
    }
    $hashlinkHaxelib = (cmd /c "`"$haxelibExe`" path hashlink 2>nul") -join ''
    if ($LASTEXITCODE -ne 0 -or $hashlinkHaxelib -notmatch '-D hashlink=1\.16\.0') {
        throw "HashLink/C support library 1.16.0 is required. Found '$hashlinkHaxelib'."
    }

    $requiredFiles = @(
        @{ Path = (Join-Path $hashLinkDir 'dx12.hdll'); Message = 'HashLink must include dx12.hdll.' },
        @{ Path = (Join-Path $hashLinkDir 'directx.hdll'); Message = 'HashLink must include directx.hdll.' },
        @{ Path = (Join-Path $hashLinkDir 'directx.lib'); Message = 'HashLink must include directx.lib for native linking.' },
        @{ Path = (Join-Path $hashLinkDir 'libhl.dll'); Message = 'HashLink must include libhl.dll.' },
        @{ Path = (Join-Path $hashLinkDir 'libhl.lib'); Message = 'HashLink must include libhl.lib for native linking.' },
        @{ Path = (Join-Path $hashLinkDir 'dxcompiler.dll'); Message = 'HashLink must include dxcompiler.dll.' },
        @{ Path = (Join-Path $hashLinkDir 'dxil.dll'); Message = 'HashLink must include dxil.dll.' },
        @{ Path = (Join-Path $hashLinkDir 'WinPixEventRuntime.dll'); Message = 'Run .\tools\build.ps1 -InstallDependencies to install the pinned PIX runtime.' }
    )
    foreach ($required in $requiredFiles) {
        Get-RequiredFile $required.Path $required.Message | Out-Null
    }
    $actualPixHash = (Get-FileHash (Join-Path $hashLinkDir 'WinPixEventRuntime.dll') -Algorithm SHA256).Hash
    if ($actualPixHash -ne $pixRuntimeHash) {
        throw "Unexpected WinPixEventRuntime.dll hash: $actualPixHash. Run .\tools\build.ps1 -InstallDependencies to restore it."
    }

    $buildConfig = Get-Content (Join-Path $repoRoot 'compile.hxml') -Raw
    if ($buildConfig -notmatch '(?m)^\s*-lib\s+hldx\s*$') {
        throw 'compile.hxml must select -lib hldx for the Windows DirectX target.'
    }
    if ($buildConfig -notmatch '(?m)^\s*-D\s+dx12\s*$') {
        throw 'compile.hxml must contain -D dx12.'
    }
    if ($buildConfig -notmatch '(?m)^\s*-D\s+hl_ver=1\.16\.0\s*$') {
        throw 'compile.hxml must define -D hl_ver=1.16.0.'
    }
    if ($buildConfig -match 'hlsdl|sdl|opengl') {
        throw 'compile.hxml must not select SDL/OpenGL for the Windows DirectX 12 target.'
    }

    $visualStudio = Get-VisualStudioConfiguration
    Write-Host "Visual Studio: $($visualStudio.Version) | MSBuild: $($visualStudio.MSBuild)"

    Write-Host 'Environment check passed.' -ForegroundColor Green
    Write-Host "Toolchain: Haxe $haxeVersion | HashLink $hlVersion | Heaps 2.1.0 | hldx 1.16.0 | HashLink/C 1.16.0" -ForegroundColor Green
}

function New-NativeRelease {
    $visualStudio = Get-VisualStudioConfiguration
    $vsPath = $visualStudio.InstallationPath
    $vsTemplate = $visualStudio.Template
    $platformToolset = $visualStudio.PlatformToolset
    $cmakeGenerator = $visualStudio.CMakeGenerator
    $msbuild = $visualStudio.MSBuild
    $env:VSWHERE = $visualStudio.VSWhere

    $hashLinkSource = Join-Path $env:HAXELIB_PATH 'hashlink\git'
    if (-not (Test-Path (Join-Path $hashLinkSource 'libs\directx\window.c'))) {
        throw "HashLink native source was not found at $hashLinkSource. Run .\tools\build.ps1 -InstallDependencies."
    }

    $resizePatch = Join-Path $repoRoot 'tools\patches\hashlink-directx-live-resize.patch'
    Apply-HashLinkPatch $hashLinkSource $resizePatch 'Interactive resize'
    $vswherePatch = Join-Path $repoRoot 'tools\patches\hashlink-vswhere-path.patch'
    Apply-HashLinkPatch $hashLinkSource $vswherePatch 'Visual Studio locator path'
    if ($vsTemplate -eq 'vs2026') {
        $vs2026ToolsetPatch = Join-Path $repoRoot 'tools\patches\hashlink-vs2026-v145.patch'
        Apply-HashLinkPatch $hashLinkSource $vs2026ToolsetPatch 'Visual Studio 2026 v145 toolset'
    }

    $cmakeExe = Join-Path $vsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    if (-not (Test-Path $cmakeExe)) {
        $cmakeCommand = Get-Command cmake -ErrorAction SilentlyContinue
        if ($null -ne $cmakeCommand) {
            $cmakeExe = $cmakeCommand.Source
        } else {
            throw 'CMake is required to rebuild the patched DirectX module. Install the C++ CMake tools for Visual Studio.'
        }
    }

    $nativeModuleBuild = Join-Path $repoRoot 'bin\native-modules'
    $cmakeArgs = @(
        '-S', $hashLinkSource,
        '-B', $nativeModuleBuild,
        '-G', $cmakeGenerator,
        '-A', 'x64',
        '-DBUILD_SHARED_LIBS=ON',
        '-DWITH_VM=OFF',
        '-DWITH_DX12=OFF',
        '-DWITH_FMT=OFF',
        '-DWITH_OPENAL=OFF',
        '-DWITH_SDL=OFF',
        '-DWITH_SQLITE=OFF',
        '-DWITH_SSL=OFF',
        '-DWITH_UI=OFF',
        '-DWITH_UV=OFF',
        '-DWITH_VIDEO=OFF',
        '-DWITH_HEAPS=OFF'
    )
    & $cmakeExe @cmakeArgs
    if ($LASTEXITCODE -ne 0) {
        throw 'CMake configuration for the patched DirectX module failed.'
    }
    & $cmakeExe --build $nativeModuleBuild --config Release --target directx.hdll
    if ($LASTEXITCODE -ne 0) {
        throw 'Building the patched DirectX module failed.'
    }
    $patchedDirectXModule = Join-Path $nativeModuleBuild 'bin\directx.hdll'
    $patchedDirectXImportLibrary = Join-Path $nativeModuleBuild 'bin\directx.lib'
    if (-not (Test-Path $patchedDirectXModule)) {
        throw "CMake succeeded but the patched module was not created: $patchedDirectXModule"
    }
    if (-not (Test-Path $patchedDirectXImportLibrary)) {
        throw "CMake succeeded but the patched import library was not created: $patchedDirectXImportLibrary"
    }
    $directXImportLibrary = Join-Path $hashLinkDir 'directx.lib'
    $directXImportLibraryBackup = Join-Path $nativeModuleBuild 'directx-original.lib'
    Copy-Item -LiteralPath $directXImportLibrary -Destination $directXImportLibraryBackup -Force
    Copy-Item -LiteralPath $patchedDirectXModule -Destination (Join-Path $hashLinkDir 'directx.hdll') -Force
    Write-Host 'Patched DirectX module built for interactive window resizing.' -ForegroundColor Green

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

    Copy-Item -LiteralPath $patchedDirectXImportLibrary -Destination $directXImportLibrary -Force
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
    }
    finally {
        Copy-Item -LiteralPath $directXImportLibraryBackup -Destination $directXImportLibrary -Force
    }
    $haxeOutput |
        Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } |
        ForEach-Object { Write-Host $_ }

    foreach ($generatedFile in @($nativeSource, $nativeSolution, $nativeProject, $nativeConfigPath)) {
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

    try {
        Copy-Item -LiteralPath $patchedDirectXImportLibrary -Destination $directXImportLibrary -Force
        & $msbuild $nativeSolution '-t:Boltspark' '-nologo' '-verbosity:minimal' `
            '-property:Configuration=Release' '-property:Platform=x64' `
            "-property:PlatformToolset=$platformToolset"
        if ($LASTEXITCODE -ne 0) {
            throw "MSBuild failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Copy-Item -LiteralPath $directXImportLibraryBackup -Destination $directXImportLibrary -Force
    }

    $nativeExe = Join-Path $buildRoot 'x64\Release\Boltspark.exe'
    if (-not (Test-Path $nativeExe)) {
        throw "MSBuild succeeded but the expected executable was not created: $nativeExe"
    }

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
        @{ Source = (Join-Path $hashLinkDir 'WinPixEventRuntime.dll'); Name = 'WinPixEventRuntime.dll' },
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

    $releaseDir = Join-Path $repoRoot 'release'
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
    Write-Host 'Native release built: release\Boltspark.exe' -ForegroundColor Green
}

if ($InstallDependencies) {
    Install-Dependencies
    return
}

if ($Run) {
    $runtime = Get-RequiredFile $hlExe 'Restore the HashLink 1.16.0 runtime into toolchain/hashlink.'
    $bytecode = Get-RequiredFile (Join-Path $repoRoot 'bin\boltspark.hl') `
        'Build output not found (bin\boltspark.hl). Run .\tools\build.ps1 first.'
    Push-Location $repoRoot
    try {
        & $runtime $bytecode
        if ($LASTEXITCODE -ne 0) { throw "Boltspark exited with code $LASTEXITCODE." }
    }
    finally {
        Pop-Location
    }
    return
}

Push-Location $repoRoot
try {
    Test-Environment
    if ($Check) { return }

    New-Item -ItemType Directory -Force (Join-Path $repoRoot 'bin') | Out-Null
    & $haxeExe (Join-Path $repoRoot 'compile.hxml')
    if ($LASTEXITCODE -ne 0) { throw "Haxe compilation failed with exit code $LASTEXITCODE." }
    if (-not (Test-Path (Join-Path $repoRoot 'bin\boltspark.hl'))) {
        throw 'Expected output bin\boltspark.hl was not created.'
    }
    Write-Host 'Development build succeeded: bin\boltspark.hl' -ForegroundColor Green
    New-NativeRelease
    Write-Host 'Release executable: release\Boltspark.exe' -ForegroundColor Green
    Write-Host 'Launch the development build with .\tools\build.ps1 -Run.' -ForegroundColor Green
}
finally {
    Pop-Location
}

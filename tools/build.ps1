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
$haxeRuntimeHashes = [ordered]@{
    'libmbedcrypto.dll' = 'C66623ED439BC779C09BECF76278EB6615C05D42374AA75CB0592B86D4C9AD62'
    'libmbedtls.dll' = '6E329DB9D8B65B859D89D295D37A2ECCB93EE09E4A3AE17B203EBB14F1DEF18B'
    'libmbedx509.dll' = '1248D18B14471D606AA11A97039252CFDADB8D1712CA18D49A36A76317F683C3'
    'libpcre2-8-0.dll' = 'A794A85AEBE6784AB3491F7EFF353CCE7AF2CB799619E635B49E0C55276A0911'
    'zlib1.dll' = 'A9ADF9FEFE5CA7F283A3BF0488C99AB845B74310C32C6F64025F324676743660'
}
$pixVersion = '1.0.240308001'
$pixPackageHash = '726ACC93D6968E2146261A1E415521747D50AD69894C2B42B5D0D4C29FD66EC4'
$pixRuntimeHash = '81ADCFD8253C3489BE720DA7E30F16004DC9A1F02A8B418C6C3AEF4993032E6D'
$hlFreeTypeVersion = '1.0.0'
$hlFreeTypeCommit = '56c8aac44b1874f0e50c61d970fe8c171c3c5e70'
$freeTypeVersion = '2.14.3'
$freeTypeCommit = '0a0221a1347e2f1e07c395263540026e9a0aa7c7'
$freeTypePackageHash = 'A4C2B6F10C8C78013B410B1ED861485B1BE413F424BF9A6F92AABA844E13C934'
$freeTypeHeaderHash = 'FD45E7EE01C8F0F2419186D3FC9DD58E25CD866EF0C49F0B347C2D141665A364'
$hlFreeTypeRoot = Join-Path $repoRoot 'third_party\hlfreetype'
$freeTypeSource = Join-Path $hlFreeTypeRoot 'vendor\freetype'
$winFloatSource = Join-Path $repoRoot 'tools\native\winfloat.c'
$winFloatModule = Join-Path $repoRoot 'bin\winfloat.hdll'
$winFloatImportLibrary = Join-Path $repoRoot 'bin\winfloat.lib'
$multiFileSource = Join-Path $repoRoot 'tools\native\multifile.c'
$multiFileModule = Join-Path $repoRoot 'bin\multifile.hdll'
$multiFileImportLibrary = Join-Path $repoRoot 'bin\multifile.lib'

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

function Test-FreeTypeSource {
    $marker = Join-Path $freeTypeSource '.boltspark-version'
    $header = Join-Path $freeTypeSource 'include\freetype\freetype.h'
    if (-not (Test-Path $marker) -or -not (Test-Path $header)) {
        throw "FreeType $freeTypeVersion source is missing. Run .\tools\build.ps1 -InstallDependencies."
    }
    if ((Get-Content $marker -Raw).Trim() -ne $freeTypeCommit) {
        throw "Unexpected FreeType source version under $freeTypeSource. Run .\tools\build.ps1 -InstallDependencies."
    }
    if ((Get-FileHash $header -Algorithm SHA256).Hash -ne $freeTypeHeaderHash) {
        throw "FreeType source verification failed under $freeTypeSource. Run .\tools\build.ps1 -InstallDependencies."
    }
}

function Install-FreeTypeSource {
    try {
        Test-FreeTypeSource
        Write-Host "FreeType $freeTypeVersion source is already installed." -ForegroundColor DarkGray
        return
    }
    catch {
        if (Test-Path $freeTypeSource) {
            Remove-Item -LiteralPath $freeTypeSource -Recurse -Force
        }
    }

    $downloadRoot = Join-Path $repoRoot 'bin\dependency-downloads\freetype'
    $archive = Join-Path $downloadRoot "freetype-$freeTypeVersion.zip"
    $extractRoot = Join-Path $downloadRoot 'extract'
    try {
        New-Item -ItemType Directory -Force $downloadRoot | Out-Null
        Invoke-WebRequest `
            -Uri "https://codeload.github.com/freetype/freetype/zip/$freeTypeCommit" `
            -OutFile $archive
        if ((Get-FileHash $archive -Algorithm SHA256).Hash -ne $freeTypePackageHash) {
            throw "Downloaded FreeType $freeTypeVersion source failed SHA256 verification."
        }
        Expand-Archive -LiteralPath $archive -DestinationPath $extractRoot
        $source = Get-ChildItem $extractRoot -Directory | Select-Object -First 1
        if ($null -eq $source) {
            throw "FreeType $freeTypeVersion archive did not contain a source directory."
        }
        New-Item -ItemType Directory -Force (Split-Path -Parent $freeTypeSource) | Out-Null
        Move-Item -LiteralPath $source.FullName -Destination $freeTypeSource
        [System.IO.File]::WriteAllText(
            (Join-Path $freeTypeSource '.boltspark-version'),
            $freeTypeCommit,
            (New-Object System.Text.UTF8Encoding($false)))
        Test-FreeTypeSource
    }
    finally {
        if (Test-Path $downloadRoot) {
            Remove-Item -LiteralPath $downloadRoot -Recurse -Force
        }
    }
    Write-Host "Installed pinned FreeType $freeTypeVersion source project-locally." -ForegroundColor Green
}

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

    Install-FreeTypeSource
    Build-FreeTypeModule

    Write-Host "Dependencies ready: Heaps 2.1.0, format, hldx 1.16.0, HashLink/C 1.16.0, PIX $pixVersion, hlfreetype $hlFreeTypeVersion, FreeType $freeTypeVersion." -ForegroundColor Green
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

function Get-CMakeExecutable($VisualStudio) {
    $cmakeExe = Join-Path $VisualStudio.InstallationPath `
        'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    if (Test-Path $cmakeExe) { return $cmakeExe }

    $cmakeCommand = Get-Command cmake -ErrorAction SilentlyContinue
    if ($null -ne $cmakeCommand) { return $cmakeCommand.Source }
    throw 'CMake is required. Install the C++ CMake tools for Visual Studio.'
}

function Build-FreeTypeModule {
    Test-FreeTypeSource
    $visualStudio = Get-VisualStudioConfiguration
    $cmakeExe = Get-CMakeExecutable $visualStudio
    $buildRoot = Join-Path $repoRoot 'bin\freetype-native'
    $env:HASHLINK = $hashLinkDir
    $cmakeArgs = @(
        '-S', $hlFreeTypeRoot,
        '-B', $buildRoot,
        '-G', $visualStudio.CMakeGenerator,
        '-A', 'x64',
        "-DFETCHCONTENT_SOURCE_DIR_FREETYPE=$freeTypeSource"
    )
    & $cmakeExe @cmakeArgs
    if ($LASTEXITCODE -ne 0) {
        throw 'CMake configuration for the FreeType HashLink module failed.'
    }
    & $cmakeExe --build $buildRoot --config Release --target extension
    if ($LASTEXITCODE -ne 0) {
        throw 'Building the FreeType HashLink module failed.'
    }

    $module = Join-Path $buildRoot 'extension\Release\freetype.hdll'
    $importLibrary = Join-Path $buildRoot 'extension\Release\freetype.lib'
    if (-not (Test-Path $module) -or -not (Test-Path $importLibrary)) {
        throw "FreeType build completed without the expected freetype.hdll/freetype.lib outputs."
    }
    $binDir = Join-Path $repoRoot 'bin'
    New-Item -ItemType Directory -Force $binDir | Out-Null
    Copy-Item -LiteralPath $module -Destination (Join-Path $binDir 'freetype.hdll') -Force
    Copy-Item -LiteralPath $importLibrary -Destination (Join-Path $binDir 'freetype.lib') -Force
    Write-Host "Native FreeType glyph module built (hlfreetype $hlFreeTypeVersion, FreeType $freeTypeVersion)." -ForegroundColor Green
}

function Build-WinFloatModule {
    # Raw-Win32 floating dock panels: own HWND/WndProc, GDI paint, no swapchain.
    # Built with the same pinned MSVC toolset as the other native modules.
    $visualStudio = Get-VisualStudioConfiguration
    $vcvars = Join-Path $visualStudio.InstallationPath 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not (Test-Path $vcvars)) {
        throw "vcvars64.bat was not found at $vcvars. Install the Desktop C++ workload."
    }
    $cl = Get-ChildItem -LiteralPath (Join-Path $visualStudio.InstallationPath 'VC\Tools\MSVC') `
        -Recurse -Filter cl.exe |
        Where-Object { $_.FullName -match 'Hostx64\\x64\\cl\.exe$' } |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $cl) { throw 'x64 cl.exe not found for the floating-panel module.' }
    Get-RequiredFile $winFloatSource `
        'The native floating-panel source tools\native\winfloat.c is required.' | Out-Null

    $command = "`"$vcvars`" >nul && `"$cl`" /nologo /LD /MD /O2 " +
        "/I `"$hashLinkDir\include`" `"$winFloatSource`" /Fe:`"$winFloatModule`" " +
        "/link /LIBPATH:`"$hashLinkDir`" libhl.lib user32.lib gdi32.lib dwmapi.lib shell32.lib"
    Push-Location (Join-Path $repoRoot 'bin')
    try {
        & cmd.exe /c $command | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $winFloatModule) `
                -or -not (Test-Path $winFloatImportLibrary)) {
            throw 'Building the native floating-panel module failed.'
        }
    }
    finally { Pop-Location }
    Write-Host 'Native floating-panel module built (bin\winfloat.hdll).' -ForegroundColor Green
}

function Build-MultiFileModule {
    # Multi-select common item dialog for importing texture sets in one command.
    $visualStudio = Get-VisualStudioConfiguration
    $vcvars = Join-Path $visualStudio.InstallationPath 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not (Test-Path $vcvars)) {
        throw "vcvars64.bat was not found at $vcvars. Install the Desktop C++ workload."
    }
    $cl = Get-ChildItem -LiteralPath (Join-Path $visualStudio.InstallationPath 'VC\Tools\MSVC') `
        -Recurse -Filter cl.exe |
        Where-Object { $_.FullName -match 'Hostx64\\x64\\cl\.exe$' } |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $cl) { throw 'x64 cl.exe not found for the multi-file module.' }
    Get-RequiredFile $multiFileSource `
        'The native multi-file picker source tools\native\multifile.c is required.' | Out-Null

    $command = "`"$vcvars`" >nul && `"$cl`" /nologo /LD /MD /O2 " +
        "/I `"$hashLinkDir\include`" `"$multiFileSource`" /Fe:`"$multiFileModule`" " +
        "/link /LIBPATH:`"$hashLinkDir`" libhl.lib ole32.lib uuid.lib shell32.lib"
    Push-Location (Join-Path $repoRoot 'bin')
    try {
        & cmd.exe /c $command | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $multiFileModule) `
                -or -not (Test-Path $multiFileImportLibrary)) {
            throw 'Building the native multi-file picker module failed.'
        }
    }
    finally { Pop-Location }
    Write-Host 'Native multi-file picker module built (bin\multifile.hdll).' -ForegroundColor Green
}

function Install-TemporaryImportLibrary([string]$Source, [string]$Target,
        [string]$Backup, [bool]$HadOriginal) {
    if ($HadOriginal) {
        Copy-Item -LiteralPath $Target -Destination $Backup -Force
    }
    Copy-Item -LiteralPath $Source -Destination $Target -Force
}

function Restore-TemporaryImportLibrary([string]$Target, [string]$Backup,
        [bool]$HadOriginal) {
    if ($HadOriginal) {
        Copy-Item -LiteralPath $Backup -Destination $Target -Force
    } elseif (Test-Path $Target) {
        Remove-Item -LiteralPath $Target -Force
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

function Add-NativeApplicationIcon([string]$ProjectPath, [string]$BuildRoot, [string]$IconPath) {
    $projectIcon = Join-Path $BuildRoot 'Boltspark.ico'
    $resourceFile = Join-Path $BuildRoot 'Boltspark.rc'
    Copy-Item -LiteralPath $IconPath -Destination $projectIcon -Force

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $resourceText = @'
#define IDI_BOLTSPARK_ICON 101
IDI_BOLTSPARK_ICON ICON "Boltspark.ico"
'@
    [System.IO.File]::WriteAllText($resourceFile, $resourceText, $utf8NoBom)

    $projectText = [System.IO.File]::ReadAllText($ProjectPath)
    if ($projectText -notmatch '<ResourceCompile Include="Boltspark\.rc"') {
        $closingProject = $projectText.LastIndexOf('</Project>')
        if ($closingProject -lt 0) {
            throw "Generated native project is missing its closing Project element: $ProjectPath"
        }
        $resourceItem = @'
  <ItemGroup>
    <ResourceCompile Include="Boltspark.rc" />
  </ItemGroup>
'@
        $projectText = $projectText.Insert($closingProject, $resourceItem)
        [System.IO.File]::WriteAllText($ProjectPath, $projectText, $utf8NoBom)
    }
}

function Set-NativeReleaseGuiSubsystem([string]$ProjectPath) {
    $projectText = [System.IO.File]::ReadAllText($ProjectPath)
    $releaseGroupPattern = '(?s)<ItemDefinitionGroup(?=[^>]*Condition="[^"]*Release\|[^"]*")[^>]*>.*?</ItemDefinitionGroup>'
    $releaseGroups = [regex]::Matches($projectText, $releaseGroupPattern)
    if ($releaseGroups.Count -eq 0) {
        throw "Generated native project has no Release item definition groups: $ProjectPath"
    }

    foreach ($releaseGroup in @($releaseGroups)) {
        $updatedGroup = $releaseGroup.Value
        if (-not $updatedGroup.Contains('<SubSystem>Console</SubSystem>')) {
            throw "Generated native Release configuration is not console-based: $ProjectPath"
        }
        if (-not $updatedGroup.Contains('_CONSOLE;')) {
            throw "Generated native Release configuration is missing the _CONSOLE definition: $ProjectPath"
        }

        # HashLink's generated hlc_main.c supplies wWinMain when _CONSOLE is
        # absent. Keep Debug console-based, but package Release as a GUI app so
        # starting Boltspark.exe does not create a command window.
        $updatedGroup = $updatedGroup.Replace(
            '<SubSystem>Console</SubSystem>',
            '<SubSystem>Windows</SubSystem>')
        $updatedGroup = $updatedGroup.Replace('_CONSOLE;', '')
        $projectText = $projectText.Replace($releaseGroup.Value, $updatedGroup)
    }

    [System.IO.File]::WriteAllText(
        $ProjectPath,
        $projectText,
        (New-Object System.Text.UTF8Encoding($false)))
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
    foreach ($runtimeName in $haxeRuntimeHashes.Keys) {
        $runtimePath = Get-RequiredFile (Join-Path $haxeDevDir $runtimeName) `
            "Restore the pinned Haxe compiler runtime $runtimeName."
        $runtimeHash = (Get-FileHash $runtimePath -Algorithm SHA256).Hash
        if ($runtimeHash -ne $haxeRuntimeHashes[$runtimeName]) {
            throw "Unexpected pinned Haxe compiler runtime hash for ${runtimeName}: $runtimeHash"
        }
    }
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
    Get-RequiredFile (Join-Path $hlFreeTypeRoot 'freetype\heaps\DynamicFreeTypeFont.hx') `
        "Restore pinned hlfreetype $hlFreeTypeVersion source at commit $hlFreeTypeCommit." | Out-Null
    Get-RequiredFile (Join-Path $hlFreeTypeRoot 'extension\freetype.c') `
        "Restore pinned hlfreetype $hlFreeTypeVersion native source." | Out-Null
    Get-RequiredFile $winFloatSource `
        'The native floating-panel source tools\native\winfloat.c is required.' | Out-Null
    Get-RequiredFile $multiFileSource `
        'The native multi-file picker source tools\native\multifile.c is required.' | Out-Null
    Test-FreeTypeSource
    $monoFontSource = Get-RequiredFile `
        (Join-Path $repoRoot 'tools\font-source\JetBrainsMono.ttf') `
        'The pinned JetBrains Mono source font is required.'
    $monoFontResource = Get-RequiredFile `
        (Join-Path $repoRoot 'src\res\fonts\jetbrains_mono.ttf') `
        'Run .\tools\assets\generate-fonts.ps1 to restore the embedded JetBrains Mono resource.'
    $monoFontSourceHash = (Get-FileHash $monoFontSource -Algorithm SHA256).Hash
    $monoFontResourceHash = (Get-FileHash $monoFontResource -Algorithm SHA256).Hash
    if ($monoFontSourceHash -ne $monoFontResourceHash) {
        throw 'Embedded JetBrains Mono does not match tools\font-source\JetBrainsMono.ttf. Run .\tools\assets\generate-fonts.ps1.'
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
    if ($buildConfig -notmatch '(?m)^\s*-cp\s+third_party/hlfreetype\s*$') {
        throw 'compile.hxml must include the pinned project-local hlfreetype source.'
    }
    if ($buildConfig -notmatch 'freetype\.heaps\.Macro\.main\(\)') {
        throw 'compile.hxml must register the hlfreetype Heaps resource integration.'
    }
    if ($buildConfig -match 'hlsdl|sdl|opengl') {
        throw 'compile.hxml must not select SDL/OpenGL for the Windows DirectX 12 target.'
    }

    $visualStudio = Get-VisualStudioConfiguration
    Write-Host "Visual Studio: $($visualStudio.Version) | MSBuild: $($visualStudio.MSBuild)"

    Write-Host 'Environment check passed.' -ForegroundColor Green
    Write-Host "Toolchain: Haxe $haxeVersion | HashLink $hlVersion | Heaps 2.1.0 | hldx 1.16.0 | HashLink/C 1.16.0 | hlfreetype $hlFreeTypeVersion | FreeType $freeTypeVersion" -ForegroundColor Green
}

function New-ThirdPartyLicenseBundle([string]$Destination) {
    $sections = @(
        [ordered]@{
            Component = 'HashLink'
            Version = '1.16.0 (runtime, hldx bindings, HashLink/C support library)'
            Source = 'https://github.com/HaxeFoundation/hashlink'
            License = 'MIT License'
            Use = 'HashLink VM, DirectX 12 native modules, and Haxe bindings used by the engine.'
            Path = (Join-Path $repoRoot 'third_party\licenses\HashLink-LICENSE.txt')
        },
        [ordered]@{
            Component = 'Heaps'
            Version = '2.1.0'
            Source = 'https://github.com/HeapsIO/heaps'
            License = 'MIT License'
            Use = 'Graphics framework and H2D editor UI.'
            Path = (Join-Path $repoRoot 'third_party\licenses\Heaps-LICENSE.txt')
        },
        [ordered]@{
            Component = 'format'
            Version = '3.8.0'
            Source = 'https://github.com/HaxeFoundation/format'
            License = 'BSD 2-Clause License'
            Use = 'File-format support used by asset import and serialization.'
            Path = (Join-Path $repoRoot 'third_party\licenses\Format-LICENSE.txt')
        },
        [ordered]@{
            Component = 'Tabler Icons'
            Version = '3.52.0'
            Source = 'https://github.com/tabler/tabler-icons/tree/v3.52.0'
            License = 'MIT License'
            Use = 'Selected icons embedded in the BoltUI exact-size atlas.'
            Path = (Join-Path $repoRoot 'third_party\tabler-icons\LICENSE')
        },
        [ordered]@{
            Component = 'Inter'
            Version = '4.1'
            Source = 'https://github.com/rsms/inter'
            License = 'SIL Open Font License 1.1'
            Use = 'Regular, SemiBold, and Bold font faces embedded in BoltUI.'
            Path = (Join-Path $repoRoot 'tools\font-source\Inter-LICENSE.txt')
        },
        [ordered]@{
            Component = 'JetBrains Mono'
            Version = $null
            Source = 'https://github.com/JetBrains/JetBrainsMono'
            License = 'SIL Open Font License 1.1'
            Use = 'Regular font face embedded for console and numeric text.'
            Path = (Join-Path $repoRoot 'tools\font-source\JetBrainsMono-LICENSE.txt')
        },
        [ordered]@{
            Component = 'hlfreetype'
            Version = "$hlFreeTypeVersion ($hlFreeTypeCommit)"
            Source = 'https://github.com/dtwotwo/hlfreetype'
            License = 'MIT License'
            Use = 'HashLink/Heaps runtime font integration.'
            Path = (Join-Path $hlFreeTypeRoot 'LICENSE')
        },
        [ordered]@{
            Component = 'FreeType'
            Version = $freeTypeVersion
            Source = 'https://github.com/freetype/freetype'
            License = 'FreeType License'
            Use = 'Font rasterizer statically linked into freetype.hdll.'
            Path = (Join-Path $hlFreeTypeRoot 'FreeType-LICENSE.txt')
        },
        [ordered]@{
            Component = 'WinPixEventRuntime'
            Version = $pixVersion
            Source = "https://www.nuget.org/packages/WinPixEventRuntime/$pixVersion"
            License = 'MIT License'
            Use = 'PIX event runtime distributed as WinPixEventRuntime.dll.'
            Path = (Join-Path $hashLinkDir 'WinPixEventRuntime.LICENSE.txt')
        }
    )

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine('BOLTSPARK ENGINE - THIRD-PARTY SOFTWARE NOTICES AND LICENSES')
    [void]$builder.AppendLine('==========================================================')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('This file covers third-party software distributed with or embedded in')
    [void]$builder.AppendLine('Boltspark Engine. Canonical upstream license files remain separate and')
    [void]$builder.AppendLine('unaltered in the source repository; this release copy consolidates them')
    [void]$builder.AppendLine('for convenient binary distribution.')
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('Required FreeType acknowledgement:')
    [void]$builder.AppendLine('This software is based in part on the work of the FreeType Team.')
    [void]$builder.AppendLine()

    $index = 1
    foreach ($section in $sections) {
        $licensePath = Get-RequiredFile $section.Path `
            "Restore the canonical $($section.Component) license file."
        $licenseText = [System.IO.File]::ReadAllText($licensePath)
        if ([string]::IsNullOrWhiteSpace($licenseText)) {
            throw "Canonical $($section.Component) license file is empty: $licensePath"
        }

        [void]$builder.AppendLine('----------------------------------------------------------')
        [void]$builder.AppendLine("$index. $($section.Component)")
        [void]$builder.AppendLine('----------------------------------------------------------')
        [void]$builder.AppendLine("Component: $($section.Component)")
        if ($null -ne $section.Version) {
            [void]$builder.AppendLine("Version: $($section.Version)")
        }
        [void]$builder.AppendLine("Source: $($section.Source)")
        [void]$builder.AppendLine("License: $($section.License)")
        [void]$builder.AppendLine("Distributed use: $($section.Use)")
        [void]$builder.AppendLine()
        [void]$builder.AppendLine('Full license text:')
        [void]$builder.AppendLine()
        [void]$builder.Append($licenseText.TrimEnd())
        [void]$builder.AppendLine()
        [void]$builder.AppendLine()
        $index++
    }

    $destinationDirectory = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force $destinationDirectory | Out-Null
    [System.IO.File]::WriteAllText($Destination, $builder.ToString(),
        (New-Object System.Text.UTF8Encoding($false)))
}

function New-NativeRelease {
    $visualStudio = Get-VisualStudioConfiguration
    $vsPath = $visualStudio.InstallationPath
    $vsTemplate = $visualStudio.Template
    $platformToolset = $visualStudio.PlatformToolset
    $cmakeGenerator = $visualStudio.CMakeGenerator
    $msbuild = $visualStudio.MSBuild
    $env:VSWHERE = $visualStudio.VSWhere
    $freeTypeModule = Get-RequiredFile (Join-Path $repoRoot 'bin\freetype.hdll') `
        'Build the native FreeType module before creating a release.'
    $freeTypeImportLibrary = Get-RequiredFile (Join-Path $repoRoot 'bin\freetype.lib') `
        'Build the native FreeType import library before creating a release.'
    $appIcon = Get-RequiredFile (Join-Path $repoRoot 'src\res\boltspark.ico') `
        'The Boltspark application icon is required for native release branding.'

    $hashLinkSource = Join-Path $env:HAXELIB_PATH 'hashlink\git'
    if (-not (Test-Path (Join-Path $hashLinkSource 'libs\directx\window.c'))) {
        throw "HashLink native source was not found at $hashLinkSource. Run .\tools\build.ps1 -InstallDependencies."
    }

    $resizePatch = Join-Path $repoRoot 'tools\patches\hashlink-directx-live-resize.patch'
    Apply-HashLinkPatch $hashLinkSource $resizePatch 'Interactive resize and native window behavior'
    $vswherePatch = Join-Path $repoRoot 'tools\patches\hashlink-vswhere-path.patch'
    Apply-HashLinkPatch $hashLinkSource $vswherePatch 'Visual Studio locator path'
    if ($vsTemplate -eq 'vs2026') {
        $vs2026ToolsetPatch = Join-Path $repoRoot 'tools\patches\hashlink-vs2026-v145.patch'
        Apply-HashLinkPatch $hashLinkSource $vs2026ToolsetPatch 'Visual Studio 2026 v145 toolset'
    }

    $cmakeExe = Get-CMakeExecutable $visualStudio

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
    $hashLinkFreeTypeImportLibrary = Join-Path $hashLinkDir 'freetype.lib'
    $freeTypeImportLibraryBackup = Join-Path $nativeModuleBuild 'freetype-original.lib'
    $hadFreeTypeImportLibrary = Test-Path $hashLinkFreeTypeImportLibrary
    $winFloatImportLibraryTarget = Join-Path $hashLinkDir 'winfloat.lib'
    $winFloatImportLibraryBackup = Join-Path $nativeModuleBuild 'winfloat-original.lib'
    $hadWinFloatImportLibrary = Test-Path $winFloatImportLibraryTarget
    $multiFileImportLibraryTarget = Join-Path $hashLinkDir 'multifile.lib'
    $multiFileImportLibraryBackup = Join-Path $nativeModuleBuild 'multifile-original.lib'
    $hadMultiFileImportLibrary = Test-Path $multiFileImportLibraryTarget
    if ($hadFreeTypeImportLibrary) {
        Copy-Item -LiteralPath $hashLinkFreeTypeImportLibrary `
            -Destination $freeTypeImportLibraryBackup -Force
    }
    Copy-Item -LiteralPath $directXImportLibrary -Destination $directXImportLibraryBackup -Force
    Copy-Item -LiteralPath $patchedDirectXModule -Destination (Join-Path $hashLinkDir 'directx.hdll') -Force
    Write-Host 'Patched DirectX module built for interactive resizing and auxiliary-window activation.' -ForegroundColor Green

    $buildRoot = Join-Path $repoRoot 'bin\native-release'
    $nativeSource = Join-Path $buildRoot 'Boltspark.c'
    $nativeSolution = Join-Path $buildRoot 'Boltspark.sln'
    $nativeProject = Join-Path $buildRoot 'Boltspark.vcxproj'
    $nativeConfigPath = Join-Path $buildRoot 'hlc.json'
    New-Item -ItemType Directory -Force $buildRoot | Out-Null

    $compileArgs = @(
        '-cp', 'src',
        '-cp', 'third_party/hlfreetype',
        '-lib', 'heaps',
        '-lib', 'format',
        '-lib', 'hldx',
        '-lib', 'hashlink',
        '-D', 'dx12',
        '-D', 'hl_ver=1.16.0',
        '-D', 'windowSize=1440x900',
        '-D', "hlgen.makefile=$vsTemplate",
        '--macro', 'freetype.heaps.Macro.main()',
        '-hl', $nativeSource,
        '-main', 'Main'
    )

    Copy-Item -LiteralPath $patchedDirectXImportLibrary -Destination $directXImportLibrary -Force
    Copy-Item -LiteralPath $freeTypeImportLibrary -Destination $hashLinkFreeTypeImportLibrary -Force
    Get-RequiredFile $winFloatImportLibrary `
        'Build the native floating-panel module before creating a release.' | Out-Null
    Get-RequiredFile $multiFileImportLibrary `
        'Build the native multi-file picker module before creating a release.' | Out-Null
    Install-TemporaryImportLibrary $winFloatImportLibrary $winFloatImportLibraryTarget `
        $winFloatImportLibraryBackup $hadWinFloatImportLibrary
    Install-TemporaryImportLibrary $multiFileImportLibrary $multiFileImportLibraryTarget `
        $multiFileImportLibraryBackup $hadMultiFileImportLibrary
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
        Restore-TemporaryImportLibrary $winFloatImportLibraryTarget `
            $winFloatImportLibraryBackup $hadWinFloatImportLibrary
        Restore-TemporaryImportLibrary $multiFileImportLibraryTarget `
            $multiFileImportLibraryBackup $hadMultiFileImportLibrary
        Copy-Item -LiteralPath $directXImportLibraryBackup -Destination $directXImportLibrary -Force
        if ($hadFreeTypeImportLibrary) {
            Copy-Item -LiteralPath $freeTypeImportLibraryBackup `
                -Destination $hashLinkFreeTypeImportLibrary -Force
        } elseif (Test-Path $hashLinkFreeTypeImportLibrary) {
            Remove-Item -LiteralPath $hashLinkFreeTypeImportLibrary -Force
        }
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
    Set-NativeReleaseGuiSubsystem $nativeProject
    Add-NativeApplicationIcon $nativeProject $buildRoot $appIcon

    $nativeConfig = Get-Content $nativeConfigPath -Raw | ConvertFrom-Json
    $nativeModules = @(
        $nativeConfig.libs |
            Where-Object { $_ -ne 'std' } |
            Select-Object -Unique
    )
    if ($nativeModules.Count -eq 0) {
        throw 'Haxe produced no native runtime module list.'
    }

    Install-TemporaryImportLibrary $winFloatImportLibrary $winFloatImportLibraryTarget `
        $winFloatImportLibraryBackup $hadWinFloatImportLibrary
    Install-TemporaryImportLibrary $multiFileImportLibrary $multiFileImportLibraryTarget `
        $multiFileImportLibraryBackup $hadMultiFileImportLibrary
    try {
        Copy-Item -LiteralPath $patchedDirectXImportLibrary -Destination $directXImportLibrary -Force
        Copy-Item -LiteralPath $freeTypeImportLibrary -Destination $hashLinkFreeTypeImportLibrary -Force
        & $msbuild $nativeSolution '-t:Boltspark' '-nologo' '-verbosity:minimal' `
            '-property:Configuration=Release' '-property:Platform=x64' `
            "-property:PlatformToolset=$platformToolset"
        if ($LASTEXITCODE -ne 0) {
            throw "MSBuild failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Restore-TemporaryImportLibrary $winFloatImportLibraryTarget `
            $winFloatImportLibraryBackup $hadWinFloatImportLibrary
        Restore-TemporaryImportLibrary $multiFileImportLibraryTarget `
            $multiFileImportLibraryBackup $hadMultiFileImportLibrary
        Copy-Item -LiteralPath $directXImportLibraryBackup -Destination $directXImportLibrary -Force
        if ($hadFreeTypeImportLibrary) {
            Copy-Item -LiteralPath $freeTypeImportLibraryBackup `
                -Destination $hashLinkFreeTypeImportLibrary -Force
        } elseif (Test-Path $hashLinkFreeTypeImportLibrary) {
            Remove-Item -LiteralPath $hashLinkFreeTypeImportLibrary -Force
        }
    }

    $nativeExe = Join-Path $buildRoot 'x64\Release\Boltspark.exe'
    if (-not (Test-Path $nativeExe)) {
        throw "MSBuild succeeded but the expected executable was not created: $nativeExe"
    }

    $stagingDir = Join-Path $buildRoot 'package'
    if (Test-Path $stagingDir) {
        Remove-Item -LiteralPath $stagingDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force $stagingDir | Out-Null
    Copy-Item -LiteralPath $nativeExe -Destination (Join-Path $stagingDir 'Boltspark.exe') -Force

    $runtimeFiles = @(
        @{ Source = (Join-Path $hashLinkDir 'libhl.dll'); Name = 'libhl.dll' },
        @{ Source = (Join-Path $hashLinkDir 'dxcompiler.dll'); Name = 'dxcompiler.dll' },
        @{ Source = (Join-Path $hashLinkDir 'dxil.dll'); Name = 'dxil.dll' },
        @{ Source = (Join-Path $hashLinkDir 'vcruntime140.dll'); Name = 'vcruntime140.dll' },
        @{ Source = (Join-Path $nekoDir 'vcruntime140_1.dll'); Name = 'vcruntime140_1.dll' },
        @{ Source = (Join-Path $nekoDir 'msvcp140.dll'); Name = 'msvcp140.dll' },
        @{ Source = (Join-Path $hashLinkDir 'WinPixEventRuntime.dll'); Name = 'WinPixEventRuntime.dll' }
    )
    foreach ($runtimeFile in $runtimeFiles) {
        if (-not (Test-Path $runtimeFile.Source)) {
            throw "Required runtime file not found: $($runtimeFile.Source)"
        }
        Copy-Item -LiteralPath $runtimeFile.Source -Destination (Join-Path $stagingDir $runtimeFile.Name) -Force
    }
    New-ThirdPartyLicenseBundle (Join-Path $stagingDir 'THIRD-PARTY-LICENSES.txt')

    foreach ($module in $nativeModules) {
        $moduleFile = "$module.hdll"
        $modulePath = if ($module -eq 'freetype') {
            $freeTypeModule
        } elseif ($module -eq 'winfloat') {
            $winFloatModule
        } elseif ($module -eq 'multifile') {
            $multiFileModule
        } else {
            Join-Path $hashLinkDir $moduleFile
        }
        if (-not (Test-Path $modulePath)) {
            throw "Required HashLink module not found: $modulePath"
        }
        Copy-Item -LiteralPath $modulePath -Destination (Join-Path $stagingDir $moduleFile) -Force
    }

    $releaseDir = Join-Path $repoRoot 'release'
    New-Item -ItemType Directory -Force $releaseDir | Out-Null
    $legacyLicenseNames = @(
        'WinPixEventRuntime-LICENSE.txt',
        'THIRD-PARTY-NOTICES.md',
        'Inter-LICENSE.txt',
        'JetBrainsMono-LICENSE.txt',
        'Tabler-Icons-LICENSE.txt',
        'hlfreetype-LICENSE.txt',
        'FreeType-LICENSE.txt'
    )
    $replaceNames = @(
        'Boltspark.exe',
        'libhl.dll',
        'dxcompiler.dll',
        'dxil.dll',
        'vcruntime140.dll',
        'vcruntime140_1.dll',
        'msvcp140.dll',
        'WinPixEventRuntime.dll',
        'THIRD-PARTY-LICENSES.txt',
        'freetype.hdll',
        'winfloat.hdll',
        'multifile.hdll'
    )
    $replaceNames += $legacyLicenseNames
    $replaceNames += Get-ChildItem $hashLinkDir -Filter '*.hdll' -File | Select-Object -ExpandProperty Name
    foreach ($name in ($replaceNames | Select-Object -Unique)) {
        $oldFile = Join-Path $releaseDir $name
        if (Test-Path $oldFile) {
            Remove-Item -LiteralPath $oldFile -Force
        }
    }
    Copy-Item -Path (Join-Path $stagingDir '*') -Destination $releaseDir -Force
    foreach ($legacyLicenseName in $legacyLicenseNames) {
        if (Test-Path (Join-Path $releaseDir $legacyLicenseName)) {
            throw "Obsolete individual license remained in release: $legacyLicenseName"
        }
    }
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
    Get-RequiredFile (Join-Path $repoRoot 'bin\freetype.hdll') `
        'FreeType runtime module not found. Run .\tools\build.ps1 first.' | Out-Null
    Push-Location (Join-Path $repoRoot 'bin')
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
    Build-FreeTypeModule
    Build-WinFloatModule
    Build-MultiFileModule
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

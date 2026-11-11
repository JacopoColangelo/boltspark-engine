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
$hashLinkDir = Join-Path $toolchain 'hashlink'

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
$hashlinkLibraryVersion = (cmd /c "`"$haxelib`" path hashlink 2>nul") -join ''
if ($LASTEXITCODE -eq 0) {
    if ($hashlinkLibraryVersion -notmatch '-D hashlink=1\.16\.0') {
        throw "Expected HashLink haxelib 1.16.0, found '$hashlinkLibraryVersion'. Remove the incompatible local package before installing dependencies."
    }
} else {
    & $haxelib git hashlink https://github.com/HaxeFoundation/hashlink.git 1.16 other/haxelib/
    if ($LASTEXITCODE -ne 0) { throw 'Failed to install the HashLink 1.16.0 Haxe/C support library.' }
}

$pixVersion = '1.0.240308001'
$pixPackageUrl = "https://api.nuget.org/v3-flatcontainer/winpixeventruntime/$pixVersion/winpixeventruntime.$pixVersion.nupkg"
$pixPackageHash = '726ACC93D6968E2146261A1E415521747D50AD69894C2B42B5D0D4C29FD66EC4'
$pixRuntimeHash = '81ADCFD8253C3489BE720DA7E30F16004DC9A1F02A8B418C6C3AEF4993032E6D'
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
        Invoke-WebRequest -Uri $pixPackageUrl -OutFile $packageFile
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

Write-Host 'Haxe libraries installed.' -ForegroundColor Green
Write-Host 'Note: the HashLink 1.16.0 runtime (with directx.hdll and dx12.hdll) ships inside toolchain/hashlink.' -ForegroundColor Green
Write-Host "Pinned WinPixEventRuntime $pixVersion is installed beside the HashLink runtime." -ForegroundColor Green
Write-Host 'Run .\tools\check-windows.ps1, then .\tools\build-windows.ps1.' -ForegroundColor Green

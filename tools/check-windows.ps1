$ErrorActionPreference = 'Stop'

# Boltspark Windows 11 / DirectX 12 environment check.
#
# The toolchain is project-local: toolchain/haxe-dev (pinned dev build),
# toolchain/haxe (reference stable), toolchain/hashlink, toolchain/haxelib.
# This script verifies the exact set required to build and run the DX12
# foundation. It does NOT require the D3D12 Agility SDK: the official
# HashLink 1.16.0 binary build is a standard DX12 runtime (verified against
# the 1.16 CMake configuration and by runtime evidence); agility files are
# only needed for custom HashLink builds that enable them.

$repoRoot = Split-Path -Parent $PSScriptRoot
$toolchain = Join-Path $repoRoot 'toolchain'

function Require-File([string]$Path, [string]$Message) {
    if (-not (Test-Path $Path)) { throw "Missing file: $Path`n$Message" }
    return (Resolve-Path $Path).Path
}

function Get-PeVersion([string]$Path) {
    return (Get-Item $Path).VersionInfo.FileVersion
}

Write-Host 'Boltspark Windows 11 / DirectX 12 environment check' -ForegroundColor Cyan

# --- OS ---
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

# --- Project-local toolchain layout ---
$haxeDevDir = Join-Path $toolchain 'haxe-dev'
$haxeExe = Require-File (Join-Path $haxeDevDir 'haxe.exe') `
    'Run the toolchain bootstrap (or re-extract the pinned Haxe dev build 2025-10-23 dcda605 into toolchain/haxe-dev).'
$hashLinkDir = Join-Path $toolchain 'hashlink'
$hlExe = Require-File (Join-Path $hashLinkDir 'hl.exe') `
    'Extract the HashLink 1.16.0 official win64 build into toolchain/hashlink.'
$haxelibDir = Join-Path $toolchain 'haxelib'
$nekoDir = Join-Path $toolchain 'neko'
$haxeHaxelib = Join-Path $haxeDevDir 'haxelib.exe'

Write-Host "Haxe (pinned dev build): $haxeExe"
Write-Host "HashLink runtime: $hlExe"

# --- Resolve toolchain env for this session ---
$env:Path = "$haxeDevDir;$nekoDir;$hashLinkDir;$env:Path"
$env:HAXE_STD_PATH = Join-Path $haxeDevDir 'std'
$env:HAXELIB_PATH = $haxelibDir
$env:NEKOPATH = Join-Path $toolchain 'neko'

$haxeVersion = & $haxeExe --version
$hlVersion = (& $hlExe --version).Trim()
Write-Host "Haxe version: $haxeVersion"
Write-Host "HashLink version: $hlVersion"

if ($hlVersion -ne '1.16.0') {
    throw "HashLink 1.16.0 is pinned for M0. Found '$hlVersion' at $hlExe."
}

# --- Haxelib packages (project-local repository) ---
foreach ($library in @('heaps', 'format', 'hldx')) {
    # cmd /c keeps haxelib's stderr warnings from becoming PowerShell errors.
    cmd /c "`"$haxeHaxelib`" path $library 2>nul" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Haxelib package '$library' is missing from $haxelibDir. Run tools\install-dependencies.ps1."
    }
    Write-Host "Haxelib package OK: $library"
}
$hldxVersion = (cmd /c "`"$haxeHaxelib`" list hldx 2>nul") -join ''
if ($hldxVersion -notmatch '1\.16\.0') {
    throw "hldx 1.16.0 is pinned for M0 (bindings must match the HashLink runtime). Found: $hldxVersion"
}

# --- HashLink native modules ---
$dx12Module = Require-File (Join-Path $hashLinkDir 'dx12.hdll') `
    'The HashLink runtime must include dx12.hdll (Direct3D 12 driver).'
$directxModule = Require-File (Join-Path $hashLinkDir 'directx.hdll') `
    'The HashLink runtime must include directx.hdll (window/input services).'
$libhl = Require-File (Join-Path $hashLinkDir 'libhl.dll') `
    'The HashLink runtime must include libhl.dll (VM core).'
# dxcompiler/dxil ship beside dx12.hdll in the official 1.16.0 build and are
# loaded by it for shader compilation; verify presence as part of the set.
$dxCompiler = Require-File (Join-Path $hashLinkDir 'dxcompiler.dll') `
    'The official HashLink 1.16.0 build ships dxcompiler.dll beside dx12.hdll.'
$dxil = Require-File (Join-Path $hashLinkDir 'dxil.dll') `
    'The official HashLink 1.16.0 build ships dxil.dll beside dx12.hdll.'

foreach ($module in @($dx12Module, $directxModule, $libhl, $dxCompiler, $dxil)) {
    $hash = (Get-FileHash $module -Algorithm SHA256).Hash
    Write-Host "Native module OK: $(Split-Path -Leaf $module)  sha256=$hash"
}

# --- Build configuration ---
$buildConfig = Get-Content (Join-Path $repoRoot 'compile.hxml') -Raw
if ($buildConfig -notmatch '(?m)^\s*-lib\s+hldx\s*$') {
    throw 'compile.hxml must select -lib hldx for the Windows DirectX target.'
}
if ($buildConfig -notmatch '(?m)^\s*-D\s+dx12\s*$') {
    throw 'compile.hxml must contain -D dx12. This project targets DirectX 12, not the default DirectX 11 configuration.'
}
if ($buildConfig -notmatch '(?m)^\s*-D\s+hl_ver=1\.16\.0\s*$') {
    throw 'compile.hxml must define -D hl_ver=1.16.0 (required by the Heaps DX12 driver for hl.CArray).'
}
if ($buildConfig -match 'hlsdl|sdl|opengl') {
    throw 'compile.hxml must not select SDL/OpenGL for the Windows-first DirectX 12 target.'
}

Write-Host ''
Write-Host 'Environment check passed. Build with .\tools\build-windows.ps1' -ForegroundColor Green
Write-Host "Toolchain: haxe-dev $haxeVersion | HashLink $hlVersion | hldx 1.16.0 | heaps 2.1.0" -ForegroundColor Green

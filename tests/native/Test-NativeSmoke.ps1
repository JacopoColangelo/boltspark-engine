param(
    [switch]$DevelopmentOnly,
    [switch]$ReleaseOnly,
    [int]$TimeoutSeconds = 15
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$outputDir = Join-Path $repoRoot 'bin\test-results\native-smoke'
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$release = Join-Path $repoRoot 'release\Boltspark.exe'

New-Item -ItemType Directory -Force $outputDir | Out-Null

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BoltsparkNativeSmokeApi {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
"@

function Wait-ForEditorWindow([Diagnostics.Process]$process) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 125
        $process.Refresh()
        if ($process.HasExited) {
            throw "Boltspark exited before opening a window (code $($process.ExitCode))."
        }
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
            return $process.MainWindowHandle
        }
    }
    throw "Boltspark did not create its native window within $TimeoutSeconds seconds."
}

function Close-Editor([Diagnostics.Process]$process, [IntPtr]$window) {
    [void][BoltsparkNativeSmokeApi]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Boltspark did not close after WM_CLOSE.'
    }
    $process.Refresh()
    if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) {
        throw "Boltspark exited with code $($process.ExitCode)."
    }
}

function Assert-WindowIcons([IntPtr]$window) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        $small = [BoltsparkNativeSmokeApi]::SendMessage(
            $window, 0x007F, [IntPtr]::new(0), [IntPtr]::Zero)
        $large = [BoltsparkNativeSmokeApi]::SendMessage(
            $window, 0x007F, [IntPtr]::new(1), [IntPtr]::Zero)
        if ($small -ne [IntPtr]::Zero -and $large -ne [IntPtr]::Zero) { return }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($small -eq [IntPtr]::Zero -or $large -eq [IntPtr]::Zero) {
        throw 'The native window did not expose both small and large icons before timeout.'
    }
}

if (-not $ReleaseOnly) {
    if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
        throw 'Development runtime/build missing. Run tools\build.ps1 first.'
    }
    $stdout = Join-Path $outputDir 'development.stdout.log'
    $stderr = Join-Path $outputDir 'development.stderr.log'
    $process = Start-Process $runtime -ArgumentList 'boltspark.hl' `
        -WorkingDirectory (Join-Path $repoRoot 'bin') `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -NoNewWindow -PassThru
    try {
        $window = Wait-ForEditorWindow $process
        Assert-WindowIcons $window
        Close-Editor $process $window
        $driver = Select-String -Path $stdout `
            -Pattern '^\[M0\] renderer driver = h3d\.impl\.DX12Driver$'
        if ($null -eq $driver) {
            throw 'Development smoke did not positively identify the DX12 driver.'
        }
        if ((Get-Item $stderr).Length -ne 0) {
            throw "Development smoke wrote stderr; inspect $stderr."
        }
        Write-Host '[native-smoke] Development DX12 launch/close passed.' -ForegroundColor Green
    }
    finally {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    }
}

if (-not $DevelopmentOnly) {
    if (-not (Test-Path $release)) {
        throw 'Native release missing. Run tools\build.ps1 first.'
    }
    $process = Start-Process $release `
        -WorkingDirectory (Split-Path -Parent $release) -PassThru
    try {
        $window = Wait-ForEditorWindow $process
        Assert-WindowIcons $window
        Close-Editor $process $window
        Write-Host '[native-smoke] Packaged release launch/close passed.' -ForegroundColor Green
    }
    finally {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    }
}

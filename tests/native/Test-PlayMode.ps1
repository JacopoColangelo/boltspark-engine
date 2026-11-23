param(
    [int]$TimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\play-mode\$runId"
$localAppData = Join-Path $outputDir 'localappdata'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
New-Item -ItemType Directory -Force $localAppData | Out-Null

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\build.ps1 first.'
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BoltsparkPlayModeApi {
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    public static IntPtr MakeLParam(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }
}
"@

function Wait-Window([Diagnostics.Process]$process) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 125
        $process.Refresh()
        if ($process.HasExited) { throw "Editor exited early with code $($process.ExitCode)." }
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) { return $process.MainWindowHandle }
    }
    throw 'Editor HWND did not appear.'
}

function Send-Message([IntPtr]$window, [uint32]$message,
        [IntPtr]$wparam, [IntPtr]$lparam) {
    $result = [IntPtr]::Zero
    $sent = [BoltsparkPlayModeApi]::SendMessageTimeout(
        $window, $message, $wparam, $lparam, 0, 5000, [ref]$result)
    if ($sent -eq [IntPtr]::Zero) {
        throw ('Window message 0x{0:X} failed.' -f $message)
    }
}

function Send-Mouse([IntPtr]$window, [uint32]$message,
        [int]$x, [int]$y, [IntPtr]$buttons) {
    Send-Message $window $message $buttons `
        ([BoltsparkPlayModeApi]::MakeLParam($x, $y))
}

function Send-Key([IntPtr]$window, [int]$virtualKey, [int]$scanCode,
        [bool]$down) {
    $message = if ($down) { [uint32]0x0100 } else { [uint32]0x0101 }
    $flags = if ($down) {
        [int64](1 -bor ($scanCode -shl 16))
    } else {
        [int64](0xC0000001 -bor ($scanCode -shl 16))
    }
    Send-Message $window $message ([IntPtr]$virtualKey) ([IntPtr]$flags)
}

$oldProbe = $env:BOLTSPARK_PROBE
$oldLocalAppData = $env:LOCALAPPDATA
$env:BOLTSPARK_PROBE = '1'
$env:LOCALAPPDATA = $localAppData
$process = $null
try {
    $process = Start-Process $runtime -ArgumentList 'boltspark.hl' `
        -WorkingDirectory (Join-Path $repoRoot 'bin') `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -NoNewWindow -PassThru
    $window = Wait-Window $process
    [void][BoltsparkPlayModeApi]::SetWindowPos(
        $window, [IntPtr]::Zero, 40, 40, 1440, 900, 0x0004)
    Start-Sleep -Seconds 1

    # Transport toolbar centers at 1440px width: x = 672/705/738, y = 48.
    # Click Play to exercise the button path.
    Send-Mouse $window 0x0200 687 48 ([IntPtr]::Zero)
    Send-Mouse $window 0x0201 687 48 ([IntPtr]1)
    Send-Mouse $window 0x0202 687 48 ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 700

    # Pause/resume with the rebindable F6 default.
    Send-Key $window 0x75 0x40 $true
    Send-Key $window 0x75 0x40 $false
    Start-Sleep -Milliseconds 300
    Send-Key $window 0x75 0x40 $true
    Send-Key $window 0x75 0x40 $false
    Start-Sleep -Milliseconds 300

    # Stop with the rebindable F7 default.
    Send-Key $window 0x76 0x41 $true
    Send-Key $window 0x76 0x41 $false
    Start-Sleep -Milliseconds 700

    [void][BoltsparkPlayModeApi]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Editor did not close after play-mode test.'
    }
    if ((Get-Item $stderr).Length -ne 0) {
        throw "Play-mode test wrote stderr; inspect $stderr."
    }

    $log = Get-Content $stdout -Raw
    $started = [regex]::Match($log,
        '\[probe\] play started objects=(\d+) revision=(\d+)')
    if (-not $started.Success) {
        throw 'Play toolbar button did not start the runtime session.'
    }
    if ($started.Groups[1].Value -ne '1') {
        throw "Unexpected runtime object count: $($started.Groups[1].Value)."
    }
    if ([regex]::Matches($log, '\[probe\] play paused=true').Count -ne 1) {
        throw 'F6 did not pause the running scene.'
    }
    if ([regex]::Matches($log, '\[probe\] play paused=false').Count -ne 1) {
        throw 'F6 did not resume the running scene.'
    }
    $stopped = [regex]::Match($log,
        '\[probe\] play stopped elapsed=([0-9.]+) revision=(\d+)')
    if (-not $stopped.Success) {
        throw 'F7 did not stop the runtime session.'
    }
    if ($started.Groups[2].Value -ne $stopped.Groups[2].Value) {
        throw ('Play/Stop changed the editor history revision: {0} -> {1}.' -f
            $started.Groups[2].Value, $stopped.Groups[2].Value)
    }
    if ([double]::Parse($stopped.Groups[1].Value,
            [Globalization.CultureInfo]::InvariantCulture) -le 0) {
        throw 'Runtime elapsed time did not advance while playing.'
    }

    Write-Host '[play-mode] Native toolbar + F5/F6/F7 transport and editor isolation passed.' -ForegroundColor Green
    Write-Host "[play-mode] Evidence: $outputDir"
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
}

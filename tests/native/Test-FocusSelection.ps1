param(
    [int]$TimeoutSeconds = 20
)

# Window-scoped probe for the F Focus Selection command. It deliberately keeps
# the pointer over the hierarchy panel (never the viewport) so a regression of
# the old viewport-focus gate would suppress the command. No global input
# injection: every event is sent directly to the Boltspark HWND.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$outputDir = Join-Path $repoRoot 'bin\test-results\focus-selection'
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'

New-Item -ItemType Directory -Force $outputDir | Out-Null

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BoltsparkFocusNative {
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w,
        IntPtr l, uint f, uint t, out IntPtr r);
    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
"@

function Send-Key([IntPtr]$window, [int]$virtualKey, [int]$scanCode) {
    $result = [IntPtr]::Zero
    [void][BoltsparkFocusNative]::SendMessageTimeout($window, 0x0100,
        [IntPtr]$virtualKey, [IntPtr](1 -bor ($scanCode -shl 16)),
        0, 5000, [ref]$result)
    Start-Sleep -Milliseconds 120
    [void][BoltsparkFocusNative]::SendMessageTimeout($window, 0x0101,
        [IntPtr]$virtualKey, [IntPtr](0xC0000001 -bor ($scanCode -shl 16)),
        0, 5000, [ref]$result)
    Start-Sleep -Milliseconds 350
}

function Send-MouseMove([IntPtr]$window, [int]$x, [int]$y) {
    $coordinates = [IntPtr](($y -shl 16) -bor ($x -band 0xffff))
    $result = [IntPtr]::Zero
    [void][BoltsparkFocusNative]::SendMessageTimeout($window, 0x0200,
        [IntPtr]::Zero, $coordinates, 0, 5000, [ref]$result)
}

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\build.ps1 first.'
}
$lingering = Get-Process hl -ErrorAction SilentlyContinue
if ($null -ne $lingering) {
    throw 'hl.exe is already running; close it before the focus-selection probe.'
}

$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
$previousProbeFlag = $env:BOLTSPARK_PROBE
$env:BOLTSPARK_PROBE = '1'
$process = Start-Process $runtime -ArgumentList 'boltspark.hl' `
    -WorkingDirectory (Join-Path $repoRoot 'bin') `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
    -NoNewWindow -PassThru
try {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $window = [IntPtr]::Zero
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 125
        $process.Refresh()
        if ($process.HasExited) {
            throw "Boltspark exited before opening a window (code $($process.ExitCode))."
        }
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
            $window = $process.MainWindowHandle
            break
        }
    }
    if ($window -eq [IntPtr]::Zero) {
        throw "Boltspark did not create its native window within $TimeoutSeconds seconds."
    }
    Start-Sleep -Seconds 2

    # Hover the hierarchy panel (left ~255 px), far from the 3D viewport. The
    # primary sampleCube object is selected at startup, so F has a valid target.
    # A fresh editor can still be settling its input focus after other native
    # probes, so retry the chord before declaring failure.
    $focused = $false
    for ($attempt = 0; $attempt -lt 3 -and -not $focused; $attempt++) {
        Send-MouseMove $window 80 400
        Start-Sleep -Milliseconds 400
        Send-Key $window 0x46 0x21 # VK_F
        Start-Sleep -Milliseconds 700
        $log = Get-Content $stdout -Raw
        $focused = $log -match 'camera: focused sampleCube'
    }
    if (-not $focused) {
        throw 'F did not focus the selected object while the pointer was over the hierarchy panel.'
    }
    if ((Get-Item $stderr).Length -ne 0) {
        throw "Focus-selection probe wrote stderr; inspect $stderr."
    }

    [void][BoltsparkFocusNative]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Boltspark did not close after the focus-selection probe.'
    }
    Write-Host '[focus] F frames the selection without viewport focus.' -ForegroundColor Green
}
finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    if ($null -eq $previousProbeFlag) {
        Remove-Item Env:BOLTSPARK_PROBE -ErrorAction SilentlyContinue
    } else {
        $env:BOLTSPARK_PROBE = $previousProbeFlag
    }
}

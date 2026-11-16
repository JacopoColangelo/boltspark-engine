param(
    [int]$TimeoutSeconds = 20
)

# Window-scoped probe for the viewport FOV numeric field. It opens the camera
# settings popup from the PERSPECTIVE strip, clicks the transform-style numeric
# drag field, types an exact value, and commits it with Enter. No global input
# injection: every event is sent directly to the Boltspark HWND.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$outputDir = Join-Path $repoRoot 'bin\test-results\fov-input'
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'

New-Item -ItemType Directory -Force $outputDir | Out-Null

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BoltsparkFovNative {
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w,
        IntPtr l, uint f, uint t, out IntPtr r);
    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
"@

function Send-Mouse([IntPtr]$window, [uint32]$message, [int]$x, [int]$y, [int]$buttons = 0) {
    $coordinates = [IntPtr](($y -shl 16) -bor ($x -band 0xffff))
    $result = [IntPtr]::Zero
    [void][BoltsparkFovNative]::SendMessageTimeout($window, $message,
        [IntPtr]$buttons, $coordinates, 0, 5000, [ref]$result)
}

function Send-Click([IntPtr]$window, [int]$x, [int]$y) {
    Send-Mouse $window 0x0200 $x $y
    Start-Sleep -Milliseconds 180
    Send-Mouse $window 0x0201 $x $y 1
    Start-Sleep -Milliseconds 90
    Send-Mouse $window 0x0202 $x $y
    Start-Sleep -Milliseconds 400
}

function Send-Key([IntPtr]$window, [int]$virtualKey, [int]$scanCode) {
    $result = [IntPtr]::Zero
    [void][BoltsparkFovNative]::SendMessageTimeout($window, 0x0100,
        [IntPtr]$virtualKey, [IntPtr](1 -bor ($scanCode -shl 16)),
        0, 5000, [ref]$result)
    Start-Sleep -Milliseconds 60
    [void][BoltsparkFovNative]::SendMessageTimeout($window, 0x0101,
        [IntPtr]$virtualKey, [IntPtr](0xC0000001 -bor ($scanCode -shl 16)),
        0, 5000, [ref]$result)
    Start-Sleep -Milliseconds 80
}

# hldx converts WM_CHAR into Heaps TextInput events (window.c:351), so typed
# characters must be delivered as WM_CHAR rather than relying on TranslateMessage.
function Send-Char([IntPtr]$window, [char]$character) {
    $result = [IntPtr]::Zero
    [void][BoltsparkFovNative]::SendMessageTimeout($window, 0x0102,
        [IntPtr][int]$character, [IntPtr]1, 0, 5000, [ref]$result)
    Start-Sleep -Milliseconds 80
}

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\build.ps1 first.'
}
$lingering = Get-Process hl -ErrorAction SilentlyContinue
if ($null -ne $lingering) {
    throw 'hl.exe is already running; close it before the FOV input probe.'
}

# Use the same viewport geometry contract as the other window-scoped probes.
$left = 255.0; $right = 386.0; $console = 174.0
$layoutPath = Join-Path $env:LOCALAPPDATA 'Boltspark Engine\layout.json'
if (Test-Path $layoutPath) {
    $layout = Get-Content $layoutPath | ConvertFrom-Json
    $left = [double]$layout.leftPanelWidth
    $right = [double]$layout.rightPanelWidth
    $console = [double]$layout.consoleHeight
}
$viewportX = [int][Math]::Round($left + 4)
$viewportY = 66

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

    $stripX = $viewportX + 58
    $stripY = $viewportY + 20
    $popupX = $viewportX + 8
    $popupY = $viewportY + 8 + 26
    # Numeric field sits at popup (10, 30) with size 128x24.
    $fieldX = $popupX + 10 + 40
    $fieldY = $popupY + 30 + 12

    Send-Click $window $stripX $stripY
    Send-Click $window $fieldX $fieldY

    # Select the displayed value, type an exact FOV, then commit.
    $result = [IntPtr]::Zero
    [void][BoltsparkFovNative]::SendMessageTimeout($window, 0x0100,
        [IntPtr]0x11, [IntPtr]0x001D, 0, 5000, [ref]$result)
    Send-Key $window 0x41 0x1E # Ctrl+A
    [void][BoltsparkFovNative]::SendMessageTimeout($window, 0x0101,
        [IntPtr]0x11, [IntPtr]0xC01D0001, 0, 5000, [ref]$result)
    Send-Char $window '6'
    Send-Char $window '0'
    Send-Key $window 0x0D 0x1C # Enter commits the edit
    Start-Sleep -Milliseconds 500

    $log = Get-Content $stdout -Raw
    $matches = [regex]::Matches($log, '\[viewport\] fov=(\d+)')
    if ($matches.Count -eq 0) {
        throw 'Typing into the FOV field did not report a new field of view.'
    }
    $value = [int]$matches[$matches.Count - 1].Groups[1].Value
    if ($value -ne 60) {
        throw "Typed FOV was not applied: expected 60, got $value."
    }
    if ((Get-Item $stderr).Length -ne 0) {
        throw "FOV input probe wrote stderr; inspect $stderr."
    }

    [void][BoltsparkFovNative]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Boltspark did not close after the FOV input probe.'
    }
    Write-Host "[fov] Typed field set the viewport FOV to $value deg." -ForegroundColor Green
}
finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    if ($null -eq $previousProbeFlag) {
        Remove-Item Env:BOLTSPARK_PROBE -ErrorAction SilentlyContinue
    } else {
        $env:BOLTSPARK_PROBE = $previousProbeFlag
    }
}

param(
    [int]$TimeoutSeconds = 15
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$outputDir = Join-Path $repoRoot 'bin\test-results\rotation-ring-handoff'
$stdout = Join-Path $outputDir 'development.stdout.log'
$stderr = Join-Path $outputDir 'development.stderr.log'

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\tests\test.ps1 -Build first.'
}
if (Get-Process hl -ErrorAction SilentlyContinue) {
    throw 'hl.exe is already running; close it before the rotation handoff probe.'
}
New-Item -ItemType Directory -Force $outputDir | Out-Null

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BoltsparkRotationHandoffApi {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")]
    public static extern bool GetClientRect(IntPtr h, out RECT rect);
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessageTimeout(IntPtr h, uint message,
        IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr h, uint message,
        IntPtr wParam, IntPtr lParam);
    public static IntPtr MousePosition(int x, int y) {
        return (IntPtr)((y << 16) | (x & 0xffff));
    }
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

function Send-Mouse([IntPtr]$window, [uint32]$message,
        [int]$x, [int]$y, [int]$buttons = 0) {
    $result = [IntPtr]::Zero
    [void][BoltsparkRotationHandoffApi]::SendMessageTimeout(
        $window, $message, [IntPtr]$buttons,
        [BoltsparkRotationHandoffApi]::MousePosition($x, $y),
        0, 5000, [ref]$result)
}

function Send-Key([IntPtr]$window, [int]$virtualKey, [int]$scanCode) {
    $result = [IntPtr]::Zero
    $down = 1 -bor ($scanCode -shl 16)
    $up = 0xC0000001 -bor ($scanCode -shl 16)
    [void][BoltsparkRotationHandoffApi]::SendMessageTimeout(
        $window, 0x0100, [IntPtr]$virtualKey, [IntPtr]$down,
        0, 5000, [ref]$result)
    Start-Sleep -Milliseconds 100
    [void][BoltsparkRotationHandoffApi]::SendMessageTimeout(
        $window, 0x0101, [IntPtr]$virtualKey, [IntPtr]$up,
        0, 5000, [ref]$result)
    Start-Sleep -Milliseconds 300
}

function Invoke-Drag([IntPtr]$window, [int]$x, [int]$y,
        [int]$deltaX, [int]$deltaY, [int]$steps) {
    Send-Mouse $window 0x0200 $x $y
    Start-Sleep -Milliseconds 200
    Send-Mouse $window 0x0201 $x $y 1
    Start-Sleep -Milliseconds 100
    for ($index = 1; $index -le $steps; $index++) {
        Send-Mouse $window 0x0200 `
            ($x + $deltaX * $index) ($y + $deltaY * $index) 1
        Start-Sleep -Milliseconds 35
    }
    Send-Mouse $window 0x0202 `
        ($x + $deltaX * $steps) ($y + $deltaY * $steps)
    Start-Sleep -Milliseconds 400
}

function Get-ViewportCenter([IntPtr]$window) {
    $rect = New-Object BoltsparkRotationHandoffApi+RECT
    if (-not [BoltsparkRotationHandoffApi]::GetClientRect($window, [ref]$rect)) {
        throw 'Could not read the Boltspark client rectangle.'
    }
    $left = 250.0
    $right = 318.0
    $console = 160.0
    $layoutPath = Join-Path $env:LOCALAPPDATA 'Boltspark Engine\layout.json'
    if (Test-Path $layoutPath) {
        $layout = Get-Content $layoutPath -Raw | ConvertFrom-Json
        $left = [double]$layout.leftPanelWidth
        $right = [double]$layout.rightPanelWidth
        $console = [double]$layout.consoleHeight
    }
    $viewportWidth = $rect.Right - 8 - $left - $right
    $bodyHeight = $rect.Bottom - 66 - 20
    $viewportHeight = $bodyHeight - $console - 4
    return @{
        X = [int][Math]::Round($left + 4 + $viewportWidth / 2)
        Y = [int][Math]::Round(66 + $viewportHeight / 2)
    }
}

function Parse-Rotation([string]$contents, [string]$handle) {
    $escapedHandle = [regex]::Escape($handle)
    $pattern = "\[gizmo\] drag end object=.* handle=$escapedHandle rotation=" +
        "\(([-0-9.]+), ([-0-9.]+), ([-0-9.]+) deg\)"
    $match = [regex]::Match($contents, $pattern)
    if (-not $match.Success) {
        throw "Rotation probe did not complete the $handle drag."
    }
    return @(
        [double]::Parse($match.Groups[1].Value,
            [Globalization.CultureInfo]::InvariantCulture),
        [double]::Parse($match.Groups[2].Value,
            [Globalization.CultureInfo]::InvariantCulture),
        [double]::Parse($match.Groups[3].Value,
            [Globalization.CultureInfo]::InvariantCulture))
}

$oldProbe = $env:BOLTSPARK_PROBE
$oldLocalAppData = $env:LOCALAPPDATA
$probeLocalAppData = Join-Path $outputDir 'localappdata'
New-Item -ItemType Directory -Force $probeLocalAppData | Out-Null
$env:BOLTSPARK_PROBE = '1'
$env:LOCALAPPDATA = $probeLocalAppData
$process = Start-Process $runtime -ArgumentList 'boltspark.hl' `
    -WorkingDirectory (Join-Path $repoRoot 'bin') `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
    -NoNewWindow -PassThru
try {
    $window = Wait-ForEditorWindow $process
    Start-Sleep -Seconds 2
    $center = Get-ViewportCenter $window

    # E selects Rotate. First tumble from the ring interior, then grab the
    # world-X torus at its stable top sample and sweep it. Probe mode retains
    # absolute input, making every window-scoped event deterministic.
    Send-Key $window 0x45 0x12
    Invoke-Drag $window $center.X $center.Y 6 -4 12
    Invoke-Drag $window ($center.X - 35) ($center.Y - 32) 7 10 10

    [void][BoltsparkRotationHandoffApi]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Boltspark did not close after the rotation handoff probe.'
    }
    $process.Refresh()
    if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) {
        throw "Boltspark exited with code $($process.ExitCode)."
    }
}
finally {
    if ($null -eq $oldProbe) {
        Remove-Item Env:BOLTSPARK_PROBE -ErrorAction SilentlyContinue
    } else {
        $env:BOLTSPARK_PROBE = $oldProbe
    }
    $env:LOCALAPPDATA = $oldLocalAppData
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
}

if ((Get-Item $stderr).Length -ne 0) {
    throw "Rotation handoff probe wrote stderr; inspect $stderr."
}
$contents = Get-Content $stdout -Raw
$arcball = Parse-Rotation $contents 'rotation.omni'
$ring = Parse-Rotation $contents 'rotation.x'
$deltaX = $ring[0] - $arcball[0]
$deltaY = $ring[1] - $arcball[1]
$deltaZ = $ring[2] - $arcball[2]
if ([Math]::Abs($deltaX) -lt 0.1) {
    throw 'The post-arcball torus drag did not rotate the object.'
}
if ([Math]::Abs($deltaX / 15 - [Math]::Round($deltaX / 15)) -gt 0.01) {
    throw "The torus result was not a 15-degree increment: delta X=$deltaX."
}
if ([Math]::Abs($deltaY) -gt 0.05 -or [Math]::Abs($deltaZ) -gt 0.05) {
    throw "The world-X torus coupled other axes after arcball: delta=($deltaX, $deltaY, $deltaZ)."
}

Write-Host ('[rotation-handoff] Arcball {0} -> world-X torus {1} passed.' -f `
    ('({0}, {1}, {2})' -f $arcball[0], $arcball[1], $arcball[2]), `
    ('({0}, {1}, {2})' -f $ring[0], $ring[1], $ring[2])) `
    -ForegroundColor Green

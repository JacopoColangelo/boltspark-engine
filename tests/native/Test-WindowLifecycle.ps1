param(
    [int]$TimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\window-lifecycle\$runId"
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
public static class BoltsparkWindowLifecycleApi {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", SetLastError=true)] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int command);
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

function Get-ClientSize([IntPtr]$window) {
    $rect = New-Object BoltsparkWindowLifecycleApi+RECT
    if (-not [BoltsparkWindowLifecycleApi]::GetClientRect($window, [ref]$rect)) {
        throw 'GetClientRect failed.'
    }
    return @{ Width = $rect.Right - $rect.Left; Height = $rect.Bottom - $rect.Top }
}

function Assert-Responsive([IntPtr]$window, [string]$stage) {
    $result = [IntPtr]::Zero
    $sent = [BoltsparkWindowLifecycleApi]::SendMessageTimeout(
        $window, 0, [IntPtr]::Zero, [IntPtr]::Zero, 0x0002, 3000, [ref]$result)
    if ($sent -eq [IntPtr]::Zero) { throw "Editor stopped responding during $stage." }
}

function Send-Mouse([IntPtr]$window, [uint32]$message, [int]$x, [int]$y, [IntPtr]$buttons) {
    $result = [IntPtr]::Zero
    $sent = [BoltsparkWindowLifecycleApi]::SendMessageTimeout(
        $window, $message, $buttons,
        [BoltsparkWindowLifecycleApi]::MakeLParam($x, $y),
        0, 5000, [ref]$result)
    if ($sent -eq [IntPtr]::Zero) {
        throw ('Mouse message 0x{0:X} failed at ({1},{2}).' -f $message, $x, $y)
    }
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
    Start-Sleep -Seconds 1

    foreach ($size in @(
        @{ Width = 960; Height = 720; Name = 'small' },
        @{ Width = 1600; Height = 1000; Name = 'large' },
        @{ Width = 1440; Height = 900; Name = 'baseline' }
    )) {
        if (-not [BoltsparkWindowLifecycleApi]::SetWindowPos(
                $window, [IntPtr]::Zero, 40, 40, $size.Width, $size.Height, 0x0004)) {
            throw "SetWindowPos failed for $($size.Name)."
        }
        Start-Sleep -Milliseconds 500
        Assert-Responsive $window $size.Name
        $client = Get-ClientSize $window
        if ($client.Width -lt 800 -or $client.Height -lt 600) {
            throw "Unexpected client size after $($size.Name): $($client.Width)x$($client.Height)."
        }
    }

    [void][BoltsparkWindowLifecycleApi]::ShowWindow($window, 3)  # maximize
    Start-Sleep -Milliseconds 700
    Assert-Responsive $window 'maximize'
    [void][BoltsparkWindowLifecycleApi]::ShowWindow($window, 9)  # restore
    Start-Sleep -Milliseconds 700
    Assert-Responsive $window 'restore'
    [void][BoltsparkWindowLifecycleApi]::ShowWindow($window, 6)  # minimize
    Start-Sleep -Milliseconds 350
    [void][BoltsparkWindowLifecycleApi]::ShowWindow($window, 9)  # restore
    Start-Sleep -Milliseconds 700
    Assert-Responsive $window 'minimize/restore'

    # Start from a deterministic client geometry before exercising the left
    # splitter. The exact client dimensions are queried after non-client DPI
    # adjustments instead of assuming they match SetWindowPos's outer size.
    [void][BoltsparkWindowLifecycleApi]::SetWindowPos(
        $window, [IntPtr]::Zero, 40, 40, 1440, 900, 0x0004)
    Start-Sleep -Milliseconds 700
    $client = Get-ClientSize $window
    $splitterX = 250
    $dragY = 300
    Send-Mouse $window 0x0200 $splitterX $dragY ([IntPtr]::Zero)
    Send-Mouse $window 0x0201 $splitterX $dragY ([IntPtr]1)
    for ($step = 1; $step -le 10; $step++) {
        Send-Mouse $window 0x0200 ($splitterX + $step * 10) $dragY ([IntPtr]1)
        Start-Sleep -Milliseconds 25
    }
    Send-Mouse $window 0x0202 ($splitterX + 100) $dragY ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 700

    $layoutPath = Join-Path $localAppData 'Boltspark Engine\layout.json'
    if (-not (Test-Path $layoutPath)) { throw 'Splitter drag did not persist layout.json.' }
    $layout = Get-Content $layoutPath -Raw | ConvertFrom-Json
    if ([Math]::Abs([double]$layout.leftPanelWidth - 350) -gt 3) {
        throw "Splitter drag expected left width about 350, got $($layout.leftPanelWidth)."
    }

    # Reproduce DockLayout geometry after the drag. Deselect in empty viewport
    # space first so the gizmo cannot consume the center click, then pick the
    # origin cube at the recalculated viewport center.
    $bodyTop = 66.0
    $bodyHeight = [Math]::Max(0, $client.Height - 66 - 20)
    $panelSpace = [Math]::Max(0, $client.Width - 8)
    $left = [double]$layout.leftPanelWidth
    $right = [double]$layout.rightPanelWidth
    $console = [Math]::Max(140, [Math]::Min(
        [double]$layout.consoleHeight, $bodyHeight - 168 - 4))
    $viewportWidth = $panelSpace - $left - $right
    $viewportHeight = $bodyHeight - $console - 4
    $viewportX = $left + 4
    $emptyX = [int][Math]::Round($viewportX + 18)
    $emptyY = [int][Math]::Round($bodyTop + 18)
    $centerX = [int][Math]::Round($viewportX + $viewportWidth * 0.5)
    $centerY = [int][Math]::Round($bodyTop + $viewportHeight * 0.5)
    foreach ($point in @(
        @{ X = $emptyX; Y = $emptyY },
        @{ X = $centerX; Y = $centerY }
    )) {
        Send-Mouse $window 0x0200 $point.X $point.Y ([IntPtr]::Zero)
        Send-Mouse $window 0x0201 $point.X $point.Y ([IntPtr]1)
        Send-Mouse $window 0x0202 $point.X $point.Y ([IntPtr]::Zero)
        Start-Sleep -Milliseconds 500
    }

    [void][BoltsparkWindowLifecycleApi]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Editor did not close after lifecycle test.'
    }
    $process.Refresh()
    if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) {
        throw "Editor exited with code $($process.ExitCode)."
    }
    if ((Get-Item $stderr).Length -ne 0) { throw "Lifecycle test wrote stderr; inspect $stderr." }

    $log = Get-Content $stdout -Raw
    if ($log -notmatch 'viewport: no object at pointer') {
        throw 'Empty-space viewport deselection was not observed after splitter resize.'
    }
    if ($log -notmatch 'viewport: selected sampleCube') {
        throw 'Viewport picking did not select sampleCube after splitter resize.'
    }

    Write-Host '[window] Resize, maximize/restore, splitter persistence, and post-split picking passed.' -ForegroundColor Green
    Write-Host "[window] Evidence: $outputDir"
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
}

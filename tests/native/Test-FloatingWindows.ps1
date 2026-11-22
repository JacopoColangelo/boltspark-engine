param(
    [int]$TimeoutSeconds = 25,
    [string]$Executable = 'boltspark.hl'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\floating-windows\$runId"
$localAppData = Join-Path $outputDir 'localappdata'
$layoutDir = Join-Path $localAppData 'Boltspark Engine'
$layoutPath = Join-Path $layoutDir 'dock-layout.json'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
New-Item -ItemType Directory -Force $layoutDir | Out-Null

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\build.ps1 first.'
}

# Start with Output Log already floating in the persisted layout. Startup must
# re-host it as a real HWND before the first draw, never as an in-app ghost.
$layout = @{
    version = 3
    bottomTab = 1
    closed = @()
    root = @{
        kind = 'tab'
        active = 1
        panels = @(
            @{ id = 'boltspark.hierarchy'; key = 'boltspark.hierarchy'; state = $null },
            @{ id = 'boltspark.viewport'; key = 'boltspark.viewport'; state = $null },
            @{ id = 'boltspark.inspector'; key = 'boltspark.inspector'; state = $null },
            @{ id = 'boltspark.assets'; key = 'boltspark.assets'; state = $null }
        )
    }
    floating = @(@{
        id = 7
        title = 'Output Log'
        x = 120
        y = 120
        width = 520
        height = 360
        minimized = $false
        root = @{
            kind = 'tab'
            active = 0
            panels = @(
                @{ id = 'boltspark.console'; key = 'boltspark.console'; state = $null }
            )
        }
    })
}
[System.IO.File]::WriteAllText($layoutPath, ($layout | ConvertTo-Json -Depth 20))

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class BoltsparkFloatApi {
    public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("gdi32.dll")] public static extern uint GetPixel(IntPtr dc, int x, int y);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleBitmap(IntPtr dc, int w, int h);
    [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr obj);
    [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr dc);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
    public static IntPtr MakeLParam(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }

    public static uint[] CapturePixels(IntPtr h, int width, int height, int[] xs, int[] ys) {
        IntPtr screen = GetDC(IntPtr.Zero);
        IntPtr mem = CreateCompatibleDC(screen);
        IntPtr bitmap = CreateCompatibleBitmap(screen, width, height);
        IntPtr old = SelectObject(mem, bitmap);
        var colors = new uint[xs.Length];
        try {
            PrintWindow(h, mem, 2); // PW_RENDERFULLCONTENT
            for (int i = 0; i < xs.Length; i++) colors[i] = GetPixel(mem, xs[i], ys[i]);
        }
        finally {
            SelectObject(mem, old);
            DeleteObject(bitmap);
            DeleteDC(mem);
            ReleaseDC(IntPtr.Zero, screen);
        }
        return colors;
    }

    public static int[] ClientSize(IntPtr h) {
        RECT r;
        GetClientRect(h, out r);
        return new int[] { r.Right - r.Left, r.Bottom - r.Top };
    }

    public static IntPtr[] FindPanelWindows(uint pid) {
        var result = new List<IntPtr>();
        EnumWindows((h, l) => {
            uint owner;
            GetWindowThreadProcessId(h, out owner);
            if (owner != pid) return true;
            var name = new StringBuilder(128);
            GetClassName(h, name, name.Capacity);
            if (name.ToString() == "BoltSparkFloatPanel") result.Add(h);
            return true;
        }, IntPtr.Zero);
        return result.ToArray();
    }
}
"@

function Send-RightClick([IntPtr]$window, [int]$x, [int]$y) {
    $result = [IntPtr]::Zero
    $param = [BoltsparkFloatApi]::MakeLParam($x, $y)
    [void][BoltsparkFloatApi]::SendMessageTimeout(
        $window, 0x0204, [IntPtr]2, $param, 0, 3000, [ref]$result)  # WM_RBUTTONDOWN
    [void][BoltsparkFloatApi]::SendMessageTimeout(
        $window, 0x0205, [IntPtr]::Zero, $param, 0, 3000, [ref]$result)  # WM_RBUTTONUP
    Start-Sleep -Milliseconds 250
}

function Get-PanelIds($node) {
    $ids = @()
    if ($null -eq $node) { return $ids }
    if ($node.kind -eq 'tab' -and $null -ne $node.panels) {
        $ids += @($node.panels | ForEach-Object { $_.id })
    }
    $ids += @(Get-PanelIds $node.first)
    $ids += @(Get-PanelIds $node.second)
    return $ids
}

function Send-Click([IntPtr]$window, [int]$x, [int]$y) {
    $result = [IntPtr]::Zero
    $param = [BoltsparkFloatApi]::MakeLParam($x, $y)
    [void][BoltsparkFloatApi]::SendMessageTimeout(
        $window, 0x0200, [IntPtr]::Zero, $param, 0, 3000, [ref]$result)  # WM_MOUSEMOVE
    [void][BoltsparkFloatApi]::SendMessageTimeout(
        $window, 0x0201, [IntPtr]1, $param, 0, 3000, [ref]$result)       # WM_LBUTTONDOWN
    [void][BoltsparkFloatApi]::SendMessageTimeout(
        $window, 0x0202, [IntPtr]::Zero, $param, 0, 3000, [ref]$result)  # WM_LBUTTONUP
    Start-Sleep -Milliseconds 250
}

function Get-FloatChecksum([IntPtr]$window) {
    # Capture the window's own visual, independent of z-order or cached DCs.
    $rect = New-Object BoltsparkFloatApi+RECT
    if (-not [BoltsparkFloatApi]::GetClientRect($window, [ref]$rect)) {
        throw 'GetClientRect failed while sampling the float.'
    }
    $width = [int]($rect.Right - $rect.Left)
    $height = [int]($rect.Bottom - $rect.Top)
    $xs = @()
    for ($x = 20; $x -lt ($width - 20); $x += 40) { $xs += $x }
    $ys = @()
    for ($y = 40; $y -lt ($height - 8); $y += 24) { $ys += $y }
    $sum = [int64]0
    foreach ($y in $ys) {
        $sameY = @()
        foreach ($x in $xs) { $sameY += $y }
        $colors = [BoltsparkFloatApi]::CapturePixels(
            $window, $width, $height, [int[]]$xs, [int[]]$sameY)
        foreach ($color in $colors) { $sum += [int64]$color }
    }
    return $sum
}

function Find-PanelPath($node, [string]$id, [string]$prefix) {
    if ($null -eq $node) { return $null }
    if ($node.kind -eq 'tab' -and $null -ne $node.panels) {
        for ($i = 0; $i -lt $node.panels.Count; $i++) {
            if ($node.panels[$i].id -eq $id) { return "$prefix/panels[$i]" }
        }
    }
    $hit = Find-PanelPath $node.first $id "$prefix/first"
    if ($null -ne $hit) { return $hit }
    return Find-PanelPath $node.second $id "$prefix/second"
}

function Assert-Responsive([IntPtr]$window, [string]$stage) {
    $result = [IntPtr]::Zero
    $sent = [BoltsparkFloatApi]::SendMessageTimeout(
        $window, 0, [IntPtr]::Zero, [IntPtr]::Zero, 0x0002, 4000, [ref]$result)
    if ($sent -eq [IntPtr]::Zero) { throw "Window stopped responding during $stage." }
}

function Wait-FloatWindow([Diagnostics.Process]$process) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
        $process.Refresh()
        if ($process.HasExited) { throw "Editor exited early with code $($process.ExitCode)." }
        $windows = [BoltsparkFloatApi]::FindPanelWindows([uint32]$process.Id)
        if ($windows.Length -gt 0) { return $windows[0] }
    }
    throw 'No BoltSparkFloatPanel HWND was created at startup.'
}

$oldProbe = $env:BOLTSPARK_PROBE
$oldLocalAppData = $env:LOCALAPPDATA
$env:BOLTSPARK_PROBE = '1'
$env:LOCALAPPDATA = $localAppData
$process = $null
try {
    if ($Executable -eq 'boltspark.hl') {
        $process = Start-Process $runtime -ArgumentList 'boltspark.hl' `
            -WorkingDirectory (Join-Path $repoRoot 'bin') `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
            -NoNewWindow -PassThru
    } else {
        $launcher = Join-Path $repoRoot 'release\Boltspark.exe'
        if (-not (Test-Path $launcher)) { throw "Release executable not found: $launcher" }
        $process = Start-Process $launcher `
            -WorkingDirectory (Join-Path $repoRoot 'release') `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
            -NoNewWindow -PassThru
    }
    $main = $null
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 125
        $process.Refresh()
        if ($process.HasExited) { throw "Editor exited early with code $($process.ExitCode)." }
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
            $main = $process.MainWindowHandle
            break
        }
    }
    if ($main -eq $null) { throw 'Editor HWND did not appear.' }

    $floatWindow = Wait-FloatWindow $process
    Write-Host "[float] Native panel HWND: $floatWindow" -ForegroundColor DarkGray

    # The editor and the float must both answer WM_NULL while the float is live.
    Assert-Responsive $main 'float idle (editor)'
    Assert-Responsive $floatWindow 'float idle (panel)'

    if ($Executable -eq 'boltspark.hl') {
        $beforeMenus = (Get-Content $stdout -Raw |
            Select-String -Pattern '\[probe\] menu open' -AllMatches).Matches.Count
        Send-RightClick $floatWindow 200 200
        $afterMenus = (Get-Content $stdout -Raw |
            Select-String -Pattern '\[probe\] menu open' -AllMatches).Matches.Count
        if ($afterMenus -le $beforeMenus) {
            throw 'Right-click inside a floating panel did not open a submenu.'
        }
        # Dismiss the submenu so its full-window catcher cannot swallow later input.
        Send-Click $floatWindow 400 380
        Write-Host '[float] Right-click submenu passed.' -ForegroundColor DarkGray
    }

    # Let the watchdog window pass while the float keeps being pumped/painted.
    Start-Sleep -Seconds 6
    Assert-Responsive $main 'float sustained (editor)'
    Assert-Responsive $floatWindow 'float sustained (panel)'
    $process.Refresh()
    if ($process.HasExited) { throw "Editor exited while the float was open: $($process.ExitCode)." }

    # Sample the float client area: it must be painted, not a black/empty HWND.
    $dc = [BoltsparkFloatApi]::GetDC($floatWindow)
    try {
        $painted = 0
        foreach ($point in @(@(10, 10), @(60, 40), @(200, 120), @(400, 300))) {
            $color = [BoltsparkFloatApi]::GetPixel($dc, $point[0], $point[1])
            if ($color -ne 0 -and $color -ne 0xFFFFFFFF) { $painted++ }
        }
        if ($painted -eq 0) { throw 'Floating panel client area has no painted pixels.' }
        Write-Host "[float] Painted sample points: $painted/4" -ForegroundColor DarkGray
    }
    finally {
        [void][BoltsparkFloatApi]::ReleaseDC($floatWindow, $dc)
    }

    # User closes the float: the panel must return to the editor and save the
    # re-docked layout without leaving the HWND alive.
    [void][BoltsparkFloatApi]::PostMessage(
        $floatWindow, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)  # WM_CLOSE
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
        if (-not [BoltsparkFloatApi]::IsWindow($floatWindow)) { break }
    }
    if ([BoltsparkFloatApi]::IsWindow($floatWindow)) {
        throw 'Floating HWND survived WM_CLOSE.'
    }
    Start-Sleep -Milliseconds 500
    Assert-Responsive $main 'after re-dock'

    $saved = Get-Content $layoutPath -Raw | ConvertFrom-Json
    if (@($saved.floating).Count -ne 0) {
        throw 'Re-docked panel was still persisted as floating.'
    }
    $panelIds = @(Get-PanelIds $saved.root)
    if ($panelIds -notcontains 'boltspark.console') {
        throw 'Output Log did not return to the editor docking tree.'
    }

    # Remember where the console lives before floating it again; closing the
    # float must put it back in exactly that tab and slot order.
    $beforeRefloat = Get-Content $layoutPath -Raw | ConvertFrom-Json
    $originalPath = Find-PanelPath $beforeRefloat.root 'boltspark.console' 'root'

    # On-demand float through Window > Float Focused Panel. The re-docked
    # console tab sits in the right half of the split, so click its tab first.
    Send-Click $main 760 76
    Start-Sleep -Milliseconds 300
    Send-Click $main 219 15    # Window menu
    if ($Executable -eq 'boltspark.hl') {
        $menuLog = Get-Content $stdout -Raw
        if ($menuLog -notmatch '\[probe\] menu open') {
            throw 'Window menu did not open.'
        }
    }
    Send-Click $main 264 237   # Float Focused Panel (section/separator heights vary)
    $secondFloat = [IntPtr]::Zero
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
        $windows = [BoltsparkFloatApi]::FindPanelWindows([uint32]$process.Id)
        if ($windows.Length -gt 0) { $secondFloat = $windows[0]; break }
    }
    if ($secondFloat -eq [IntPtr]::Zero) {
        throw 'Window > Float Focused Panel did not create a native HWND.'
    }
    Assert-Responsive $secondFloat 'on-demand float'

    # Widening the HWND must paint the newly exposed strip immediately, without
    # waiting for the mouse button to be released (WM_SIZE is synchronous).
    $beforeSize = [BoltsparkFloatApi]::ClientSize($secondFloat)
    $oldClientWidth = [int]($beforeSize[0])
    $oldClientHeight = [int]($beforeSize[1])
    [void][BoltsparkFloatApi]::SetWindowPos(
        $secondFloat, [IntPtr]::Zero, 0, 0,
        $oldClientWidth + 16 + 140, $oldClientHeight + 16 + 32,
        0x0002 -bor 0x0004 -bor 0x0010)  # NOMOVE | NOZORDER | NOACTIVATE
    $afterSize = [BoltsparkFloatApi]::ClientSize($secondFloat)
    $newClientWidth = [int]($afterSize[0])
    $newClientHeight = [int]($afterSize[1])
    if ($newClientWidth -le $oldClientWidth + 80) {
        throw "Float did not widen: $oldClientWidth -> $newClientWidth."
    }
    $stripX = @(($oldClientWidth + 12), ($oldClientWidth + 40))
    $stripPainted = 0
    foreach ($y in @(80, 160, 240)) {
        $colors = [BoltsparkFloatApi]::CapturePixels($secondFloat,
            $newClientWidth, $newClientHeight,
            [int[]]$stripX, [int[]]@($y, $y))
        foreach ($color in $colors) {
            if ($color -ne 0 -and $color -ne 0xFFFFFFFF) { $stripPainted++ }
        }
    }
    if ($stripPainted -eq 0) {
        throw 'Newly exposed strip stayed black during resize.'
    }
    Write-Host "[float] Resize strip painted samples: $stripPainted/6" -ForegroundColor DarkGray

    # A line printed from the Help menu must reach the editor log path that
    # also mirrors into floating Output Logs.
    Send-Click $main 278 15    # Help menu logs a command-surface message
    Start-Sleep -Milliseconds 700
    if ($Executable -eq 'boltspark.hl') {
        $helpLog = Get-Content $stdout -Raw
        if ($helpLog -notmatch 'Help menu: command surface reserved') {
            throw 'Help menu log line did not reach the editor log path.'
        }
    }

    # Use the header's dock button: it must re-dock at the original position.
    $rect = New-Object BoltsparkFloatApi+RECT
    if (-not [BoltsparkFloatApi]::GetClientRect($secondFloat, [ref]$rect)) {
        throw 'GetClientRect failed for the on-demand float.'
    }
    $dockX = [int]($rect.Right - 64)
    Send-Click $secondFloat $dockX 12
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
        if (-not [BoltsparkFloatApi]::IsWindow($secondFloat)) { break }
    }
    if ([BoltsparkFloatApi]::IsWindow($secondFloat)) {
        throw 'Float dock button did not destroy the HWND.'
    }
    Assert-Responsive $main 'after dock button'
    $afterClose = Get-Content $layoutPath -Raw | ConvertFrom-Json
    $restoredPath = Find-PanelPath $afterClose.root 'boltspark.console' 'root'
    if ($null -eq $originalPath -or $restoredPath -ne $originalPath) {
        throw "Closing the float did not restore the console to $originalPath (got $restoredPath)."
    }
    Write-Host "[float] Dock button restored panel to $restoredPath" -ForegroundColor DarkGray
    Write-Host '[float] On-demand float, live log mirroring, and dock button passed.' -ForegroundColor DarkGray

    # The header X removes the panel instead of docking it.
    Send-Click $main 760 76
    Start-Sleep -Milliseconds 250
    Send-Click $main 219 15
    Send-Click $main 264 237
    $thirdFloat = [IntPtr]::Zero
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
        $windows = [BoltsparkFloatApi]::FindPanelWindows([uint32]$process.Id)
        if ($windows.Length -gt 0) { $thirdFloat = $windows[0]; break }
    }
    if ($thirdFloat -eq [IntPtr]::Zero) {
        throw 'Could not create a third float for the close-button test.'
    }
    $thirdRect = New-Object BoltsparkFloatApi+RECT
    [void][BoltsparkFloatApi]::GetClientRect($thirdFloat, [ref]$thirdRect)
    $closeX = [int]($thirdRect.Right - 10)
    Send-Click $thirdFloat $closeX 12
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
        if (-not [BoltsparkFloatApi]::IsWindow($thirdFloat)) { break }
    }
    if ([BoltsparkFloatApi]::IsWindow($thirdFloat)) {
        throw 'Float close button did not destroy the HWND.'
    }
    Start-Sleep -Milliseconds 300
    $afterRemoval = Get-Content $layoutPath -Raw | ConvertFrom-Json
    if ($null -ne (Find-PanelPath $afterRemoval.root 'boltspark.console' 'root')) {
        throw 'Float close button re-docked the panel instead of removing it.'
    }
    Write-Host '[float] Close button removed panel from the editor.' -ForegroundColor DarkGray

    [void][BoltsparkFloatApi]::PostMessage(
        $main, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Editor did not close after floating-window test.'
    }
    $process.Refresh()
    if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) {
        throw "Editor exited with code $($process.ExitCode)."
    }
    if ((Get-Item $stderr).Length -ne 0) {
        throw "Floating-window test wrote stderr; inspect $stderr."
    }
    if ($Executable -eq 'boltspark.hl') {
        $log = Get-Content $stdout -Raw
        if ($log -match 'Program timeout') {
            throw 'Heaps watchdog fired while a floating panel was open.'
        }
        if ($log -notmatch 'docked floating window into editor') {
            throw 'Re-dock path did not run.'
        }
    }

    Write-Host '[float] Native float creation, live pump, re-dock, and shutdown passed.' -ForegroundColor Green
    Write-Host "[float] Evidence: $outputDir"
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
}

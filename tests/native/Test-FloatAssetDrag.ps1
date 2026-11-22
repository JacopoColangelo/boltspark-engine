param(
    [int]$TimeoutSeconds = 25,
    [string]$Executable = 'boltspark.hl'
)

# Cross-window asset drag regression: drag an engine material out of a floating
# Asset Browser HWND and drop it on a type-aware Inspector slot in the main
# editor. Verifies the screen->scene coordinate translation (the editor client
# origin, not its frame origin) and that float event dispatch restores all
# shared UI overrides when a drop rebuilds the Inspector.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\float-asset-drag\$runId"
$localAppData = Join-Path $outputDir 'localappdata'
$layoutDir = Join-Path $localAppData 'Boltspark Engine'
$layoutPath = Join-Path $layoutDir 'dock-layout.json'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
New-Item -ItemType Directory -Force $layoutDir | Out-Null

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\build.ps1 first.'
}

# Inspector must be a visible tab group; the Asset Browser is hosted in a
# separate HWND before the first draw.
$panel = { param([string]$id) @{ id = $id; key = $id; state = $null } }
$tab = { param([string[]]$ids) @{
    kind = 'tab'; active = 0
    panels = @($ids | ForEach-Object { & $panel $_ })
} }
$layout = @{
    version = 3
    bottomTab = 0
    closed = @()
    root = @{
        kind = 'split'; orientation = 'h'; ratio = 0.25
        minFirst = 180; minSecond = 560
        first = & $tab @('boltspark.hierarchy')
        second = @{
            kind = 'split'; orientation = 'h'; ratio = 0.6
            minFirst = 320; minSecond = 260
            first = @{
                kind = 'split'; orientation = 'v'; ratio = 0.7
                minFirst = 168; minSecond = 120
                first = & $tab @('boltspark.viewport')
                second = & $tab @('boltspark.console')
            }
            second = & $tab @('boltspark.inspector')
        }
    }
    floating = @(@{
        id = 7
        title = 'Asset Browser'
        x = 300
        y = 200
        width = 480
        height = 372
        minimized = $false
        root = & $tab @('boltspark.assets')
    })
}
[System.IO.File]::WriteAllText($layoutPath, ($layout | ConvertTo-Json -Depth 20))

# Engine assets are hidden by default in a fresh profile; the user's screenshot
# has them enabled, so seed the same Asset Browser state for this probe.
$assetState = @{
    version = 1
    favorites = @(); recent = @()
    # Large thumbnails guarantee vertical overflow so WM_MOUSEWHEEL can be
    # verified with the small deterministic float.
    viewMode = 0; thumbnailSize = 192
    sortKey = 0; sortAsc = $true
    typeFilter = 'engine'; showEngineAssets = $true
    foldersFirst = $false; folderWidth = 118
    inspectorWidth = 220; inspectorCollapsed = $false
}
[System.IO.File]::WriteAllText(
    (Join-Path $layoutDir 'asset-browser.json'),
    ($assetState | ConvertTo-Json -Depth 8))

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class BoltsparkFloatDragApi {
    public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    public static IntPtr LParam(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }

    public static IntPtr[] FindWindows(uint pid, string className) {
        var result = new List<IntPtr>();
        EnumWindows((h, l) => {
            uint owner;
            GetWindowThreadProcessId(h, out owner);
            if (owner != pid) return true;
            var name = new StringBuilder(128);
            GetClassName(h, name, name.Capacity);
            if (name.ToString() == className) result.Add(h);
            return true;
        }, IntPtr.Zero);
        return result.ToArray();
    }

    public static int[] ClientOrigin(IntPtr h) {
        POINT p;
        p.X = 0; p.Y = 0;
        if (!ClientToScreen(h, ref p)) return new int[] { 0, 0 };
        return new int[] { p.X, p.Y };
    }

    public static void Wheel(IntPtr h, int clientX, int clientY, int delta) {
        POINT p;
        p.X = clientX; p.Y = clientY;
        ClientToScreen(h, ref p);
        long wp = ((long)(ushort)(short)delta) << 16;
        IntPtr ignored;
        SendMessageTimeout(h, 0x020A, (IntPtr)wp, LParam(p.X, p.Y),
            0, 3000, out ignored);
    }
}
"@

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Drawing;
public static class BoltsparkDragShot {
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr GetWindowDC(IntPtr h);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleBitmap(IntPtr dc, int w, int h);
    [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr obj);
    [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr dc);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    public static void Save(IntPtr h, string path) {
        RECT r;
        if (!GetClientRect(h, out r)) return;
        int w = r.R - r.L, ht = r.B - r.T;
        IntPtr screen = GetWindowDC(h);
        IntPtr mem = CreateCompatibleDC(screen);
        IntPtr bmp = CreateCompatibleBitmap(screen, w, ht);
        IntPtr old = SelectObject(mem, bmp);
        try {
            PrintWindow(h, mem, 2);
            using (var image = Image.FromHbitmap(bmp))
                image.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        } finally {
            SelectObject(mem, old);
            DeleteObject(bmp);
            DeleteDC(mem);
            ReleaseDC(h, screen);
        }
    }
    public static int CountRgb(string path, int left, int top,
            int width, int height, int rgb) {
        int count = 0;
        using (var image = new Bitmap(path)) {
            int right = Math.Min(image.Width, left + width);
            int bottom = Math.Min(image.Height, top + height);
            for (int y = Math.Max(0, top); y < bottom; y++)
                for (int x = Math.Max(0, left); x < right; x++)
                    if ((image.GetPixel(x, y).ToArgb() & 0xFFFFFF) == rgb)
                        count++;
        }
        return count;
    }
}
"@ -ReferencedAssemblies System.Drawing

function Send-Mouse([IntPtr]$window, [uint32]$message, [int]$x, [int]$y) {
    $result = [IntPtr]::Zero
    [void][BoltsparkFloatDragApi]::SendMessageTimeout(
        $window, $message, [IntPtr]::Zero,
        [BoltsparkFloatDragApi]::LParam($x, $y), 0, 3000, [ref]$result)
}

function Read-Log() {
    if (-not (Test-Path $stdout)) { return '' }
    return Get-Content $stdout -Raw
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

    $floatWindow = [IntPtr]::Zero
    $main = [IntPtr]::Zero
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
        $process.Refresh()
        if ($process.HasExited) { throw "Editor exited early with code $($process.ExitCode)." }
        $floats = [BoltsparkFloatDragApi]::FindWindows([uint32]$process.Id, 'BoltSparkFloatPanel')
        $mains = [BoltsparkFloatDragApi]::FindWindows([uint32]$process.Id, 'HL_WIN')
        if ($floats.Length -gt 0 -and $mains.Length -gt 0) {
            $floatWindow = $floats[0]
            $main = $mains[0]
            break
        }
    }
    if ($floatWindow -eq [IntPtr]::Zero -or $main -eq [IntPtr]::Zero) {
        throw 'Floating Asset Browser and editor HWNDs did not appear.'
    }
    Write-Host "[float-drag] float=$floatWindow editor=$main" -ForegroundColor DarkGray

    # The settings popover is a custom group of overlay siblings (not a
    # MenuDropdown). It must be reparented into the float-owned scene.
    Send-Mouse $floatWindow 0x0200 405 38
    Send-Mouse $floatWindow 0x0201 405 38
    Send-Mouse $floatWindow 0x0202 405 38
    Start-Sleep -Milliseconds 300
    if ((Read-Log) -notmatch '\[probe\] asset browser settings local=true') {
        throw 'Asset Browser settings popover was not hosted in the floating window.'
    }
    [BoltsparkDragShot]::Save($floatWindow,
        (Join-Path $outputDir 'float-settings.png'))
    # Dismiss through the float-owned full-client catch.
    Send-Mouse $floatWindow 0x0200 100 250
    Send-Mouse $floatWindow 0x0201 100 250
    Send-Mouse $floatWindow 0x0202 100 250
    Start-Sleep -Milliseconds 200
    Write-Host '[float-drag] Floating Asset Browser settings passed.' -ForegroundColor DarkGray

    # Engine assets live under the Engine folder, which is collapsed on startup.
    # Open it so the grid contains draggable engine tiles.
    Send-Mouse $floatWindow 0x0200 55 110
    Send-Mouse $floatWindow 0x0201 55 110
    Send-Mouse $floatWindow 0x0202 55 110
    Start-Sleep -Milliseconds 300
    if ((Read-Log) -notmatch '\[probe\] asset browser navigate folder=Engine') {
        throw 'Could not open the Engine folder in the floating Asset Browser.'
    }

    # WM_MOUSEWHEEL carries screen coordinates, unlike ordinary mouse
    # messages. The float host must convert them to client coordinates before
    # injecting EWheel or the grid under the pointer never sees the event.
    $scrollCount = ((Read-Log) |
        Select-String -Pattern '\[probe\] asset browser grid scroll=' -AllMatches).Matches.Count
    [BoltsparkFloatDragApi]::Wheel($floatWindow, 330, 250, -120)
    Start-Sleep -Milliseconds 300
    $afterScrollCount = ((Read-Log) |
        Select-String -Pattern '\[probe\] asset browser grid scroll=' -AllMatches).Matches.Count
    if ($afterScrollCount -le $scrollCount) {
        throw 'Mouse wheel over the floating Asset Browser did not scroll its asset grid.'
    }
    [BoltsparkFloatDragApi]::Wheel($floatWindow, 330, 250, 120)
    Start-Sleep -Milliseconds 200
    Write-Host '[float-drag] Floating Asset Browser wheel passed.' -ForegroundColor DarkGray

    $floatOrigin = [BoltsparkFloatDragApi]::ClientOrigin($floatWindow)
    $mainOrigin = [BoltsparkFloatDragApi]::ClientOrigin($main)
    $offsetX = [int]($floatOrigin[0] - $mainOrigin[0])
    $offsetY = [int]($floatOrigin[1] - $mainOrigin[1])
    Write-Host "[float-drag] client offset=$offsetX,$offsetY" -ForegroundColor DarkGray

    # Find an engine asset tile by clicking grid positions. A plain click logs
    # the press through beginEngineAssetDrag without starting a drag session.
    # The first engine tile is at ~126,54 in the 480x372 float client area.
    $tx = 160
    $ty = 95
    Send-Mouse $floatWindow 0x0200 $tx $ty
    Send-Mouse $floatWindow 0x0201 $tx $ty
    Send-Mouse $floatWindow 0x0200 ($tx + 12) ($ty + 12)
    Start-Sleep -Milliseconds 350
    $log = Read-Log
    if ($log -notmatch '\[probe\] asset drag begin source=\S+ at=') {
        throw 'The press on the first engine tile did not begin an asset drag.'
    }

    $slotMatch = [regex]::Match($log, '\[probe\] asset slot type=(\w+) rect=(-?\d+),(-?\d+) (\d+)x(\d+)')
    if (-not $slotMatch.Success) {
        throw "Dragging did not highlight an Inspector slot. Log: $($log.Substring([Math]::Max(0, $log.Length - 1200)))"
    }
    $slotX = [int]$slotMatch.Groups[2].Value
    $slotY = [int]$slotMatch.Groups[3].Value
    $slotW = [int]$slotMatch.Groups[4].Value
    $slotH = [int]$slotMatch.Groups[5].Value
    $targetX = [int]($slotX + $slotW * 0.5)
    $targetY = [int]($slotY + $slotH * 0.5)
    Write-Host "[float-drag] slot=$($slotMatch.Groups[1].Value) rect=$slotX,$slotY ${slotW}x${slotH}" -ForegroundColor DarkGray

    [BoltsparkDragShot]::Save($floatWindow,
        (Join-Path $outputDir 'float-drag-label.png'))
    $beforeShot = Join-Path $outputDir 'main-before.png'
    [BoltsparkDragShot]::Save($main, $beforeShot)
    $labelPixels = [BoltsparkDragShot]::CountRgb(
        $beforeShot, 480, 312, 130, 40, 0x45C7A1)
    if ($labelPixels -lt 20) {
        throw 'Translated drag label was not visible beside the cursor in the main editor.'
    }

    # Convert the main-editor scene target into float client coordinates. The
    # editor exposes its HWND rect origin, but scene coordinates start at the
    # client origin; this is the conversion the editor itself must perform.
    $localX = $targetX - $offsetX
    $localY = $targetY - $offsetY
    Send-Mouse $floatWindow 0x0200 ($localX - 6) ($localY - 6)
    Send-Mouse $floatWindow 0x0200 $localX $localY
    Send-Mouse $floatWindow 0x0202 $localX $localY
    Start-Sleep -Milliseconds 600
    $afterShot = Join-Path $outputDir 'main-after.png'
    [BoltsparkDragShot]::Save($main, $afterShot)

    # Before the fix, the synchronous Inspector rebuild redrew main-window
    # chrome with the float's 480x372 size. A 116x20 TITLE_BAR-colored frame
    # was then left over this deterministic viewport region.
    $artifactPixels = [BoltsparkDragShot]::CountRgb(
        $afterShot, 372, 383, 116, 20, 0x1B1C1E)
    if ($artifactPixels -gt 200) {
        throw "Drop left a main-editor chrome artifact ($artifactPixels pixels)."
    }
    $tooltipLeakPixels = [BoltsparkDragShot]::CountRgb(
        $afterShot, 160, 335, 225, 36, 0x1B1C1E)
    if ($tooltipLeakPixels -gt 200) {
        throw "Floating Asset Browser tooltip leaked into the main editor ($tooltipLeakPixels pixels)."
    }

    $log = Read-Log
    if ($log -notmatch '\[probe\] asset drop at=\d+,\d+ target=True') {
        throw "Cross-window drop did not resolve to the Inspector slot. Log: $($log.Substring([Math]::Max(0, $log.Length - 1600)))"
    }
    if ($log -notmatch '\[probe\] inspector asset changed ') {
        throw 'Dropping the asset did not assign it to the Inspector property.'
    }
    if ($log -match '\[probe\] editor resize 480x372') {
        throw 'Float event dispatch leaked sizeOverride and resized the editor.'
    }

    # The project-tree/asset-grid divider now has a centered 14px hit area.
    # Drag from its persisted 118px position and verify that the float's H2D
    # capture receives the gesture and stores the new width.
    Send-Mouse $floatWindow 0x0200 118 210
    Send-Mouse $floatWindow 0x0201 118 210
    Send-Mouse $floatWindow 0x0200 168 210
    Send-Mouse $floatWindow 0x0202 168 210
    Start-Sleep -Milliseconds 350
    $assetStatePath = Join-Path $layoutDir 'asset-browser.json'
    $savedAssetState = Get-Content $assetStatePath -Raw | ConvertFrom-Json
    if ([double]$savedAssetState.folderWidth -lt 150) {
        throw "Floating Asset Browser divider did not move (folderWidth=$($savedAssetState.folderWidth))."
    }
    Write-Host '[float-drag] Floating Asset Browser divider passed.' -ForegroundColor DarkGray
    Write-Host '[float-drag] Cross-window asset drop assigned the Inspector slot.' -ForegroundColor Green
    Write-Host "[float-drag] Evidence: $outputDir"
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
}

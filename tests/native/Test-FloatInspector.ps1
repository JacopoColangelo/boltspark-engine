param(
    [int]$TimeoutSeconds = 25,
    [string]$Executable = 'boltspark.hl'
)

# Regression for synchronous Inspector rebuilds from float controls. The object
# Enabled checkbox commits on EPush; before the fix, all newly-created property
# widgets rendered at 0,0 until a later float layout, collapsing the text.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\float-inspector\$runId"
$localAppData = Join-Path $outputDir 'localappdata'
$layoutDir = Join-Path $localAppData 'Boltspark Engine'
$layoutPath = Join-Path $layoutDir 'dock-layout.json'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
New-Item -ItemType Directory -Force $layoutDir | Out-Null

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
            kind = 'split'; orientation = 'v'; ratio = 0.70
            minFirst = 168; minSecond = 120
            first = & $tab @('boltspark.viewport')
            second = & $tab @('boltspark.assets', 'boltspark.console')
        }
    }
    floating = @(@{
        id = 9; title = 'Inspector'
        x = 300; y = 150; width = 480; height = 560
        minimized = $false
        root = & $tab @('boltspark.inspector')
    })
}
[System.IO.File]::WriteAllText($layoutPath, ($layout | ConvertTo-Json -Depth 20))

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
public static class BoltsparkFloatInspectorApi {
    public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern int GetClassName(IntPtr h, StringBuilder text, int max);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT rect);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT rect);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint message, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint message, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleBitmap(IntPtr dc, int width, int height);
    [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr dc, IntPtr value);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr value);
    [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr dc);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

    public static IntPtr LParam(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }

    public static IntPtr Find(uint pid, string className) {
        IntPtr result = IntPtr.Zero;
        EnumWindows((h, l) => {
            uint owner;
            GetWindowThreadProcessId(h, out owner);
            if (owner != pid) return true;
            var name = new StringBuilder(128);
            GetClassName(h, name, name.Capacity);
            if (name.ToString() == className) result = h;
            return true;
        }, IntPtr.Zero);
        return result;
    }

    public static void Mouse(IntPtr h, uint message, int x, int y) {
        IntPtr ignored;
        SendMessageTimeout(h, message, message == 0x0201 ? (IntPtr)1 : IntPtr.Zero,
            LParam(x, y), 0, 3000, out ignored);
    }

    public static void Save(IntPtr h, string path) {
        RECT rect;
        GetWindowRect(h, out rect);
        int width = rect.Right - rect.Left, height = rect.Bottom - rect.Top;
        using (var image = new Bitmap(width, height)) {
            using (var graphics = Graphics.FromImage(image))
                graphics.CopyFromScreen(rect.Left, rect.Top, 0, 0,
                    new Size(width, height));
            image.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        }
    }

    public static int DifferenceOutsideCheckbox(string beforePath, string afterPath) {
        int changed = 0;
        using (var before = new Bitmap(beforePath))
        using (var after = new Bitmap(afterPath)) {
            int width = Math.Min(before.Width, after.Width);
            int height = Math.Min(before.Height, after.Height);
            for (int y = 0; y < height; y++) {
                for (int x = 0; x < width; x++) {
                    // Enabled box and check glyph are expected to change.
                    if (x < 32 && y >= 108 && y < 142) continue;
                    if (before.GetPixel(x, y).ToArgb() != after.GetPixel(x, y).ToArgb())
                        changed++;
                }
            }
        }
        return changed;
    }
}
"@ -ReferencedAssemblies System.Drawing

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

    $main = [IntPtr]::Zero
    $float = [IntPtr]::Zero
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
        $process.Refresh()
        if ($process.HasExited) { throw "Editor exited early with code $($process.ExitCode)." }
        $main = [BoltsparkFloatInspectorApi]::Find([uint32]$process.Id, 'HL_WIN')
        $float = [BoltsparkFloatInspectorApi]::Find([uint32]$process.Id, 'BoltSparkFloatPanel')
        if ($main -ne [IntPtr]::Zero -and $float -ne [IntPtr]::Zero) { break }
    }
    if ($main -eq [IntPtr]::Zero -or $float -eq [IntPtr]::Zero) {
        throw 'Main editor and floating Inspector HWNDs did not appear.'
    }

    Start-Sleep -Milliseconds 500
    [void][BoltsparkFloatInspectorApi]::SetWindowPos(
        $float, [IntPtr](-1), 40, 40, 0, 0,
        0x0001 -bor 0x0040) # NOSIZE | SHOWWINDOW, HWND_TOPMOST
    [void][BoltsparkFloatInspectorApi]::SetForegroundWindow($float)
    Start-Sleep -Milliseconds 350
    $before = Join-Path $outputDir 'inspector-before.png'
    $during = Join-Path $outputDir 'inspector-during-push.png'
    $after = Join-Path $outputDir 'inspector-after.png'

    # First complete click disables the object and ensures DWM has presented
    # the synthetic topmost float before the screen-based evidence capture.
    [BoltsparkFloatInspectorApi]::Mouse($float, 0x0200, 15, 124)
    [BoltsparkFloatInspectorApi]::Mouse($float, 0x0201, 15, 124)
    [BoltsparkFloatInspectorApi]::Mouse($float, 0x0202, 15, 124)
    Start-Sleep -Milliseconds 500
    [BoltsparkFloatInspectorApi]::Save($float, $before)

    # Hold the second (re-enable) click down long enough to capture its EPush
    # rebuild itself. This is the exact frame that used to collapse all rows.
    [BoltsparkFloatInspectorApi]::Mouse($float, 0x0200, 15, 124)
    [BoltsparkFloatInspectorApi]::Mouse($float, 0x0201, 15, 124)
    Start-Sleep -Milliseconds 450
    [BoltsparkFloatInspectorApi]::Save($float, $during)
    $log = Get-Content $stdout -Raw
    if (($log -notmatch '\[probe\] inspector object enabled=false') -or
            ($log -notmatch '\[probe\] inspector object enabled=true')) {
        throw 'Floating Inspector Enabled checkbox did not commit on push.'
    }
    $pushDifference = [BoltsparkFloatInspectorApi]::DifferenceOutsideCheckbox($before, $during)
    if ($pushDifference -gt 1200) {
        throw "Floating Inspector collapsed during checkbox push ($pushDifference changed pixels)."
    }

    [BoltsparkFloatInspectorApi]::Mouse($float, 0x0202, 15, 124)
    Start-Sleep -Milliseconds 500
    [BoltsparkFloatInspectorApi]::Save($float, $after)
    $releaseDifference = [BoltsparkFloatInspectorApi]::DifferenceOutsideCheckbox($before, $after)
    if ($releaseDifference -gt 1200) {
        throw "Floating Inspector remained collapsed after release ($releaseDifference changed pixels)."
    }

    Write-Host '[float-inspector] Enabled checkbox rebuild kept Inspector layout stable.' -ForegroundColor Green
    Write-Host "[float-inspector] Evidence: $outputDir"

    [void][BoltsparkFloatInspectorApi]::PostMessage(
        $main, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Editor did not close after floating Inspector test.'
    }
    if ((Get-Item $stderr).Length -ne 0) {
        throw "Floating Inspector test wrote stderr; inspect $stderr."
    }
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
}

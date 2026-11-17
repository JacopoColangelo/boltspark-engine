param(
    [int]$TimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$out = Join-Path $repoRoot 'bin\test-results\reveal-root'
$localAppData = Join-Path $out 'localappdata'
New-Item -ItemType Directory -Force $localAppData | Out-Null
$stdout = Join-Path $out 'stdout.log'
$stderr = Join-Path $out 'stderr.log'

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\build.ps1 first.'
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class RevealRootApi {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", SetLastError=true)] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    public static IntPtr LP(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }
}
"@
function Send([IntPtr]$w, [uint32]$m, [IntPtr]$wp, [IntPtr]$lp) {
    $result = [IntPtr]::Zero
    if ([RevealRootApi]::SendMessageTimeout($w, $m, $wp, $lp, 0, 5000, [ref]$result) -eq [IntPtr]::Zero) {
        throw ('Message 0x{0:X} failed.' -f $m)
    }
}
function Click([IntPtr]$w, [int]$x, [int]$y) {
    Send $w 0x0200 ([IntPtr]::Zero) ([RevealRootApi]::LP($x,$y)); Start-Sleep -Milliseconds 70
    Send $w 0x0201 ([IntPtr]1) ([RevealRootApi]::LP($x,$y))
    Send $w 0x0202 ([IntPtr]::Zero) ([RevealRootApi]::LP($x,$y)); Start-Sleep -Milliseconds 160
}
function RightClick([IntPtr]$w, [int]$x, [int]$y) {
    Send $w 0x0200 ([IntPtr]::Zero) ([RevealRootApi]::LP($x,$y)); Start-Sleep -Milliseconds 70
    Send $w 0x0204 ([IntPtr]2) ([RevealRootApi]::LP($x,$y))
    Send $w 0x0205 ([IntPtr]::Zero) ([RevealRootApi]::LP($x,$y)); Start-Sleep -Milliseconds 220
}

$oldProbe = $env:BOLTSPARK_PROBE
$oldLocalAppData = $env:LOCALAPPDATA
$process = $null
try {
    $env:BOLTSPARK_PROBE = '1'
    $env:LOCALAPPDATA = $localAppData
    $process = Start-Process $runtime -ArgumentList 'boltspark.hl' `
        -WorkingDirectory (Join-Path $repoRoot 'bin') `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -NoNewWindow -PassThru

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $window = [IntPtr]::Zero
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
        $process.Refresh()
        if ($process.HasExited) { throw "Editor exited early (code $($process.ExitCode))." }
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
            $window = $process.MainWindowHandle
            break
        }
    }
    if ($window -eq [IntPtr]::Zero) { throw 'Editor HWND did not appear.' }
    [void][RevealRootApi]::SetWindowPos($window, [IntPtr]::Zero, 40, 40, 1440, 900, 0x0004)
    $readyDeadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 150
        $log = Get-Content $stdout -Raw -ErrorAction SilentlyContinue
    } while ($log -notmatch 'editor shell ready' -and [DateTime]::UtcNow -lt $readyDeadline)

    $rect = New-Object RevealRootApi+RECT
    [void][RevealRootApi]::GetClientRect($window, [ref]$rect)
    $consoleY = $rect.Bottom - 20 - 160
    $contentY = $consoleY + 24
    $allRowX = 254 + 60
    $allRowY = $contentY + 48 + 10

    # Right-click the root "All" folder, then choose Reveal in Explorer. With no
    # project loaded this used to throw from normalizeRelative(""); it should
    # now ask the user to create a project instead of opening a stray folder.
    RightClick $window $allRowX $allRowY
    $menuY = [Math]::Min($allRowY, $rect.Bottom - (5 * 22 + 6) - 4)
    Click $window ($allRowX + 40) ($menuY + 3 + 4 * 22 + 11)
    Start-Sleep -Milliseconds 400

    $final = Get-Content $stdout -Raw
    if ($final -notmatch '\[probe\] project required for reveal files in Explorer') {
        throw 'Reveal in Explorer did not request a project.'
    }
    if ($final -notmatch '\[probe\] file dialog save') {
        throw 'Reveal in Explorer did not route to project creation.'
    }
    if ($final -match '\[probe\] reveal path=') {
        throw 'Reveal in Explorer should not open a directory without a project.'
    }
    if ($final -match 'Uncaught Exception|Project path cannot be empty') {
        throw 'Reveal in Explorer still throws for the root folder.'
    }
    if ((Get-Item $stderr).Length -ne 0) {
        throw 'Reveal in Explorer wrote to stderr.'
    }

    [void][RevealRootApi]::PostMessage($window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Editor did not close after the reveal-root probe.'
    }
    $process = $null
    Write-Host '[reveal-root] no-project reveal prompts project creation cleanly.' -ForegroundColor Green
    Write-Host "[reveal-root] Evidence: $out"
} finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
}

param(
    [int]$TimeoutSeconds = 20
)

# Window-scoped probe for the Editor Keybindings window. It opens the window
# from the editor menu, confirms all actions are present, then shrinks the HWND
# and verifies the binding list becomes scrollable instead of clipping rows.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$outputDir = Join-Path $repoRoot 'bin\test-results\keybindings-list'
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'

New-Item -ItemType Directory -Force $outputDir | Out-Null

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class KeybindingsListNative {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder text, int length);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    public static IntPtr Point(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }
}
"@

function Find-VisibleWindow([int]$processId, [string]$titlePrefix) {
    $script:matchedWindow = [IntPtr]::Zero
    $callback = [KeybindingsListNative+EnumProc]{ param($window, $unused)
        $windowPid = [uint32]0
        [void][KeybindingsListNative]::GetWindowThreadProcessId($window, [ref]$windowPid)
        if ($windowPid -eq $processId -and [KeybindingsListNative]::IsWindowVisible($window)) {
            $title = [Text.StringBuilder]::new(256)
            [void][KeybindingsListNative]::GetWindowText($window, $title, $title.Capacity)
            if ($title.ToString().StartsWith($titlePrefix)) { $script:matchedWindow = $window; return $false }
        }
        return $true
    }
    [void][KeybindingsListNative]::EnumWindows($callback, [IntPtr]::Zero)
    return $script:matchedWindow
}

function Send-Click([IntPtr]$window, [int]$x, [int]$y) {
    [void][KeybindingsListNative]::PostMessage($window, 0x0200, [IntPtr]::Zero, [KeybindingsListNative]::Point($x, $y))
    Start-Sleep -Milliseconds 100
    [void][KeybindingsListNative]::PostMessage($window, 0x0201, [IntPtr]1, [KeybindingsListNative]::Point($x, $y))
    [void][KeybindingsListNative]::PostMessage($window, 0x0202, [IntPtr]::Zero, [KeybindingsListNative]::Point($x, $y))
}

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\build.ps1 first.'
}
Get-Process hl -ErrorAction SilentlyContinue | Stop-Process -Force

$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
$probeLog = Join-Path $outputDir 'keybindings-state.log'
$previousProbeFlag = $env:BOLTSPARK_PROBE
$previousProbeLog = $env:BOLTSPARK_PROBE_LOG
$env:BOLTSPARK_PROBE = '1'
$env:BOLTSPARK_PROBE_LOG = $probeLog
$process = Start-Process $runtime -ArgumentList 'boltspark.hl' `
    -WorkingDirectory (Join-Path $repoRoot 'bin') `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
    -NoNewWindow -PassThru
try {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $editor = [IntPtr]::Zero
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 125
        $process.Refresh()
        if ($process.HasExited) { throw "Boltspark exited early (code $($process.ExitCode))." }
        $editor = Find-VisibleWindow $process.Id 'Boltspark Engine'
        if ($editor -ne [IntPtr]::Zero) { break }
    }
    if ($editor -eq [IntPtr]::Zero) { throw 'Editor HWND missing.' }
    Start-Sleep -Seconds 2

    Send-Click $editor 60 15
    Start-Sleep -Milliseconds 400
    Send-Click $editor 110 46
    Start-Sleep -Milliseconds 400
    Send-Click $editor 280 46

    $keybindings = [IntPtr]::Zero
    $childDeadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $childDeadline) {
        Start-Sleep -Milliseconds 150
        foreach ($candidate in (Get-Process hl -ErrorAction SilentlyContinue | Where-Object Id -ne $process.Id)) {
            $candidateWindow = Find-VisibleWindow $candidate.Id 'Editor Keybindings'
            if ($candidateWindow -ne [IntPtr]::Zero) { $keybindings = $candidateWindow; break }
        }
        if ($keybindings -ne [IntPtr]::Zero) { break }
    }
    if ($keybindings -eq [IntPtr]::Zero) { throw 'Editor Keybindings HWND missing.' }
    Start-Sleep -Seconds 1

    if (-not (Test-Path $probeLog)) {
        throw 'Keybindings window did not emit probe state.'
    }
    $state = Get-Content $probeLog -Raw
    if ($state -notmatch '\[keybindings\] rows=14') {
        throw 'Keybindings list did not report all 14 actions.'
    }
    if ($state -notmatch 'scrollable=(?i:false)') {
        throw 'Default keybindings window was unexpectedly scrollable.'
    }

    # SWP_NOZORDER | SWP_NOACTIVATE; shrink below the full 14-row list height.
    [void][KeybindingsListNative]::SetWindowPos($keybindings, [IntPtr]::Zero,
        0, 0, 420, 360, 0x0004 -bor 0x0010)
    Start-Sleep -Seconds 1

    $state = Get-Content $probeLog -Raw
    if ($state -notmatch 'scrollable=(?i:true)') {
        throw 'Shrunk keybindings window did not switch its list to scrollable.'
    }
    if ((Get-Item $stderr).Length -ne 0) {
        throw "Keybindings list probe wrote stderr; inspect $stderr."
    }

    [void][KeybindingsListNative]::PostMessage($editor, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Boltspark did not close after the keybindings list probe.'
    }
    Write-Host '[keybindings] 14-action list is scrollable when the window shrinks.' -ForegroundColor Green
}
finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    Get-Process hl -ErrorAction SilentlyContinue | Stop-Process -Force
    if ($null -eq $previousProbeFlag) {
        Remove-Item Env:BOLTSPARK_PROBE -ErrorAction SilentlyContinue
    } else {
        $env:BOLTSPARK_PROBE = $previousProbeFlag
    }
    if ($null -eq $previousProbeLog) {
        Remove-Item Env:BOLTSPARK_PROBE_LOG -ErrorAction SilentlyContinue
    } else {
        $env:BOLTSPARK_PROBE_LOG = $previousProbeLog
    }
}

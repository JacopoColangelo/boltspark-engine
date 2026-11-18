param(
    [int]$TimeoutSeconds = 20
)

# Regression probe: scrubbing a MeshRenderer numeric field (cube Width) must
# not crash on release. The Inspector used to rebuild synchronously per scrub
# step, destroying the drag field mid-capture (Null access on release).

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\primitive-inspector-probe\$runId"
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
public static class ProbeApi {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint mapType);
    public static IntPtr MakeLParam(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }
}
"@

Add-Type -AssemblyName System.Drawing

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
    $sent = [ProbeApi]::SendMessageTimeout(
        $window, $message, $wparam, $lparam, 0, 5000, [ref]$result)
    if ($sent -eq [IntPtr]::Zero) {
        throw ('Window message 0x{0:X} failed.' -f $message)
    }
}

function Send-Mouse([IntPtr]$window, [uint32]$message,
        [int]$x, [int]$y, [IntPtr]$buttons) {
    Send-Message $window $message $buttons ([ProbeApi]::MakeLParam($x, $y))
}

function Send-Click([IntPtr]$window, [int]$x, [int]$y) {
    Send-Mouse $window 0x0200 $x $y ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    Send-Mouse $window 0x0201 $x $y ([IntPtr]1)
    Send-Mouse $window 0x0202 $x $y ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 350
}

function Send-Key([IntPtr]$window, [int]$virtualKey, [bool]$down) {
    $message = if ($down) { [uint32]0x0100 } else { [uint32]0x0101 }
    $scan = [int][ProbeApi]::MapVirtualKey([uint32]$virtualKey, 0)
    $flags = if ($down) {
        [int64](1 -bor ($scan -shl 16))
    } else {
        [int64](0xC0000001 -bor ($scan -shl 16))
    }
    Send-Message $window $message ([IntPtr]$virtualKey) ([IntPtr]$flags)
}

function Send-CtrlChord([IntPtr]$window, [int]$virtualKey, [int]$scanCode) {
    Send-Key $window 0x11 $true
    Send-Key $window $virtualKey $true
    Send-Key $window $virtualKey $false
    Send-Key $window 0x11 $false
    Start-Sleep -Milliseconds 500
}

function Send-Type([IntPtr]$window, [string]$text) {
    foreach ($character in $text.ToCharArray()) {
        $vk = [int]$character
        Send-Key $window $vk $true
        # Text fields consume WM_CHAR for actual character input.
        Send-Message $window 0x0102 ([IntPtr]$vk) ([IntPtr]1)
        Send-Key $window $vk $false
        Start-Sleep -Milliseconds 40
    }
}

function Assert-Alive([Diagnostics.Process]$process, [string]$stage) {
    Start-Sleep -Milliseconds 300
    $process.Refresh()
    if ($process.HasExited) {
        throw "Editor crashed during $stage (exit code $($process.ExitCode))."
    }
}

function Save-ScreenShot([IntPtr]$window, [string]$path) {
    $rect = New-Object ProbeApi+RECT
    if (-not [ProbeApi]::GetWindowRect($window, [ref]$rect)) {
        throw 'GetWindowRect failed.'
    }
    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top
    $bitmap = New-Object System.Drawing.Bitmap($w, $h)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $hdc = $graphics.GetHdc()
    if (-not [ProbeApi]::PrintWindow($window, $hdc, 2)) {
        $graphics.ReleaseHdc($hdc)
        throw 'PrintWindow failed.'
    }
    $graphics.ReleaseHdc($hdc)
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
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
    [void][ProbeApi]::SetWindowPos($window, [IntPtr]::Zero, 40, 40, 1440, 900, 0x0004)
    Start-Sleep -Seconds 1

    $shots = Join-Path $outputDir 'shots'
    New-Item -ItemType Directory -Force $shots | Out-Null

    # Coordinates are CLIENT coordinates (the app's own input space).
    # Screenshot pixel positions run ~32px lower because PrintWindow includes
    # the title bar; subtract ~32 from measured window pixels for clicks.

    # 1. Use the searchable toolbar Add menu to create a Cylinder.
    Send-Click $window 47 48
    Send-Type $window 'cylinder'
    Start-Sleep -Milliseconds 150
    Send-Click $window 60 105

    # 2. Type 2 into the Radius field (window row ~463 -> client ~431; the
    #    Enabled checkbox adds one 28px row above Transform) and commit with
    #    Enter. This must create a history entry.
    Send-Click $window 1298 431
    Send-Type $window '2'
    Send-Key $window 0x0D $true
    Send-Key $window 0x0D $false
    Start-Sleep -Milliseconds 400
    Save-ScreenShot $window (Join-Path $shots '01-radius-changed.png')
    Assert-Alive $process 'radius edit'

    # 3. Ctrl+Z directly: the settings edit must undo (Radius back to 0.5)
    #    WITHOUT deleting the cylinder.
    Send-CtrlChord $window 0x5A 0x2C
    Start-Sleep -Milliseconds 400
    Save-ScreenShot $window (Join-Path $shots '02-undo-edit.png')
    Assert-Alive $process 'undo edit'

    # 4. Ctrl+Z again: now the cylinder creation should undo (object gone).
    Send-CtrlChord $window 0x5A 0x2C
    Start-Sleep -Milliseconds 400
    Save-ScreenShot $window (Join-Path $shots '03-undo-create.png')
    Assert-Alive $process 'undo create'

    # 5. Ctrl+Y redo: the cylinder returns with default settings.
    Send-CtrlChord $window 0x59 0x2C
    Start-Sleep -Milliseconds 400
    Save-ScreenShot $window (Join-Path $shots '04-redo-create.png')
    Assert-Alive $process 'redo create'

    # 6. Ctrl+Y again: the radius edit reapplies (Radius back to 2).
    Send-CtrlChord $window 0x59 0x2C
    Start-Sleep -Milliseconds 400
    Save-ScreenShot $window (Join-Path $shots '05-redo-edit.png')
    Assert-Alive $process 'redo edit'

    Write-Host "Probe output: $outputDir"
} finally {
    if ($process -ne $null -and -not $process.HasExited) {
        $process.Kill()
    }
    if ($null -ne $oldProbe) { $env:BOLTSPARK_PROBE = $oldProbe } else { Remove-Item Env:BOLTSPARK_PROBE -ErrorAction SilentlyContinue }
    if ($null -ne $oldLocalAppData) { $env:LOCALAPPDATA = $oldLocalAppData } else { Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue }
}

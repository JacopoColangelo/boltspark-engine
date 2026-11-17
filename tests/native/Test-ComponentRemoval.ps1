param(
    [int]$TimeoutSeconds = 20
)

# Native regression probe for the Inspector's per-component remove action.
# Clicks the MeshRenderer header trash button on the starter sampleCube, then
# verifies the command entered history and survives undo/redo.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\component-removal\$runId"
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
public static class ComponentRemovalApi {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
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

function Send-Message([IntPtr]$window, [uint32]$message,
        [IntPtr]$wparam, [IntPtr]$lparam) {
    $result = [IntPtr]::Zero
    $sent = [ComponentRemovalApi]::SendMessageTimeout(
        $window, $message, $wparam, $lparam, 0, 5000, [ref]$result)
    if ($sent -eq [IntPtr]::Zero) {
        throw ('Window message 0x{0:X} failed.' -f $message)
    }
}

function Send-Mouse([IntPtr]$window, [uint32]$message,
        [int]$x, [int]$y, [IntPtr]$buttons) {
    Send-Message $window $message $buttons ([ComponentRemovalApi]::MakeLParam($x, $y))
}

function Send-Click([IntPtr]$window, [int]$x, [int]$y) {
    Send-Mouse $window 0x0200 $x $y ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    Send-Mouse $window 0x0201 $x $y ([IntPtr]1)
    Send-Mouse $window 0x0202 $x $y ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 400
}

function Send-Key([IntPtr]$window, [int]$virtualKey, [int]$scanCode, [bool]$down) {
    $message = if ($down) { [uint32]0x0100 } else { [uint32]0x0101 }
    $flags = if ($down) {
        [int64](1 -bor ($scanCode -shl 16))
    } else {
        [int64](0xC0000001 -bor ($scanCode -shl 16))
    }
    Send-Message $window $message ([IntPtr]$virtualKey) ([IntPtr]$flags)
}

function Send-CtrlChord([IntPtr]$window, [int]$virtualKey, [int]$scanCode) {
    Send-Key $window 0x11 0x1D $true
    Send-Key $window $virtualKey $scanCode $true
    Send-Key $window $virtualKey $scanCode $false
    Send-Key $window 0x11 0x1D $false
    Start-Sleep -Milliseconds 450
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
    [void][ComponentRemovalApi]::SetWindowPos(
        $window, [IntPtr]::Zero, 40, 40, 1440, 900, 0x0004)
    Start-Sleep -Seconds 1

    $rect = New-Object ComponentRemovalApi+RECT
    if (-not [ComponentRemovalApi]::GetClientRect($window, [ref]$rect)) {
        throw 'GetClientRect failed.'
    }
    $width = $rect.Right - $rect.Left

    # Inspector layout: bodyTop=66, panel header=32, meta=22, Object section=53,
    # Transform section=109, then the MeshRenderer header starts at +162. The
    # trash button sits 2px into that 24px header at the right edge (22px wide).
    $removeX = [int][Math]::Round($width - 22)
    $removeY = 294
    Send-Click $window $removeX $removeY
    Send-CtrlChord $window 0x5A 0x2C # Ctrl+Z
    Send-CtrlChord $window 0x59 0x15 # Ctrl+Y

    [void][ComponentRemovalApi]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Editor did not close after the component-removal probe.'
    }
    if ((Get-Item $stderr).Length -ne 0) {
        throw "Component-removal probe wrote stderr; inspect $stderr."
    }

    $log = Get-Content $stdout -Raw
    if ($log -notmatch '\[console\] component: removed MeshRenderer from sampleCube') {
        throw 'Clicking the MeshRenderer header remove action did not remove the component.'
    }
    if ($log -notmatch '\[history\] undo label=Remove MeshRenderer object=sampleCube') {
        throw 'Component removal did not enter history (undo missing).'
    }
    if ($log -notmatch '\[history\] redo label=Remove MeshRenderer object=sampleCube') {
        throw 'Component removal redo did not restore the component.'
    }
    Write-Host '[component-removal] header remove action, history undo, and redo passed.'
}
finally {
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
}

param(
    [int]$TimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\command-history\$runId"
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
public static class BoltsparkCommandHistoryApi {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", SetLastError=true)] public static extern bool GetClientRect(IntPtr h, out RECT r);
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
    $sent = [BoltsparkCommandHistoryApi]::SendMessageTimeout(
        $window, $message, $wparam, $lparam, 0, 5000, [ref]$result)
    if ($sent -eq [IntPtr]::Zero) {
        throw ('Window message 0x{0:X} failed.' -f $message)
    }
}

function Send-Mouse([IntPtr]$window, [uint32]$message,
        [int]$x, [int]$y, [IntPtr]$buttons) {
    Send-Message $window $message $buttons `
        ([BoltsparkCommandHistoryApi]::MakeLParam($x, $y))
}

function Send-Key([IntPtr]$window, [int]$virtualKey, [int]$scanCode,
        [bool]$down) {
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
    Start-Sleep -Milliseconds 500
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
    [void][BoltsparkCommandHistoryApi]::SetWindowPos(
        $window, [IntPtr]::Zero, 40, 40, 1440, 900, 0x0004)
    Start-Sleep -Seconds 1

    $rect = New-Object BoltsparkCommandHistoryApi+RECT
    if (-not [BoltsparkCommandHistoryApi]::GetClientRect($window, [ref]$rect)) {
        throw 'GetClientRect failed.'
    }
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    $bodyTop = 66.0
    $bodyHeight = [Math]::Max(0, $height - $bodyTop - 20)
    $panelSpace = [Math]::Max(0, $width - 8)
    $viewportWidth = $panelSpace - 250 - 318
    $viewportHeight = $bodyHeight - 160 - 4
    $centerX = [int][Math]::Round(254 + $viewportWidth * 0.5)
    $centerY = [int][Math]::Round($bodyTop + $viewportHeight * 0.5)

    # Drag the Move center handle. Probe mode keeps absolute mouse input so all
    # events remain addressed to this HWND and never affect another program.
    Send-Mouse $window 0x0200 $centerX $centerY ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 250
    Send-Mouse $window 0x0201 $centerX $centerY ([IntPtr]1)
    for ($step = 1; $step -le 10; $step++) {
        Send-Mouse $window 0x0200 ($centerX + $step * 8) `
            ($centerY - $step * 2) ([IntPtr]1)
        Start-Sleep -Milliseconds 35
    }
    Send-Mouse $window 0x0202 ($centerX + 80) ($centerY - 20) ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 600

    Send-CtrlChord $window 0x5A 0x2C # Ctrl+Z
    Send-CtrlChord $window 0x59 0x15 # Ctrl+Y

    # Step Position X through the Inspector's up arrow. The retained control
    # brackets this as one transform gesture even though the command is routed
    # through the same callback used by text edits and scrubs.
    $positionXUp = [int][Math]::Round(($width - 318) + 122)
    $positionRowUp = 205
    Send-Mouse $window 0x0200 $positionXUp $positionRowUp ([IntPtr]::Zero)
    Send-Mouse $window 0x0201 $positionXUp $positionRowUp ([IntPtr]1)
    Send-Mouse $window 0x0202 $positionXUp $positionRowUp ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 500
    Send-CtrlChord $window 0x5A 0x2C # undo Inspector step
    Send-CtrlChord $window 0x59 0x15 # redo Inspector step

    # Create Cube2 from the native Add palette, undo/redo its structural
    # command, then delete it and repeat. This verifies renderer-view creation
    # and disposal in addition to the pure session regression.
    Send-Mouse $window 0x0200 47 48 ([IntPtr]::Zero)
    Send-Mouse $window 0x0201 47 48 ([IntPtr]1)
    Send-Mouse $window 0x0202 47 48 ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 300
    Send-Mouse $window 0x0200 50 115 ([IntPtr]::Zero)
    Send-Mouse $window 0x0201 50 115 ([IntPtr]1)
    Send-Mouse $window 0x0202 50 115 ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 600
    Send-CtrlChord $window 0x5A 0x2C # undo Create Cube2
    Send-CtrlChord $window 0x59 0x15 # redo Create Cube2

    Send-Key $window 0x2E 0x53 $true # Delete
    Send-Key $window 0x2E 0x53 $false
    Start-Sleep -Milliseconds 500
    Send-CtrlChord $window 0x5A 0x2C # undo Delete Cube2
    Send-CtrlChord $window 0x59 0x15 # redo Delete Cube2

    [void][BoltsparkCommandHistoryApi]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Editor did not close after command-history test.'
    }
    if ((Get-Item $stderr).Length -ne 0) {
        throw "Command-history test wrote stderr; inspect $stderr."
    }

    $log = Get-Content $stdout -Raw
    $undo = [regex]::Match($log,
        '\[history\] undo label=Move sampleCube object=sampleCube position=\(([^)]*)\)')
    $redo = [regex]::Match($log,
        '\[history\] redo label=Move sampleCube object=sampleCube position=\(([^)]*)\)')
    if (-not $undo.Success) { throw 'Ctrl+Z did not execute the gizmo command undo.' }
    if (-not $redo.Success) { throw 'Ctrl+Y did not execute the gizmo command redo.' }
    if ($undo.Groups[1].Value -ne '0, 0, 0') {
        throw "Undo did not restore the origin: $($undo.Groups[1].Value)."
    }
    if ($redo.Groups[1].Value -eq '0, 0, 0') {
        throw 'Redo did not restore the moved transform.'
    }
    # The Move center drag resolves in the camera plane, so its Z depends on
    # the current camera/gizmo math. Derive the untouched Y/Z from the live
    # Move redo instead of hard-coding a stale literal, and assert only that
    # the Inspector X undo/redo changes X while preserving the other axes.
    $movedPosition = $redo.Groups[1].Value
    $inspectorUndo = [regex]::Match($log,
        '\[history\] undo label=Edit sampleCube Position X object=sampleCube position=\(([^)]*)\)')
    $inspectorRedo = [regex]::Match($log,
        '\[history\] redo label=Edit sampleCube Position X object=sampleCube position=\(([^)]*)\)')
    if (-not $inspectorUndo.Success) { throw 'Inspector Position X undo did not run.' }
    if (-not $inspectorRedo.Success) { throw 'Inspector Position X redo did not run.' }
    if ($inspectorUndo.Groups[1].Value -ne $movedPosition) {
        throw "Inspector undo did not restore the pre-step transform: $($inspectorUndo.Groups[1].Value) != $movedPosition."
    }
    $axes = $movedPosition -split ', '
    if ($axes.Count -ne 3) { throw "Unexpected Move position format: $movedPosition." }
    $expectedStep = @('-0.9', $axes[1], $axes[2]) -join ', '
    if ($inspectorRedo.Groups[1].Value -ne $expectedStep) {
        throw "Inspector redo did not restore its stepped value: $($inspectorRedo.Groups[1].Value) != $expectedStep."
    }
    if ($log -notmatch '\[history\] undo label=Create Cube2 object=sampleCube') {
        throw 'Create undo did not remove Cube2 and restore the prior selection.'
    }
    if ($log -notmatch '\[history\] redo label=Create Cube2 object=Cube2 position=\(3, 0, 0\)') {
        throw 'Create redo did not restore and select Cube2.'
    }
    if ($log -notmatch '\[history\] undo label=Delete Cube2 object=Cube2 position=\(3, 0, 0\)') {
        throw 'Delete undo did not restore Cube2 and its selection.'
    }
    if ($log -notmatch '\[history\] redo label=Delete Cube2 object=sampleCube') {
        throw 'Delete redo did not remove Cube2 and select the remaining object.'
    }

    Write-Host '[history] Native gizmo/Inspector/create/delete Ctrl+Z/Ctrl+Y passed.' -ForegroundColor Green
    Write-Host "[history] Evidence: $outputDir"
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
}

param(
    [int]$TimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\splitter-capture\$runId"
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
public static class BoltsparkSplitterCaptureApi {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct GUITHREADINFO {
        public int cbSize;
        public int flags;
        public IntPtr hwndActive;
        public IntPtr hwndFocus;
        public IntPtr hwndCapture;
        public IntPtr hwndMenuOwner;
        public IntPtr hwndMoveSize;
        public IntPtr hwndCaret;
        public RECT rcCaret;
    }
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool GetGUIThreadInfo(uint threadId, ref GUITHREADINFO info);
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

function Send-Mouse([IntPtr]$window, [uint32]$message, [int]$x, [int]$y, [IntPtr]$buttons) {
    $result = [IntPtr]::Zero
    $sent = [BoltsparkSplitterCaptureApi]::SendMessageTimeout(
        $window, $message, $buttons,
        [BoltsparkSplitterCaptureApi]::MakeLParam($x, $y),
        0, 5000, [ref]$result)
    if ($sent -eq [IntPtr]::Zero) {
        throw ('Mouse message 0x{0:X} failed at ({1},{2}).' -f $message, $x, $y)
    }
}

function Get-Capture([IntPtr]$window) {
    $procId = [uint32]0
    $threadId = [BoltsparkSplitterCaptureApi]::GetWindowThreadProcessId($window, [ref]$procId)
    $info = New-Object BoltsparkSplitterCaptureApi+GUITHREADINFO
    $info.cbSize = [Runtime.InteropServices.Marshal]::SizeOf(
        [type]'BoltsparkSplitterCaptureApi+GUITHREADINFO')
    if (-not [BoltsparkSplitterCaptureApi]::GetGUIThreadInfo($threadId, [ref]$info)) {
        throw "GetGUIThreadInfo failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
    return $info.hwndCapture
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
    [void][BoltsparkSplitterCaptureApi]::SetWindowPos(
        $window, [IntPtr]::Zero, 100, 100, 1440, 900, 0x0004)
    Start-Sleep -Milliseconds 1200

    # h2d capture only sees events that reach Heaps. The splitter must also hold
    # Win32 capture, otherwise releasing the button after the cursor leaves the
    # client area never produces an ERelease and the drag stays active forever.
    $before = Get-Capture $window
    if ($before -ne [IntPtr]::Zero) {
        throw 'Editor unexpectedly held mouse capture before the drag.'
    }

    Send-Mouse $window 0x0200 250 300 ([IntPtr]::Zero)
    Send-Mouse $window 0x0201 250 300 ([IntPtr]1)
    Start-Sleep -Milliseconds 300
    $during = Get-Capture $window
    if ($during -ne $window) {
        throw 'Splitter drag did not take Win32 mouse capture.'
    }

    for ($step = 1; $step -le 10; $step++) {
        Send-Mouse $window 0x0200 (250 + $step * 10) 300 ([IntPtr]1)
        Start-Sleep -Milliseconds 25
    }
    Send-Mouse $window 0x0202 350 300 ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 400
    $after = Get-Capture $window
    if ($after -ne [IntPtr]::Zero) {
        throw 'Splitter drag did not release Win32 mouse capture.'
    }

    if ((Get-Item $stderr).Length -ne 0) {
        throw "Splitter capture probe wrote stderr; inspect $stderr."
    }
    Write-Host '[splitter] Win32 mouse capture taken for splitters and released on end.' -ForegroundColor Green
    Write-Host "[splitter] Evidence: $outputDir"
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
}
